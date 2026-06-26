import Accelerate
import Foundation
import Observation

/// Phase 5 — live transcript during recording. A preview; the authoritative
/// transcript is the batch pass on the saved WAV at stop.
///
/// Streaming strategy ported from WhisperKit's `AudioStreamTranscriber`:
///   • Rolling buffer, re-transcribed and anchored at the last confirmed point —
///     no hard 30 s cuts, so words are never split mid-boundary and Whisper
///     always sees a natural window with context.
///   • Confirmed vs. unconfirmed segments — all but the last
///     `requiredSegmentsForConfirmation` segments are locked; the tail stays
///     mutable and is refined on each pass, so displayed text doesn't flicker.
///   • Energy VAD — silent passes are skipped (cheaper, and avoids Whisper
///     hallucinating phantom text on silence).
/// Unlike AudioStreamTranscriber we feed the *mixed* (system + mic) slice teed
/// from the recorder, and we trim the buffer past each confirmed point so the
/// re-decode window stays bounded for long meetings.
@MainActor
@Observable
final class LiveTranscriber {
    private(set) var confirmedSegments: [TranscriptSegment] = []
    private(set) var unconfirmedSegments: [TranscriptSegment] = []
    private(set) var active = false

    /// Combined view for the live panel: locked text followed by the still-changing tail.
    var segments: [TranscriptSegment] { confirmedSegments + unconfirmedSegments }

    /// Plain joined text — used as the saved deliverable.
    var transcript: String {
        segments
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var language: String?

    private let engine: TranscriptionEngine

    // Rolling buffer: `buffer[0]` corresponds to absolute time `bufferStartSeconds`.
    private let sampleRate = 16_000
    private var buffer: [Float] = []
    private var bufferStartSeconds: Double = 0
    private var newSamplesSinceRun = 0
    private var draining = false

    // Tuning — mirrors AudioStreamTranscriber defaults.
    private let requiredSegmentsForConfirmation = 2
    private let minNewSamplesToRun = 16_000      // ≥ 1 s of new audio before a pass
    private let silenceThreshold: Float = 0.3    // relative-energy VAD gate
    private let maxBufferSeconds = 30.0          // safety cap on the re-decode window

    // VAD running noise floor (the quietest energy seen so far).
    private var minEnergy: Float = 1e-3

    init(engine: TranscriptionEngine = TranscriptionEngineFactory.make()) {
        self.engine = engine
    }

    func start(language: String?) {
        confirmedSegments = []; unconfirmedSegments = []
        buffer = []; bufferStartSeconds = 0; newSamplesSinceRun = 0
        minEnergy = 1e-3
        self.language = language; active = true
    }

    func ingest(_ samples: [Float]) {
        guard active else { return }
        buffer.append(contentsOf: samples)
        newSamplesSinceRun += samples.count
        Task { await drain() }
    }

    /// Transcribe the remaining tail when recording stops, then lock everything in.
    func finish() async {
        active = false
        if !buffer.isEmpty { await runPass(force: true) }
        confirmedSegments.append(contentsOf: unconfirmedSegments)
        unconfirmedSegments = []
    }

    private func drain() async {
        guard !draining else { return }
        draining = true
        defer { draining = false }
        while active, newSamplesSinceRun >= minNewSamplesToRun {
            await runPass(force: false)
        }
    }

    private func runPass(force: Bool) async {
        let chunk = buffer
        newSamplesSinceRun = 0
        guard !chunk.isEmpty else { return }

        // VAD gate — skip decoding silence.
        if !force, !isVoiced(chunk) {
            if unconfirmedSegments.isEmpty { trimLeadingSilence() }
            return
        }

        guard let segs = try? await engine.transcribe(samples: chunk, language: language),
              !segs.isEmpty else { return }

        // Shift segment times from buffer-relative to absolute.
        let abs = segs.map {
            TranscriptSegment(start: $0.start + bufferStartSeconds,
                              end: $0.end + bufferStartSeconds,
                              text: $0.text)
        }

        // Lock all but the last N segments; keep the tail mutable for refinement.
        if abs.count > requiredSegmentsForConfirmation {
            let confirmCount = abs.count - requiredSegmentsForConfirmation
            let toConfirm = Array(abs.prefix(confirmCount))
            confirmedSegments.append(contentsOf: toConfirm)
            unconfirmedSegments = Array(abs.suffix(requiredSegmentsForConfirmation))

            // Drop audio up to the last confirmed segment so the next pass only
            // re-decodes the unconfirmed tail + new audio.
            if let lastConfirmedEnd = toConfirm.last?.end {
                trimBuffer(toAbsoluteSeconds: lastConfirmedEnd)
            }
        } else {
            unconfirmedSegments = abs
        }

        enforceMaxBuffer()
    }

    // MARK: - Buffer trimming

    private func trimBuffer(toAbsoluteSeconds t: Double) {
        let dropSeconds = t - bufferStartSeconds
        guard dropSeconds > 0 else { return }
        let dropSamples = min(buffer.count, Int(dropSeconds * Double(sampleRate)))
        guard dropSamples > 0 else { return }
        buffer.removeFirst(dropSamples)
        bufferStartSeconds += Double(dropSamples) / Double(sampleRate)
    }

    /// During a silent gap with nothing pending, keep only the last ~0.5 s for context.
    private func trimLeadingSilence() {
        let keep = sampleRate / 2
        guard buffer.count > keep else { return }
        let drop = buffer.count - keep
        buffer.removeFirst(drop)
        bufferStartSeconds += Double(drop) / Double(sampleRate)
    }

    /// Safety valve: continuous speech can't be refined forever. If the re-decode
    /// window grows past the cap, lock the tail in and trim. Rare in practice —
    /// Whisper emits a segment every few seconds, so confirmation trims first.
    private func enforceMaxBuffer() {
        guard Double(buffer.count) / Double(sampleRate) > maxBufferSeconds else { return }
        confirmedSegments.append(contentsOf: unconfirmedSegments)
        let anchor = unconfirmedSegments.last?.end ?? bufferStartSeconds
        unconfirmedSegments = []
        trimBuffer(toAbsoluteSeconds: anchor)
    }

    // MARK: - Energy VAD (ported from AudioProcessor)

    /// Voiced if any ~100 ms window's energy, relative to the running noise floor,
    /// exceeds the silence threshold.
    private func isVoiced(_ samples: [Float]) -> Bool {
        let windowSize = sampleRate / 10   // 100 ms
        guard samples.count >= windowSize else {
            return relativeEnergy(of: samples) > silenceThreshold
        }
        var voiced = false
        var i = 0
        while i + windowSize <= samples.count {
            let avg = averageEnergy(of: Array(samples[i ..< i + windowSize]))
            if avg < minEnergy { minEnergy = max(1e-8, avg) }   // track noise floor
            if relativeEnergyValue(signalEnergy: avg, reference: minEnergy) > silenceThreshold {
                voiced = true
            }
            i += windowSize
        }
        return voiced
    }

    private func relativeEnergy(of samples: [Float]) -> Float {
        let avg = averageEnergy(of: samples)
        if avg < minEnergy { minEnergy = max(1e-8, avg) }
        return relativeEnergyValue(signalEnergy: avg, reference: minEnergy)
    }

    /// RMS energy of a signal chunk.
    private func averageEnergy(of signal: [Float]) -> Float {
        guard !signal.isEmpty else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(signal, 1, &rms, vDSP_Length(signal.count))
        return rms
    }

    /// Energy normalized (0…1) against a reference floor, in dB — matches
    /// `AudioProcessor.calculateRelativeEnergy`.
    private func relativeEnergyValue(signalEnergy: Float, reference: Float) -> Float {
        let ref = max(1e-8, reference)
        let refDb = 20 * log10(ref)
        guard refDb != 0 else { return 0 }
        let signalDb = 20 * log10(max(signalEnergy, 1e-8))
        return (signalDb - refDb) / (0 - refDb)
    }
}
