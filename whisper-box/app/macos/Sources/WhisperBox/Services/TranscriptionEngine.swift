import Foundation

/// Engine-agnostic transcription interface. WhisperKit is the chosen engine
/// (WhisperKitEngine.swift); MockEngine keeps the app usable before the model
/// is available / for previews.

struct TranscriptSegment: Sendable, Identifiable {
    let id = UUID()
    let start: Double        // seconds
    let end: Double
    let text: String
}

/// Live progress during transcription: (fraction 0…1, cumulative text so far).
/// This is the streaming signal mlx couldn't provide.
typealias ProgressHandler = @Sendable (Double, String) -> Void

protocol TranscriptionEngine: Sendable {
    func transcribe(
        audioPath: String,
        language: String?,
        onProgress: @escaping ProgressHandler
    ) async throws -> [TranscriptSegment]

    /// Transcribe a raw 16 kHz mono sample buffer (used for live chunks).
    func transcribe(samples: [Float], language: String?) async throws -> [TranscriptSegment]

    /// Eagerly load the model so the first transcription doesn't pay for it.
    func prewarm() async
}

enum TranscriptionEngineFactory {
    /// Single shared engine — live preview + final batch pass reuse one loaded
    /// model (one copy in memory) and access is serialized by the actor.
    static let shared: TranscriptionEngine = {
        #if canImport(WhisperKit)
        return WhisperKitEngine()
        #else
        return MockEngine()
        #endif
    }()

    static func make() -> TranscriptionEngine { shared }
}

/// Offline placeholder — used only when WhisperKit isn't linked.
struct MockEngine: TranscriptionEngine {
    func transcribe(
        audioPath: String,
        language: String?,
        onProgress: @escaping ProgressHandler
    ) async throws -> [TranscriptSegment] {
        let segs = [
            TranscriptSegment(start: 0, end: 2, text: "[mock] WhisperKit not linked."),
            TranscriptSegment(start: 2, end: 4, text: "[mock] Build with the dependency to enable."),
        ]
        var acc = ""
        for (i, s) in segs.enumerated() {
            acc += s.text + " "
            onProgress(Double(i + 1) / Double(segs.count), acc)
        }
        return segs
    }

    func transcribe(samples: [Float], language: String?) async throws -> [TranscriptSegment] {
        [TranscriptSegment(start: 0, end: Double(samples.count) / 16000, text: "[mock chunk] ")]
    }

    func prewarm() async {}
}
