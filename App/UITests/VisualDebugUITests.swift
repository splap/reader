import XCTest

/// Visual debugging test that captures screenshots of any book at any CFI location.
///
/// Usage:
///   BOOK_KEYWORD="Crash" BOOK_CFI="epubcfi(/6/22!)" ./scripts/test ui:testVisualDebugBookAtLocation
///
/// Environment variables (passed via test-config.json):
///   - BOOK_KEYWORD: Search term to find the book (e.g., "Crash", "Frankenstein")
///   - BOOK_CFI: CFI to navigate to (e.g., "epubcfi(/6/22!)")
///   - BOOK_PAGE_OFFSET: Optional number of pages to swipe forward after loading (e.g., "5")
///
/// Screenshots are saved to /tmp/reader-tests/ with timestamps.
final class VisualDebugUITests: XCTestCase {
    var app: XCUIApplication!

    /// Test configuration read from /tmp/reader-tests/test-config.json
    private struct TestConfig {
        let bookKeyword: String
        let bookCFI: String
        let bookPageOffset: Int

        static func load() -> TestConfig {
            let configPath = "/tmp/reader-tests/test-config.json"
            guard FileManager.default.fileExists(atPath: configPath),
                  let data = FileManager.default.contents(atPath: configPath),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return TestConfig(bookKeyword: "", bookCFI: "", bookPageOffset: 0)
            }

            return TestConfig(
                bookKeyword: json["bookKeyword"] as? String ?? "",
                bookCFI: json["bookCFI"] as? String ?? "",
                bookPageOffset: json["bookPageOffset"] as? Int ?? 0
            )
        }
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    /// Opens a book specified by BOOK_KEYWORD at BOOK_CFI and captures a screenshot.
    /// Skips automatically when run without the required environment variables.
    func testVisualDebugBookAtLocation() throws {
        let config = TestConfig.load()
        let bookKeyword = config.bookKeyword
        let bookCFI = config.bookCFI
        let pageOffset = config.bookPageOffset

        print("=== Visual Debug Test ===")
        print("BOOK_KEYWORD: '\(bookKeyword)'")
        print("BOOK_CFI: '\(bookCFI)'")
        print("BOOK_PAGE_OFFSET: \(pageOffset)")

        // Skip test if required environment variables are not provided
        // This test is meant to be run manually with specific parameters
        try XCTSkipIf(bookKeyword.isEmpty, "Skipping: BOOK_KEYWORD not provided (manual test)")
        try XCTSkipIf(bookCFI.isEmpty, "Skipping: BOOK_CFI not provided (manual test)")

        // Launch app directly to the book and chapter via CFI
        let extraArgs = [
            "--uitesting-book=\(bookKeyword)",
            "--uitesting-cfi=\(bookCFI)",
        ]

        app = launchReaderApp(extraArgs: extraArgs)

        // Wait for reader to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 15), "WebView should load")
        sleep(3) // Let content render

        print("Opened book directly via CFI")

        // Swipe forward if page offset specified
        if pageOffset > 0 {
            print("Swiping forward \(pageOffset) pages...")
            for i in 1 ... pageOffset {
                webView.swipeLeft()
                sleep(1)
                print("  Swiped to page +\(i)")
            }
        }

        // Capture and save screenshot
        let screenshot = XCUIScreen.main.screenshot()

        let dirPath = "/tmp/reader-tests"
        try? FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        let safeKeyword = bookKeyword.replacingOccurrences(of: " ", with: "-").prefix(20)
        let cfiHash = "cfi-\(bookCFI.hashValue.magnitude % 10000)"
        let screenshotPath = "\(dirPath)/debug-\(safeKeyword)-\(cfiHash)-\(timestamp).png"

        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: screenshotPath))
        print("Screenshot saved to: \(screenshotPath)")

        // Add to test results
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Visual Debug: \(bookKeyword) @ CFI"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Log current position
        webView.tap()
        sleep(1)

        let pageLabel = app.staticTexts["scrubber-page-label"]
        if pageLabel.waitForExistence(timeout: 3) {
            print("Current position: \(pageLabel.label)")
        }

        print("=== Visual Debug Complete ===")
        print("Screenshot: \(screenshotPath)")
    }
}
