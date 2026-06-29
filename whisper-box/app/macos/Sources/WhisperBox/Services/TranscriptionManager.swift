import Foundation
import SwiftData
import Observation

/// App-scoped owner of running transcriptions. Tasks live here (not in any view),
/// so jobs keep running across tab switches and progress is observable anywhere.
/// In-process equivalent of the old job_queue + ws_manager.
@MainActor
@Observable
final class TranscriptionManager {
    /// Live state for an in-flight job, keyed by job id.
    struct RunState {
        var progress: Double = 0          // 0…1
        var liveText: String = ""
        var status: JobStatus = .running
        var segments: [TranscriptSegment] = []
        var preparingModel = false        // first-run model load/download
    }

    /// Claude enhancement state per job.
    struct EnhancementState {
        var running = false
        var text = ""
        var error: String?
    }

    private(set) var runs: [UUID: RunState] = [:]
    private(set) var enhancements: [UUID: EnhancementState] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let engine = TranscriptionEngineFactory.make()
    private let enhancer = EnhancementService()
    private let power = PowerAssertion()   // §10.3 Layer 1 — prevent idle sleep while transcribing

    var modelContext: ModelContext?

    /// Returns the job id immediately; transcription runs in the background.
    @discardableResult
    func start(filePath: String, language: String? = nil) -> UUID {
        let url = URL(fileURLWithPath: filePath)
        let job = TranscriptionJob(sourcePath: filePath, sourceFilename: url.lastPathComponent)
        job.status = .running
        modelContext?.insert(job)
        try? modelContext?.save()

        let id = job.id
        runs[id] = RunState()
        power.acquire(reason: "WhisperBox is transcribing")
        let lang = language ?? transcriptionLanguage()
        tasks[id] = Task { [weak self] in
            await self?.run(jobID: id, job: job, filePath: filePath, language: lang)
        }
        return id
    }

    /// Configured transcription language ("" = auto-detect → nil).
    func transcriptionLanguage() -> String? {
        let l = settings()?.defaultLanguage ?? ""
        return l.isEmpty ? nil : l
    }

    /// All transcripts/summaries are written here (not next to the source file).
    static var transcriptsDir: URL { AppPaths.transcriptsDir }

    private func outputURL(forSource source: String, ext: String) -> URL {
        let base = URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
        return AppPaths.transcriptsDir.appendingPathComponent("\(base).\(ext)")
    }

    /// Load the model in the background (e.g. while recording) so transcription
    /// starts instantly when the recording stops.
    func prewarm() { Task { await engine.prewarm() } }

    /// Persist an already-produced transcript (the live recording result) as a
    /// completed job — no redundant batch pass. A full re-transcribe stays
    /// available on demand via `start(filePath:)`.
    func saveRecordingResult(filePath: String, transcript: String) {
        let url = URL(fileURLWithPath: filePath)
        let job = TranscriptionJob(sourcePath: filePath, sourceFilename: url.lastPathComponent)
        job.status = .success
        job.progress = 100
        job.transcriptText = transcript
        let outURL = outputURL(forSource: filePath, ext: "txt")
        try? transcript.write(to: outURL, atomically: true, encoding: .utf8)
        job.outputPath = outURL.path
        modelContext?.insert(job)
        try? modelContext?.save()
        if let s = settings(), s.claudeAutoAfterTranscribe { enhance(jobID: job.id) }
    }

    func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        runs[id]?.status = .cancelled
    }

    var hasRunningJobs: Bool { runs.values.contains { $0.status == .running } }

    private func run(jobID: UUID, job: TranscriptionJob, filePath: String, language: String?) async {
        do {
            // First-run model load/download — show "Preparing model…".
            runs[jobID]?.preparingModel = true
            await engine.prewarm()
            runs[jobID]?.preparingModel = false

            // Note: don't capture the @Model `job` in this @Sendable closure (data race).
            // Live progress is tracked in `runs[jobID]`; the model is updated on completion.
            let segs = try await engine.transcribe(audioPath: filePath, language: language) { [weak self] frac, text in
                Task { @MainActor in
                    guard let self else { return }
                    self.runs[jobID]?.progress = frac
                    if !text.isEmpty { self.runs[jobID]?.liveText = text }
                }
            }

            if Task.isCancelled {
                runs[jobID]?.status = .cancelled
                job.status = .cancelled
                try? modelContext?.save()
                Log.transcription.info("Transcription cancelled", job: job)
            } else {
                runs[jobID]?.segments = segs
                runs[jobID]?.progress = 1
                runs[jobID]?.status = .success

                // Write output in the configured format; keep plain text for Claude.
                let fmt = OutputFormat(rawValue: settings()?.defaultOutputFormat ?? "txt") ?? .txt
                let rendered = OutputFormatter.render(segs, as: fmt)
                let outURL = outputURL(forSource: filePath, ext: fmt.rawValue)
                try? rendered.write(to: outURL, atomically: true, encoding: .utf8)
                job.status = .success
                job.progress = 100
                job.outputPath = outURL.path
                job.outputFormat = fmt.rawValue
                job.transcriptText = OutputFormatter.render(segs, as: .txt)
                if let end = segs.last?.end, end > 0 { job.durationAudio = end }
                try? modelContext?.save()
                Log.transcription.success("Transcription complete", job: job, detail: "\(segs.count) segments")

                if let s = settings(), s.claudeAutoAfterTranscribe {
                    enhance(jobID: jobID)
                }
            }
        } catch {
            runs[jobID]?.preparingModel = false
            runs[jobID]?.status = .error
            job.status = .error
            job.errorMessage = error.localizedDescription
            try? modelContext?.save()
            Log.transcription.error("Transcription failed", job: job, detail: error.localizedDescription)
        }
        tasks[jobID] = nil
        if !hasRunningJobs { power.release() }
    }

    // MARK: - Claude enhancement (§ Phase 4)

    func enhance(jobID: UUID) {
        guard let job = fetchJob(jobID), !job.transcriptText.isEmpty else { return }
        guard EnhancementService.isAvailable else {
            enhancements[jobID] = EnhancementState(running: false,
                error: "claude CLI not found — install @anthropic-ai/claude-code and sign in.")
            Log.enhancement.warning("claude CLI not found", job: job)
            return
        }
        let text = job.transcriptText
        let source = job.sourcePath
        let s = settings()
        let prompt = s?.claudePrompt ?? EnhancementService.defaultPrompt
        let model = s?.claudeModel ?? "claude-opus-4-8"
        enhancements[jobID] = EnhancementState(running: true)
        Task {
            do {
                let result = try await enhancer.enhance(text, prompt: prompt, model: model)
                let url = outputURL(forSource: source, ext: "summary.md")
                try? result.write(to: url, atomically: true, encoding: .utf8)
                enhancements[jobID] = EnhancementState(running: false, text: result)
                job.summaryPath = url.path
                try? modelContext?.save()
                Log.enhancement.success("Claude summary generated", job: job)
            } catch {
                enhancements[jobID] = EnhancementState(running: false, error: error.localizedDescription)
                Log.enhancement.error("Claude summary failed", job: job, detail: error.localizedDescription)
            }
        }
    }

    private func fetchJob(_ id: UUID) -> TranscriptionJob? {
        guard let ctx = modelContext else { return nil }
        return try? ctx.fetch(FetchDescriptor<TranscriptionJob>(predicate: #Predicate { $0.id == id })).first
    }

    private func settings() -> AppSettings? {
        guard let ctx = modelContext else { return nil }
        return try? ctx.fetch(FetchDescriptor<AppSettings>()).first
    }
}
