import Foundation

/// Splits long audio into windows so transcription can (a) report real
/// incremental progress, (b) pause/resume at chunk boundaries, and
/// (c) checkpoint for sleep recovery (SWIFT_MIGRATION_PLAN.md §10.2/§10.3).
/// Chunking also resets decoder context per window, capping the
/// `condition_on_previous_text` runaway we measured on long recordings.

struct AudioChunk: Equatable {
    let index: Int
    let startSec: Double
    let endSec: Double
}

enum ChunkPlanner {
    /// Plan contiguous windows with a small overlap to soften boundary cuts.
    /// Defaults: 5-minute chunks, 5-second overlap (the "transcribe every 5–10 min" idea).
    static func plan(totalSeconds: Double,
                     chunkSeconds: Double = 300,
                     overlapSeconds: Double = 5) -> [AudioChunk] {
        guard totalSeconds > 0 else { return [] }
        var chunks: [AudioChunk] = []
        var start = 0.0
        var i = 0
        while start < totalSeconds {
            let end = min(start + chunkSeconds, totalSeconds)
            chunks.append(AudioChunk(index: i, startSec: max(0, start - (i == 0 ? 0 : overlapSeconds)), endSec: end))
            start = end
            i += 1
        }
        return chunks
    }
}

/// Drives chunk-by-chunk transcription with pause/resume + checkpointing.
/// Engine-agnostic: the per-chunk work is an injected async closure.
/// Pause = stop after the current chunk (checkpoint persists); resume = run again.
final class ChunkedTranscriber {
    private(set) var nextChunk: Int      // checkpoint: first not-yet-done chunk
    private(set) var transcript: String
    private var paused = false

    init(resumeFromChunk: Int = 0, partialTranscript: String = "") {
        self.nextChunk = resumeFromChunk
        self.transcript = partialTranscript
    }

    func pause() { paused = true }

    /// Returns true if the whole sequence completed, false if it paused early.
    @discardableResult
    func run(chunks: [AudioChunk],
             transcribeChunk: (AudioChunk) async throws -> [TranscriptSegment],
             onProgress: (Double) -> Void = { _ in }) async throws -> Bool {
        paused = false
        while nextChunk < chunks.count {
            if paused { return false }                 // checkpoint already at nextChunk
            let segs = try await transcribeChunk(chunks[nextChunk])
            let text = segs.map { $0.text }.joined()
            if !text.isEmpty {
                transcript += transcript.isEmpty ? text : " " + text
            }
            nextChunk += 1
            onProgress(Double(nextChunk) / Double(chunks.count))
        }
        return true
    }
}
