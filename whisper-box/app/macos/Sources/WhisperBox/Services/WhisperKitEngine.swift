import Foundation

// Real engine — active once the WhisperKit SPM dependency is linked.
// Validated against WhisperKit 0.18.
#if canImport(WhisperKit)
import WhisperKit
import AVFoundation

/// Actor so the loaded WhisperKit pipeline is cached and reused across jobs —
/// the model loads once, not on every transcription (fixes slow job starts).
actor WhisperKitEngine: TranscriptionEngine {
    private let model: String
    private var pipe: WhisperKit?

    init(model: String = "openai_whisper-large-v3-v20240930_turbo") {
        self.model = model
    }

    private func pipeline() async throws -> WhisperKit {
        if let pipe { return pipe }
        let p = try await WhisperKit(WhisperKitConfig(model: model))
        pipe = p
        return p
    }

    func prewarm() async { _ = try? await pipeline() }

    func transcribe(samples: [Float], language: String?) async throws -> [TranscriptSegment] {
        let pipe = try await pipeline()
        let results = try await pipe.transcribe(
            audioArray: samples,
            decodeOptions: DecodingOptions(language: language)
        )
        return results.flatMap { $0.segments }.map {
            TranscriptSegment(start: Double($0.start), end: Double($0.end), text: $0.text)
        }
    }

    func transcribe(
        audioPath: String,
        language: String?,
        onProgress: @escaping ProgressHandler
    ) async throws -> [TranscriptSegment] {
        // Decode ourselves (AVAssetReader → 16 kHz mono Float) instead of WhisperKit's
        // AVAudioFile loader, which throws Core Audio -50 on mp4/mov. See `AudioDecode`.
        let samples = try await AudioDecode.pcm16kMono(path: audioPath)
        let duration = Double(samples.count) / 16_000.0
        let totalWindows = max(1.0, (duration / 30.0).rounded(.up))

        let pipe = try await pipeline()   // loaded once; reused thereafter

        let results = try await pipe.transcribe(
            audioArray: samples,
            decodeOptions: DecodingOptions(language: language),
            callback: { progress in
                let frac = min(Double(progress.windowId + 1) / totalWindows, 0.99)
                onProgress(frac, progress.text)
                return !Task.isCancelled   // stop decoding when the job is cancelled
            }
        )

        let segments = results.flatMap { $0.segments }.map {
            TranscriptSegment(start: Double($0.start), end: Double($0.end), text: $0.text)
        }
        onProgress(1.0, segments.map(\.text).joined())
        return segments
    }
}
#endif
