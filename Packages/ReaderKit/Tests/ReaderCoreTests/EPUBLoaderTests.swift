import XCTest
import ZIPFoundation
@testable import ReaderCore

final class EPUBLoaderTests: XCTestCase {
    func testEPUBLoaderReadsSingleChapter() throws {
        let epubURL = try TestHelpers.makeMinimalEPUB()
        let loader = EPUBLoader()
        let chapter = try loader.loadChapter(from: epubURL, maxSections: 1)

        // Check that content is loaded in htmlSections (used by WebView renderer)
        XCTAssertFalse(chapter.htmlSections.isEmpty, "Chapter should have HTML sections")
        let allHTML = chapter.htmlSections.map { $0.html }.joined()
        XCTAssertTrue(allHTML.contains("Hello from EPUB"), "HTML should contain test content")
        XCTAssertEqual(chapter.title, "Sample EPUB")
    }

    func testCSSManagerGeneratesHouseCSS() {
        let css = CSSManager.houseCSS(fontScale: 2.0)

        // Verify house CSS contains critical pagination properties
        XCTAssertTrue(css.contains("font-size: 32px"), "House CSS should scale font size")
        // Default margin is 32px, total margin (both sides) is 64px
        XCTAssertTrue(css.contains("column-width: calc(100vw - 64px)"), "House CSS should set column width for pagination")
    }

    func testCSSManagerIncludesPublisherCSS() {
        let publisherCSS = """
        p { text-indent: 1em; }
        .centered { text-align: center; }
        """

        let combined = CSSManager.generateCompleteCSS(fontScale: 1.0, publisherCSS: publisherCSS)

        // Publisher CSS should be included (sanitized but these rules are safe)
        XCTAssertTrue(combined.contains("text-indent: 1em"), "Publisher CSS should be preserved")
        XCTAssertTrue(combined.contains("text-align: center"), "Publisher alignment should be preserved")
        // House CSS should also be present
        XCTAssertTrue(combined.contains("column-width: calc(100vw - 64px)"), "House CSS should be included")
    }

    func testCSSManagerSanitizesPercentageMargins() {
        let publisherCSS = """
        .narrow { margin: 0 45%; }
        .wide { margin-left: 56%; }
        p { font-style: italic; }
        """

        let combined = CSSManager.generateCompleteCSS(fontScale: 1.0, publisherCSS: publisherCSS)

        // Percentage margins should be sanitized (they break CSS column pagination)
        XCTAssertFalse(combined.contains("margin: 0 45%"), "Percentage margins should be sanitized")
        XCTAssertFalse(combined.contains("margin-left: 56%"), "Percentage margin-left should be sanitized")
        // Safe CSS should be preserved
        XCTAssertTrue(combined.contains("font-style: italic"), "Safe CSS should be preserved")
    }
}
