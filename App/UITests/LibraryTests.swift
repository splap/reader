import XCTest

final class LibraryTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = launchReaderApp()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testAppLaunchesInLibrary() {
        // Verify we're on the Library screen
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5), "Library screen should be visible")

        // Verify all three bundled books are present
        let frankenstein = findBook(in: app, containing: "Frankenstein")
        let meditations = findBook(in: app, containing: "Meditations")
        let metamorphosis = findBook(in: app, containing: "Metamorphosis")

        XCTAssertTrue(frankenstein.waitForExistence(timeout: 5), "Bundled book 'Frankenstein' should be visible")
        XCTAssertTrue(meditations.waitForExistence(timeout: 5), "Bundled book 'Meditations' should be visible")
        XCTAssertTrue(metamorphosis.waitForExistence(timeout: 5), "Bundled book 'Metamorphosis' should be visible")
    }

    func testNavigateFromLibraryToSettings() {
        // This test verifies we can navigate from Library to Settings via a book
        // The Settings button is in the reader view, not the library

        // Wait for library to load
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5), "Library should be visible")
        print("Library visible")

        // Open a book first
        let bookCell = findBook(in: app, containing: "Frankenstein")
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5), "Frankenstein should be visible")
        bookCell.tap()

        // Wait for reader to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5), "WebView should exist")
        sleep(2)

        // Tap to reveal overlay
        webView.tap()
        sleep(1)

        // Look for settings button in reader
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Settings button should exist in reader")
        print("Settings button found, tapping...")
        settingsButton.tap()

        // Verify settings screen appears
        let settingsNavBar = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNavBar.waitForExistence(timeout: 5), "Settings screen should appear")
        print("Navigated to settings successfully")
    }

    func testOpenBook() {
        // Wait for library to load
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("Looking for books in library...")

        // Look for Frankenstein by partial title match
        let bookCell = findBook(in: app, containing: "Frankenstein")

        XCTAssertTrue(bookCell.waitForExistence(timeout: 5), "Frankenstein book should be visible in library")
        print("Found Frankenstein")

        // Tap to open the book
        bookCell.tap()
        print("Tapped book to open")

        // Wait for library nav bar to disappear (we've navigated away)
        let libraryDisappeared = !libraryNavBar.waitForExistence(timeout: 2)
        if !libraryDisappeared {
            print("Still on library screen after tap")
        }

        // Give reader time to load and render
        sleep(3)

        // Verify we're in the reader by checking for WebView (book content)
        print("Looking for book content...")

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5), "WebView containing book should exist")
        print("WebView found - book is loaded")

        // Tap to reveal overlay (buttons start hidden)
        webView.tap()
        sleep(1)
        print("Tapped to reveal overlay")

        // Verify Back button exists (proves we're in reader, not library)
        let backButton = app.buttons["Back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 3), "Back button should exist in reader")
        print("Back button found - confirmed in reader view")

        // Check that we have book content by verifying scrubber shows valid chapter info
        // With spine-scoped rendering, we load one chapter at a time
        let pageLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(pageLabel.waitForExistence(timeout: 3), "Scrubber page label should exist")

        let pageLabelText = pageLabel.label
        print("Scrubber label: \(pageLabelText)")

        guard let scrubberInfo = parseScrubberLabel(pageLabelText) else {
            XCTFail("Could not parse scrubber label: \(pageLabelText)")
            return
        }

        // Verify we have substantial book content (Frankenstein has 32 chapters)
        XCTAssertGreaterThan(scrubberInfo.totalChapters, 20,
            "Should have substantial book content loaded (got \(scrubberInfo.totalChapters) chapters)")
        XCTAssertGreaterThan(scrubberInfo.pagesInChapter, 0,
            "Current chapter should have pages")

        print("Book content verified successfully - \(scrubberInfo.totalChapters) chapters, " +
              "page \(scrubberInfo.currentPage) of \(scrubberInfo.pagesInChapter) in chapter \(scrubberInfo.currentChapter)")
    }
}
