import XCTest
@testable import WhisperBox

/// Guards the #22 crash-safety behavior: `flushHeader()` (called ~every 5 s while recording)
/// and `finalize()` must write a valid RIFF `dataSize` so a hard crash still leaves a playable
/// file (a stale `dataSize: 0` header plays as empty even though samples are on disk).
final class WAVWriterTests: XCTestCase {
    private func le32(_ data: Data, _ offset: Int) -> UInt32 {
        data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    }

    func testFlushHeaderWritesCurrentDataSizeWithoutClosing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wbwav_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let w = WAVWriter(url: url)               // 16 kHz mono, 16-bit
        try w.open()
        w.writeSamples([Float](repeating: 0.5, count: 100))   // 100 samples → 200 data bytes
        w.flushHeader()                            // crash-safety rewrite, handle stays open

        let mid = try Data(contentsOf: url)
        XCTAssertGreaterThanOrEqual(mid.count, 44 + 200)
        XCTAssertEqual(le32(mid, 40), 200, "data chunk size should reflect samples written so far")
        XCTAssertEqual(le32(mid, 4), 200 + 36, "RIFF chunk size = dataSize + 36")

        // More audio, then finalize → header reflects the full length.
        w.writeSamples([Float](repeating: -0.5, count: 50))   // +100 bytes
        w.finalize()
        let final = try Data(contentsOf: url)
        XCTAssertEqual(le32(final, 40), 300)
        XCTAssertEqual(le32(final, 4), 300 + 36)
    }

    func testHeaderIsZeroBeforeAnyFlush() throws {
        // open() writes a dataSize:0 header; without flush/finalize a crash would leave 0.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wbwav_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let w = WAVWriter(url: url)
        try w.open()
        let data = try Data(contentsOf: url)
        XCTAssertEqual(le32(data, 40), 0)
        w.finalize()
    }
}
