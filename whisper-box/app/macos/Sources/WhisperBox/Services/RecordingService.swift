import Foundation
import Observation
import ScreenCaptureKit

enum RecordingState: String, Codable {
    case idle, recording, paused, stopped, endedBySleep   // §10.4
}

/// In-process recording orchestration (replaces the SCRecorder subprocess).
/// App-scoped so recording survives navigation; pause gates the writer; the
/// sleep hook finalizes a valid WAV instead of a truncated fragment (§10.3).
@MainActor
@Observable
final class RecordingService {
    private(set) var state: RecordingState = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastError: String?
    private(set) var outputURL: URL?

    /// Phase 5 — live transcript preview during recording.
    let live = LiveTranscriber()
    var liveEnabled = true

    private let power = PowerAssertion()   // §10.3 Layer 1 — prevent idle sleep

    /// Set by the app — used to route a finished recording to transcription.
    weak var transcriptionManager: TranscriptionManager?

    private var writer: WAVWriter?
    private var mixer: AudioMixer?
    private var systemCapturer: SystemAudioCapturer?
    private var micCapturer: MicCapturer?
    private var stream: SCStream?
    private var timer: Timer?
    private var startedAt: Date?
    private var pausedAccum: TimeInterval = 0
    private var pauseStartedAt: Date?

    private static var recordingsDir: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Whisper Memory/recordings")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `captureSystem` uses ScreenCaptureKit (needs Screen Recording permission).
    /// With it off, only the mic is recorded → no screen-recording prompt.
    func start(captureSystem: Bool, captureMic: Bool) async throws {
        guard state == .idle || state == .stopped || state == .endedBySleep else { return }
        guard captureSystem || captureMic else {
            throw NSError(domain: "Recorder", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "Sélectionnez au moins une source audio."])
        }
        lastError = nil

        let url = Self.recordingsDir.appendingPathComponent("recording_\(Self.timestamp()).wav")
        let writer = WAVWriter(url: url)
        try writer.open()

        // Source indexing: system (if any) is 0, mic is next. Prepare mic before sizing.
        var mic: MicCapturer?
        if captureMic {
            let m = MicCapturer(sourceIndex: captureSystem ? 1 : 0)
            do { try m.prepare(); mic = m }
            catch { Log.recording.warning("Préparation du micro échouée", detail: error.localizedDescription) }
        }
        let count = (captureSystem ? 1 : 0) + (mic != nil ? 1 : 0)
        guard count > 0 else {
            throw NSError(domain: "Recorder", code: 12,
                          userInfo: [NSLocalizedDescriptionKey: "Micro indisponible."])
        }
        let mixer = AudioMixer(writer: writer, sourceCount: count)
        if let m = mic {
            m.mixer = mixer
            do { try m.start() } catch {
                Log.recording.warning("Démarrage du micro échoué — enregistrement sans micro",
                                      detail: error.localizedDescription)
                mixer.finish(source: m.sourceIndex); mic = nil
            }
        }

        if liveEnabled {
            live.start(language: transcriptionManager?.transcriptionLanguage())
            mixer.onFlush = { [weak self] slice in
                Task { @MainActor in self?.live.ingest(slice) }
            }
        }

        // System audio via SCStream — only if requested (this is what needs Screen Recording).
        var systemCap: SystemAudioCapturer?
        var stream: SCStream?
        if captureSystem {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else {
                throw NSError(domain: "Recorder", code: 10, userInfo: [NSLocalizedDescriptionKey: "Aucun écran trouvé"])
            }
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.sampleRate = 16000
            config.channelCount = 1
            config.excludesCurrentProcessAudio = false
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let cap = SystemAudioCapturer(mixer: mixer, sourceIndex: 0)
            cap.onStop = { [weak self] err in
                Log.recording.error("Flux audio système interrompu", detail: err.localizedDescription)
                Task { @MainActor in self?.lastError = err.localizedDescription }
            }
            let s = SCStream(filter: filter, configuration: config, delegate: cap)
            try s.addStreamOutput(cap, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
            try await s.startCapture()
            systemCap = cap; stream = s
        }

        self.writer = writer; self.mixer = mixer; self.systemCapturer = systemCap
        self.micCapturer = mic; self.stream = stream; self.outputURL = url
        startedAt = Date(); pausedAccum = 0; pauseStartedAt = nil
        state = .recording
        power.acquire(reason: "WhisperBox enregistre")
        transcriptionManager?.prewarm()
        startTimer()
        Log.recording.success("Enregistrement démarré",
                              detail: "système: \(captureSystem ? "oui" : "non") · micro: \(mic != nil ? "oui" : "non")")
    }

    func pause() {
        guard state == .recording else { return }
        mixer?.isPaused = true
        pauseStartedAt = Date()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        if let p = pauseStartedAt { pausedAccum += Date().timeIntervalSince(p) }
        pauseStartedAt = nil
        mixer?.isPaused = false
        state = .recording
    }

    /// Stop, finalize the WAV, and return its URL (or nil if not recording).
    /// `finishLive: false` skips the live-tail transcription (used on sleep for speed).
    @discardableResult
    func stop(finishLive: Bool = true) async -> URL? {
        guard state == .recording || state == .paused else { return outputURL }
        timer?.invalidate(); timer = nil
        if let stream {
            do { try await stream.stopCapture() }
            catch { Log.recording.error("Arrêt de la capture système échoué", detail: error.localizedDescription) }
        }
        if systemCapturer != nil { mixer?.finish(source: 0) }   // system is source 0 when present
        micCapturer?.stop()                                     // removes tap, then finishes mic's source
        writer?.finalize()
        if finishLive && liveEnabled { await live.finish() }   // transcribe the live tail
        power.release()
        let url = outputURL
        state = .stopped
        cleanup()
        if let url { Log.recording.success("Enregistrement enregistré", detail: url.lastPathComponent) }
        return url
    }

    /// Stop and route the result to transcription — live transcript as the
    /// deliverable, else a batch pass. Shared by the Record view and the menu bar.
    func stopAndTranscribe() async {
        guard let url = await stop() else { return }
        let text = live.transcript
        if liveEnabled, !text.isEmpty {
            transcriptionManager?.saveRecordingResult(filePath: url.path, transcript: text)
        } else {
            transcriptionManager?.start(filePath: url.path)
        }
    }

    /// §10.3 Layer 2 — on system sleep, finalize a valid file rather than lose
    /// audio. Skips the live tail to finalize fast within the willSleep window.
    @discardableResult
    func handleSystemWillSleep() async -> URL? {
        guard state == .recording || state == .paused else { return nil }
        let url = await stop(finishLive: false)
        state = .endedBySleep
        if let url, !live.transcript.isEmpty {
            transcriptionManager?.saveRecordingResult(filePath: url.path, transcript: live.transcript)
        }
        return url
    }

    private func cleanup() {
        stream = nil; systemCapturer = nil; micCapturer = nil; mixer = nil; writer = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let s = startedAt else { return }
        let now = Date()
        let pausedNow = pausedAccum + (pauseStartedAt.map { now.timeIntervalSince($0) } ?? 0)
        elapsed = now.timeIntervalSince(s) - pausedNow
    }

    private static func timestamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}
