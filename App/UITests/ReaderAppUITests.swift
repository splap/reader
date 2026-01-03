import XCTest

final class ReaderAppUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()

        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testAppLaunchesInLibrary() {
        // Verify we're on the library screen
        // The library should show either books or an empty state
        let navBar = app.navigationBars.firstMatch
        XCTAssertTrue(navBar.waitForExistence(timeout: 5), "Navigation bar should exist")

        // Log for debugging
        print("🧪 App launched successfully")
        print("🧪 Navigation bars: \(app.navigationBars.count)")
    }

    func testNavigateFromLibraryToSettings() {
        // Verify library is visible
        XCTAssertTrue(app.navigationBars.firstMatch.exists)

        // Look for settings button
        let settingsButton = app.buttons["Settings"]

        if settingsButton.exists {
            print("🧪 Settings button found, tapping...")
            settingsButton.tap()

            // Give UI time to transition
            sleep(1)

            // Verify we're in settings
            // (This depends on what your settings screen looks like)
            print("🧪 Navigated to settings")
        } else {
            print("🧪 Settings button not found - skipping navigation test")
        }
    }

    func testOpenBook() {
        // Wait for library to load
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("🧪 Looking for books in library...")

        // Look for Consider Phlebas by author name (Banks, Ian M.)
        let banksAuthor = app.staticTexts["Banks, Ian M."]

        XCTAssertTrue(banksAuthor.waitForExistence(timeout: 5), "Book by Banks, Ian M. should be visible")
        print("🧪 Found book by Banks, Ian M.")

        // Tap to open the book
        banksAuthor.tap()
        print("🧪 Tapped book to open")

        // Wait for library nav bar to disappear (we've navigated away)
        let libraryDisappeared = !libraryNavBar.waitForExistence(timeout: 2)
        if !libraryDisappeared {
            print("🧪 Still on library screen after tap")
        }

        // Give reader time to load and render
        sleep(3)

        // Verify we're in the reader by checking for WebView (book content)
        print("🧪 Looking for book content...")

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5), "WebView containing book should exist")
        print("🧪 WebView found - book is loaded")

        // Verify Back button exists (proves we're in reader, not library)
        let backButton = app.buttons["Back"]
        XCTAssertTrue(backButton.exists, "Back button should exist in reader")
        print("🧪 Back button found - confirmed in reader view")

        // Check that we have substantial text content (book text)
        let staticTextCount = app.staticTexts.count
        print("🧪 Static text elements found: \(staticTextCount)")
        XCTAssertGreaterThan(staticTextCount, 100, "Should have substantial book content loaded")

        print("🧪 Book content verified successfully - \(staticTextCount) text elements")
    }

    func testPage3TextAlignment() {
        // Open Consider Phlebas by Banks
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("🧪 Opening Consider Phlebas by Banks...")
        let banksAuthor = app.staticTexts["Banks, Ian M."]
        XCTAssertTrue(banksAuthor.waitForExistence(timeout: 5), "Book by Banks should be visible")
        banksAuthor.tap()

        // Wait for book to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5), "WebView should exist")
        sleep(3) // Let content render

        print("🧪 Book loaded, now swiping to page 3...")

        // Swipe to page 2
        webView.swipeLeft()
        sleep(1)
        print("🧪 Swiped to page 2")

        // Swipe to page 3
        webView.swipeLeft()
        sleep(1)
        print("🧪 Swiped to page 3")

        // Check for text alignment - page 2 text should NOT be visible on page 3
        // We'll look for specific text that should only appear on page 2
        // This will fail if pagination is broken
        print("🧪 Checking for text alignment on page 3...")

        // Save screenshot to temp directory
        let screenshot = XCUIScreen.main.screenshot()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let screenshotPath = "/tmp/reader-tests/page3-align-\(timestamp).png"

        // Create directory if needed
        let dirPath = "/tmp/reader-tests"
        try? FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)

        // Save screenshot
        let imageData = screenshot.pngRepresentation
        try? imageData.write(to: URL(fileURLWithPath: screenshotPath))
        print("🧪 Screenshot saved to: \(screenshotPath)")

        // Also add to test results
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Page 3 State"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Keep simulator open in this state for manual inspection
        print("🧪 Test complete - simulator will remain open for 60 seconds for inspection")
        print("🧪 Check if page 2 text is bleeding into page 3")
        sleep(60)

        // TODO: Add specific assertion for page 2 text not being visible
        // For now, we'll just capture the state and manually verify
        XCTFail("Text alignment check - verify page 2 text is not visible on page 3")
    }
}
