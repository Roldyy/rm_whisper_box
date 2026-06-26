import Foundation
import Observation

/// Phase 5 — live transcript during recording. Accumulates the mixed 16 kHz
/// samples teed from the recorder and transcribes them in 30s chunks, keeping
/// timestamped segments (offset to absolute time) for the live panel. A preview;
/// the authoritative transcript is the batch pass on the saved WAV at stop.
@MainActor
@Observable
final class LiveTranscriber {
    private(set) var segments: [TranscriptSegment] = []
    private(set) var transcript = ""        // plain joined text (used as the saved deliverable)
    private(set) var active = false

    private let engine: TranscriptionEngine
    private var pending: [Float] = []
    private var consumedSeconds: Double = 0
    private var draining = false
    var language: String?

    private let chunkSamples = 16_000 * 30   // 30 s = Whisper's native window

    init(engine: TranscriptionEngine = TranscriptionEngineFactory.make()) {
        self.engine = engine
    }

    func start(language: String?) {
        segments = []; transcript = ""; pending = []; consumedSeconds = 0
        self.language = language; active = true
    }

    func ingest(_ samples: [Float]) {
        guard active else { return }
        pending.append(contentsOf: samples)
        Task { await drain() }
    }

    private func drain() async {
        guard !draining else { return }
        draining = true
        defer { draining = false }
        while pending.count >= chunkSamples {
            let chunk = Array(pending.prefix(chunkSamples))
            pending.removeFirst(chunkSamples)
            await transcribe(chunk)
        }
    }

    /// Transcribe the remaining tail when recording stops.
    func finish() async {
        active = false
        guard !pending.isEmpty else { return }
        let chunk = pending
        pending = []
        await transcribe(chunk)
    }

    private func transcribe(_ chunk: [Float]) async {
        let offset = consumedSeconds
        consumedSeconds += Double(chunk.count) / 16_000
        guard let segs = try? await engine.transcribe(samples: chunk, language: language) else { return }
        let shifted = segs.map { TranscriptSegment(start: $0.start + offset, end: $0.end + offset, text: $0.text) }
        segments.append(contentsOf: shifted)
        let text = segs.map(\.text).joined()
        if !text.isEmpty { transcript += transcript.isEmpty ? text : " " + text }
    }
}
