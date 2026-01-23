import XCTest

/// UI Tests for visual comparison between reference server and iOS app.
/// These tests capture screenshots that can be compared with reference screenshots
/// using the LLM-as-Judge visual comparison system.
///
/// Environment variables:
///   BOOK - Book slug (default: frankenstein)
///   CHAPTER - Chapter index (default: 0)
///   PAGE - Page within chapter (default: 1)
///   CHAPTER_COUNT - Number of chapters to capture (default: 5)
///
/// Usage:
///   BOOK=frankenstein CHAPTER=1 ./scripts/test ui:testCaptureForComparison
///   BOOK=meditations CHAPTER=1 ./scripts/test ui:testCaptureBothRenderers
final class VisualComparisonTests: XCTestCase {
    var app: XCUIApplication!

    /// Test configuration from environment variables
    private struct TestConfig {
        let book: String
        let chapter: String
        let page: String
        let chapterCount: String

        static func load() -> TestConfig {
            // Read from environment variables, with defaults
            let book = ProcessInfo.processInfo.environment["BOOK"] ?? "frankenstein"
            let chapter = ProcessInfo.processInfo.environment["CHAPTER"] ?? "0"
            let page = ProcessInfo.processInfo.environment["PAGE"] ?? "1"
            let chapterCount = ProcessInfo.processInfo.environment["CHAPTER_COUNT"] ?? "5"
            return TestConfig(book: book, chapter: chapter, page: page, chapterCount: chapterCount)
        }
    }

    private var config: TestConfig!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false

        // Load configuration from temp file (written by test script)
        config = TestConfig.load()

        app = XCUIApplication()

        // Configure app for visual testing
        app.launchArguments = [
            "--uitesting",
            "--uitesting-skip-indexing",
            "--uitesting-webview",
            "--uitesting-book=\(config.book)",
            "--uitesting-spine-item=\(config.chapter)"
        ]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    /// Captures a screenshot for visual comparison.
    /// The screenshot is saved to /tmp/reader-tests/ios_<book>_ch<chapter>.png
    func testCaptureForComparison() {
        let book = config.book
        let chapter = config.chapter

        // Wait for the book to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 10), "WebView should exist after opening book")

        // Wait for content to render - give it some time for fonts and layout
        sleep(3)

        // Capture screenshot
        let screenshot = XCUIScreen.main.screenshot()

        // Create output directory
        let dirPath = "/tmp/reader-tests"
        try? FileManager.default.createDirectory(
            atPath: dirPath,
            withIntermediateDirectories: true
        )

        // Save screenshot with standardized naming
        let screenshotPath = "\(dirPath)/ios_\(book)_ch\(chapter).png"
        let imageData = screenshot.pngRepresentation
        do {
            try imageData.write(to: URL(fileURLWithPath: screenshotPath))
            print("📸 Screenshot saved to: \(screenshotPath)")
        } catch {
            XCTFail("Failed to save screenshot: \(error)")
        }

        // Also add as test attachment for Xcode viewing
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "ios_\(book)_ch\(chapter)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Captures multiple chapters in sequence.
    /// Use BOOK and CHAPTER_COUNT environment variables.
    func testCaptureMultipleChapters() {
        let book = config.book
        let chapterCount = Int(config.chapterCount) ?? 5

        // Create output directory
        let dirPath = "/tmp/reader-tests"
        try? FileManager.default.createDirectory(
            atPath: dirPath,
            withIntermediateDirectories: true
        )

        for chapter in 0..<chapterCount {
            // For chapters after the first, we need to navigate
            if chapter > 0 {
                // Tap to show overlay
                let webView = app.webViews.firstMatch
                webView.tap()
                sleep(1)

                // Navigate using TOC if available
                let tocButton = app.buttons["Table of Contents"]
                if tocButton.exists {
                    tocButton.tap()
                    sleep(1)

                    // Find and tap the chapter menu item (this is approximate)
                    let menuItems = app.buttons.allElementsBoundByIndex
                    if chapter < menuItems.count {
                        menuItems[chapter].tap()
                        sleep(2)
                    }
                }
            } else {
                // First chapter - wait for initial load
                let webView = app.webViews.firstMatch
                XCTAssertTrue(webView.waitForExistence(timeout: 10))
                sleep(3)
            }

            // Capture screenshot
            let screenshot = XCUIScreen.main.screenshot()
            let screenshotPath = "\(dirPath)/ios_\(book)_ch\(chapter).png"

            do {
                try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: screenshotPath))
                print("📸 Chapter \(chapter) screenshot saved to: \(screenshotPath)")
            } catch {
                print("⚠️ Failed to save chapter \(chapter) screenshot: \(error)")
            }

            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "ios_\(book)_ch\(chapter)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// Test that captures a specific page within a chapter.
    /// Use BOOK, CHAPTER, and PAGE environment variables.
    func testCaptureSpecificPage() {
        let book = config.book
        let chapter = config.chapter
        let page = Int(config.page) ?? 1

        // Wait for the book to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 10), "WebView should exist after opening book")
        sleep(2)

        // Navigate to specific page by swiping
        for _ in 1..<page {
            webView.swipeLeft()
            usleep(500_000) // 0.5 second between swipes
        }

        // Wait for final render
        sleep(1)

        // Capture screenshot
        let screenshot = XCUIScreen.main.screenshot()

        let dirPath = "/tmp/reader-tests"
        try? FileManager.default.createDirectory(
            atPath: dirPath,
            withIntermediateDirectories: true
        )

        let screenshotPath = "\(dirPath)/ios_\(book)_ch\(chapter)_p\(page).png"
        do {
            try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: screenshotPath))
            print("📸 Screenshot saved to: \(screenshotPath)")
        } catch {
            XCTFail("Failed to save screenshot: \(error)")
        }

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "ios_\(book)_ch\(chapter)_p\(page)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Captures screenshots from both HTML (WebView) and Native renderers.
    /// Saves to /tmp/reader-tests/ios_<book>_ch<chapter>_html.png and _native.png
    func testCaptureBothRenderers() {
        let book = config.book
        let chapter = config.chapter
        let dirPath = "/tmp/reader-tests"

        try? FileManager.default.createDirectory(
            atPath: dirPath,
            withIntermediateDirectories: true
        )

        // Already launched with WebView mode in setUp()
        // Wait for the book to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 10), "WebView should exist after opening book")
        sleep(3)

        // Capture HTML/WebView screenshot
        let htmlScreenshot = XCUIScreen.main.screenshot()
        let htmlPath = "\(dirPath)/ios_\(book)_ch\(chapter)_html.png"
        do {
            try htmlScreenshot.pngRepresentation.write(to: URL(fileURLWithPath: htmlPath))
            print("📸 HTML screenshot saved to: \(htmlPath)")
        } catch {
            XCTFail("Failed to save HTML screenshot: \(error)")
        }

        let htmlAttachment = XCTAttachment(screenshot: htmlScreenshot)
        htmlAttachment.name = "ios_\(book)_ch\(chapter)_html"
        htmlAttachment.lifetime = .keepAlways
        add(htmlAttachment)

        // Now switch to Native renderer via Settings
        // Tap to show overlay
        webView.tap()
        sleep(1)

        // Open Settings
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Settings button should exist")
        settingsButton.tap()
        sleep(1)

        // Find and tap the "Renderer" cell to open action sheet
        let rendererCell = app.staticTexts["Renderer"]
        if rendererCell.waitForExistence(timeout: 3) {
            rendererCell.tap()
            sleep(1)

            // Select "Native" from the action sheet
            let nativeButton = app.buttons["Native"]
            if nativeButton.waitForExistence(timeout: 3) {
                nativeButton.tap()
                sleep(1)
            }
        }

        // Dismiss settings
        let doneButton = app.buttons["Done"]
        if doneButton.waitForExistence(timeout: 3) {
            doneButton.tap()
        } else {
            // Try tapping outside or using back navigation
            app.navigationBars.buttons.firstMatch.tap()
        }
        sleep(4) // Wait for renderer switch and re-render

        // Capture Native screenshot
        let nativeScreenshot = XCUIScreen.main.screenshot()
        let nativePath = "\(dirPath)/ios_\(book)_ch\(chapter)_native.png"
        do {
            try nativeScreenshot.pngRepresentation.write(to: URL(fileURLWithPath: nativePath))
            print("📸 Native screenshot saved to: \(nativePath)")
        } catch {
            XCTFail("Failed to save Native screenshot: \(error)")
        }

        let nativeAttachment = XCTAttachment(screenshot: nativeScreenshot)
        nativeAttachment.name = "ios_\(book)_ch\(chapter)_native"
        nativeAttachment.lifetime = .keepAlways
        add(nativeAttachment)
    }
}
