import XCTest
@testable import WhisperBox

final class AudioMixerTests: XCTestCase {
    /// A mixer writing to a throwaway WAV in the temp dir.
    private func makeMixer(sources: Int) throws -> (AudioMixer, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wbtest_\(UUID().uuidString).wav")
        let writer = WAVWriter(url: url)
        try writer.open()
        return (AudioMixer(writer: writer, sourceCount: sources), url)
    }

    func testTwoSourcesSumAtTheWatermark() throws {
        let (mixer, url) = try makeMixer(sources: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        var flushed: [Float] = []
        mixer.onFlush = { flushed.append(contentsOf: $0) }

        mixer.append(source: 0, samples: [1, 1, 1])   // ahead of source 1 → nothing flushable yet
        XCTAssertTrue(flushed.isEmpty)
        mixer.append(source: 1, samples: [2, 2])       // watermark = min(3,2) = 2 → flush 2 mixed samples
        XCTAssertEqual(flushed, [3, 3])
    }

    func testFinishDrainsRemainingViaOtherSource() throws {
        let (mixer, url) = try makeMixer(sources: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        var flushed: [Float] = []
        mixer.onFlush = { flushed.append(contentsOf: $0) }

        mixer.append(source: 0, samples: [1, 1, 1])
        mixer.append(source: 1, samples: [2, 2])       // flushes [3,3]
        mixer.finish(source: 1)                         // source 1 done → watermark follows source 0
        XCTAssertEqual(flushed, [3, 3, 1])              // the trailing source-0 sample flushes
    }

    func testAppendToFinishedSourceIsDropped() throws {
        // Regression: a stall-finished source (cursor == Int.max) delivering again must
        // be dropped — not integer-overflow-trap and not flushed. (If the guard were
        // removed the process would trap here, failing the test.)
        let (mixer, url) = try makeMixer(sources: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        var flushed: [Float] = []
        mixer.onFlush = { flushed.append(contentsOf: $0) }
        mixer.finish(source: 0)
        mixer.append(source: 0, samples: [1, 2, 3])   // must be ignored
        XCTAssertTrue(flushed.isEmpty)
    }

    func testPausedSamplesAreDropped() throws {
        let (mixer, url) = try makeMixer(sources: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        var flushed: [Float] = []
        mixer.onFlush = { flushed.append(contentsOf: $0) }
        mixer.isPaused = true
        mixer.append(source: 0, samples: [9, 9, 9])
        XCTAssertTrue(flushed.isEmpty)
    }

    // MARK: - Stall detector (#24), driven by an injected clock

    /// A 2-source mixer whose clock the test controls.
    private func makeClockedMixer(_ clock: @escaping () -> Date) throws -> (AudioMixer, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wbtest_\(UUID().uuidString).wav")
        let writer = WAVWriter(url: url)
        try writer.open()
        return (AudioMixer(writer: writer, sourceCount: 2, now: clock), url)
    }

    func testCheckStallDropsAnIdleSourceWhileAnotherMoves() throws {
        var t = Date(timeIntervalSince1970: 1000)
        let (mixer, url) = try makeClockedMixer({ t })
        defer { try? FileManager.default.removeItem(at: url) }
        var stalled: [Int] = []
        mixer.onStall = { stalled.append($0) }

        mixer.append(source: 0, samples: [1])   // both deliver at t=1000
        mixer.append(source: 1, samples: [1])
        t = t.addingTimeInterval(9)              // 9 s later…
        mixer.append(source: 0, samples: [1])    // …only source 0 delivers again
        mixer.checkStall()                       // source 1 idle 9 s > 8 s while 0 moves
        XCTAssertEqual(stalled, [1])
    }

    func testCheckStallDoesNotDropWhenBothAreIdle() throws {
        var t = Date(timeIntervalSince1970: 2000)
        let (mixer, url) = try makeClockedMixer({ t })
        defer { try? FileManager.default.removeItem(at: url) }
        var stalled: [Int] = []
        mixer.onStall = { stalled.append($0) }

        mixer.append(source: 0, samples: [1])
        mixer.append(source: 1, samples: [1])
        t = t.addingTimeInterval(20)             // both stale — neither is "moving"
        mixer.checkStall()
        XCTAssertTrue(stalled.isEmpty)
    }

    func testResetStallClocksPreventsFalsePositiveAfterPause() throws {
        // Regression: a long pause must not look like a stall on resume.
        var t = Date(timeIntervalSince1970: 3000)
        let (mixer, url) = try makeClockedMixer({ t })
        defer { try? FileManager.default.removeItem(at: url) }
        var stalled: [Int] = []
        mixer.onStall = { stalled.append($0) }

        mixer.append(source: 0, samples: [1])
        mixer.append(source: 1, samples: [1])
        t = t.addingTimeInterval(60)             // paused 60 s
        mixer.resetStallClocks()                 // resume() calls this
        mixer.append(source: 0, samples: [1])    // source 0 delivers right after resume
        mixer.checkStall()                       // source 1 not yet delivered, but clock was reset
        XCTAssertTrue(stalled.isEmpty)
    }
}
