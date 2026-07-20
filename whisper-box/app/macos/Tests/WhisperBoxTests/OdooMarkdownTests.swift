import XCTest
@testable import WhisperBox

final class OdooMarkdownTests: XCTestCase {
    private func html(_ md: String) -> String { OdooService.htmlFromMarkdown(md) }

    func testParagraphAndBold() {
        XCTAssertEqual(html("Hello **world**"), "<p>Hello <b>world</b></p>")
    }

    func testHeadings() {
        XCTAssertEqual(html("# Title"), "<h2>Title</h2>")
        XCTAssertEqual(html("## Two"), "<h2>Two</h2>")
        XCTAssertEqual(html("### Sub"), "<h3>Sub</h3>")
    }

    func testBulletsGroupIntoList() {
        XCTAssertEqual(html("- a\n- b"), "<ul><li>a</li><li>b</li></ul>")
    }

    func testAsteriskBulletsAlsoGroup() {
        XCTAssertEqual(html("* a\n* b"), "<ul><li>a</li><li>b</li></ul>")
    }

    func testBlockquoteAndRule() {
        // The default French prompt's AI-warning banner: a "> " quote then "---".
        let out = html("> **Warning**\n---")
        XCTAssertTrue(out.contains("<blockquote>"), out)
        XCTAssertTrue(out.contains("<b>Warning</b>"), out)
        XCTAssertTrue(out.contains("</blockquote>"), out)
        XCTAssertTrue(out.contains("<hr>"), out)
    }

    func testHtmlIsEscaped() {
        XCTAssertEqual(html("a < b & c > d"), "<p>a &lt; b &amp; c &gt; d</p>")
    }

    func testEmptyInputIsValidHtml() {
        XCTAssertEqual(html(""), "<p></p>")
    }

    func testBoldRegexTerminates() {
        // A lone "**" must not loop forever or crash.
        XCTAssertNoThrow(_ = html("a ** b ** c ** d"))
    }
}
