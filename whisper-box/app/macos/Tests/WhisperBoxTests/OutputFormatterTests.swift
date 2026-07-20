import XCTest
@testable import WhisperBox

final class OutputFormatterTests: XCTestCase {
    private let segs = [
        TranscriptSegment(start: 0, end: 1.5, text: " Hello "),
        TranscriptSegment(start: 1.5, end: 3670.25, text: "world"),   // 1h 1m 10.25s
    ]

    func testTxtTrimsAndJoins() {
        XCTAssertEqual(OutputFormatter.render(segs, as: .txt), "Hello world")
    }

    func testTxtDropsEmptySegments() {
        let s = [TranscriptSegment(start: 0, end: 1, text: "  "),
                 TranscriptSegment(start: 1, end: 2, text: "kept")]
        XCTAssertEqual(OutputFormatter.render(s, as: .txt), "kept")
    }

    func testSrtStructureAndCommaStamp() {
        let out = OutputFormatter.render(segs, as: .srt)
        XCTAssertTrue(out.hasPrefix("1\n00:00:00,000 --> 00:00:01,500\nHello\n"), out)
        XCTAssertTrue(out.contains("2\n00:00:01,500 --> 01:01:10,250\nworld"), out)
    }

    func testVttHeaderAndDotStamp() {
        let out = OutputFormatter.render(segs, as: .vtt)
        XCTAssertTrue(out.hasPrefix("WEBVTT\n\n"))
        XCTAssertTrue(out.contains("00:00:00.000 --> 00:00:01.500"))
        XCTAssertTrue(out.contains("01:01:10.250"))
    }

    func testNegativeTimeClampedToZero() {
        let out = OutputFormatter.render([TranscriptSegment(start: -5, end: 1, text: "x")], as: .srt)
        XCTAssertTrue(out.contains("00:00:00,000 --> 00:00:01,000"), out)
    }
}
