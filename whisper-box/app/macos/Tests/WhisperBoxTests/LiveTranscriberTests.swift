import XCTest
@testable import WhisperBox

// MARK: - Test doubles

/// Returns canned segments immediately. `segments` is set once before `ingest`, then only read.
private final class StubEngine: TranscriptionEngine, @unchecked Sendable {
    var segments: [TranscriptSegment] = []
    func transcribe(audioPath: String, language: String?, onProgress: @escaping ProgressHandler) async throws -> [TranscriptSegment] { segments }
    func transcribe(samples: [Float], language: String?) async throws -> [TranscriptSegment] { segments }
    func prewarm() async {}
}

/// Blocks inside `transcribe(samples:)` until the test releases it, so a pass can be held
/// "in flight" to drive the cancel/restart race. An `actor` (not NSLock) so it's Swift-6-clean.
private actor ControllableEngine: TranscriptionEngine {
    private var segments: [TranscriptSegment] = []
    private var releaseCont: CheckedContinuation<Void, Never>?
    private var startedCont: CheckedContinuation<Void, Never>?
    private var pendingStarted = false

    func setSegments(_ s: [TranscriptSegment]) { segments = s }

    /// Resolves once a `transcribe(samples:)` call is executing.
    func waitUntilTranscribing() async {
        if pendingStarted { pendingStarted = false; return }
        await withCheckedContinuation { startedCont = $0 }
    }
    /// Lets the in-flight `transcribe(samples:)` return.
    func releaseTranscribe() { releaseCont?.resume(); releaseCont = nil }

    func transcribe(samples: [Float], language: String?) async throws -> [TranscriptSegment] {
        if let c = startedCont { startedCont = nil; c.resume() } else { pendingStarted = true }
        await withCheckedContinuation { releaseCont = $0 }
        return segments
    }
    func transcribe(audioPath: String, language: String?, onProgress: @escaping ProgressHandler) async throws -> [TranscriptSegment] { segments }
    func prewarm() async {}
}

private func seg(_ text: String, _ start: Double = 0, _ end: Double = 1) -> TranscriptSegment {
    TranscriptSegment(start: start, end: end, text: text)
}

/// A buffer that passes the energy VAD: 100 ms of silence (drops the noise floor) then a loud
/// body, so a *non-forced* pass actually decodes. ≥ `minNewSamplesToRun` so a drain fires.
private func voiced(_ n: Int = 20_000) -> [Float] {
    var s = [Float](repeating: 0, count: 1_600)
    s += [Float](repeating: 0.6, count: max(0, n - 1_600))
    return s
}

// MARK: - Tests

@MainActor
final class LiveTranscriberTests: XCTestCase {

    /// Poll (bounded, condition-based — not blind fixed yields) until `cond` holds.
    private func waitUntil(_ cond: () -> Bool, _ maxYields: Int = 500) async {
        for _ in 0..<maxYields { if cond() { return }; await Task.yield() }
    }

    // finish() runs a forced final pass (bypasses the VAD gate); these cover that finalize path.

    func testFinishProducesJoinedTranscript() async {
        let engine = StubEngine(); engine.segments = [seg("hello"), seg("world")]
        let lt = LiveTranscriber(engine: engine)
        lt.start(language: nil)
        lt.ingest([Float](repeating: 0.5, count: 8_000))
        await lt.finish()
        XCTAssertEqual(lt.transcript, "hello world")
    }

    func testTranscriptTrimsAndDropsEmptySegments() async {
        let engine = StubEngine(); engine.segments = [seg("  a  "), seg("   "), seg("b")]
        let lt = LiveTranscriber(engine: engine)
        lt.start(language: nil)
        lt.ingest([Float](repeating: 0.5, count: 8_000))
        await lt.finish()
        XCTAssertEqual(lt.transcript, "a b")
    }

    func testEmptyEngineResultYieldsEmptyTranscript() async {
        let engine = StubEngine(); engine.segments = []
        let lt = LiveTranscriber(engine: engine)
        lt.start(language: nil)
        lt.ingest([Float](repeating: 0.5, count: 8_000))
        await lt.finish()
        XCTAssertEqual(lt.transcript, "")
    }

    func testStartResetsPreviousTranscript() async {
        let engine = StubEngine(); engine.segments = [seg("old")]
        let lt = LiveTranscriber(engine: engine)
        lt.start(language: nil)
        lt.ingest([Float](repeating: 0.5, count: 8_000))
        await lt.finish()
        XCTAssertEqual(lt.transcript, "old")

        lt.start(language: nil)                 // new session clears everything
        XCTAssertEqual(lt.transcript, "")
        XCTAssertTrue(lt.active)
    }

    func testCancelClearsAndDeactivates() async {
        let engine = StubEngine(); engine.segments = [seg("x")]
        let lt = LiveTranscriber(engine: engine)
        lt.start(language: nil)
        lt.cancel()
        XCTAssertFalse(lt.active)
        XCTAssertEqual(lt.transcript, "")
    }

    /// #1 — exercise the *incremental* (non-forced) drain pass, VAD gate, and the
    /// confirm-all-but-last-two split (previously only the forced finish() path ran).
    func testIncrementalDrainConfirmsAllButLastTwoSegments() async {
        let engine = StubEngine(); engine.segments = [seg("a"), seg("b"), seg("c")]
        let lt = LiveTranscriber(engine: engine)
        lt.start(language: nil)
        lt.ingest(voiced())                                  // drain → runPass(force:false), VAD passes
        await waitUntil { !lt.segments.isEmpty }             // wait for the pass to land
        XCTAssertEqual(lt.confirmedSegments.map(\.text), ["a"])       // all but last 2 confirmed
        XCTAssertEqual(lt.unconfirmedSegments.map(\.text), ["b", "c"])
        XCTAssertEqual(lt.transcript, "a b c")
    }

    /// #2/#3 — a pass left in flight when the session is cancelled/restarted must not leak its
    /// (stale) segments into the new session. Made deterministic with a fresh pass as a
    /// happens-after barrier: the stale runPass is released and enqueued *before* the fresh one,
    /// so if the guard were broken "STALE" would already be present when "FRESH" lands.
    func testStalePassFromCancelledSessionIsDiscarded() async {
        let engine = ControllableEngine()
        await engine.setSegments([seg("STALE")])
        let lt = LiveTranscriber(engine: engine)

        lt.start(language: nil)
        lt.ingest(voiced())
        await engine.waitUntilTranscribing()     // stale pass in flight
        lt.cancel()                              // bump session
        lt.start(language: nil)                  // brand-new session
        await engine.releaseTranscribe()         // stale pass returns [STALE] → guard must discard

        await engine.setSegments([seg("FRESH")])
        lt.ingest(voiced())                      // new-session pass
        await engine.waitUntilTranscribing()     // fresh pass in flight (⇒ stale already returned)
        await engine.releaseTranscribe()
        await waitUntil { lt.transcript == "FRESH" || lt.transcript.contains("STALE") }
        XCTAssertEqual(lt.transcript, "FRESH")   // STALE must never have leaked in
    }
}
