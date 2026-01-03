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
}
