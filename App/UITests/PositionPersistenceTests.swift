import XCTest

final class PositionPersistenceTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testPositionPersistence() {
        // This test verifies that reading position is saved and restored using a real book.
        // We navigate to a specific chapter, restart the app, and verify we're still there.

        // First launch: clean state, navigate to chapter 3
        app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--uitesting-skip-indexing",
            "--uitesting-webview",
            "--uitesting-clean-all-data",
        ]
        app.launch()

        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 10), "Library should appear")
        sleep(2)

        guard let webView = openBook(in: app, named: "Frankenstein") else {
            XCTFail("Failed to open Frankenstein")
            return
        }
        print("Frankenstein opened (clean state)")

        // Show overlay and navigate to a later chapter via TOC
        webView.tap()
        sleep(1)

        let tocButton = app.buttons["toc-button"]
        guard tocButton.waitForExistence(timeout: 3) else {
            XCTFail("TOC button not found")
            return
        }
        tocButton.tap()
        sleep(1)

        // Find and tap a chapter that's NOT the first one (Letter 3 or similar)
        let buttons = app.buttons.allElementsBoundByIndex
        for button in buttons {
            let label = button.label
            if label == "III" || label == "IV" || label.contains("Letter 3") || label.contains("Chapter 3") {
                print("Navigating to chapter: \(label)")
                button.tap()
                break
            }
        }
        sleep(3)

        // Verify we're in a later chapter
        webView.tap()
        sleep(2)

        let pageLabel = app.staticTexts["scrubber-page-label"]
        guard pageLabel.waitForExistence(timeout: 5) else {
            XCTFail("Page label not found after TOC navigation")
            return
        }

        let positionText = pageLabel.label
        print("Navigated to position: \(positionText)")

        // Record the chapter we're in
        guard let savedInfo = parseScrubberLabel(positionText) else {
            XCTFail("Could not parse scrubber label: \(positionText)")
            return
        }
        let savedChapter = savedInfo.currentChapter
        print("Saved at chapter \(savedChapter)")

        // Wait for CFI position save to complete (async operation)
        sleep(2)

        // Go back to library to ensure clean state
        let backButton = app.buttons["Back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 3), "Back button should exist")
        backButton.tap()
        sleep(2)

        // Restart app and verify position is restored
        print("Restarting app to verify position persistence...")
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--uitesting-keep-state",
            "--uitesting-webview",
        ]
        app.launch()

        // App may auto-open to the last book (reader) or show library
        // Wait for either the webview (reader) or library to appear
        let webView2 = app.webViews.firstMatch
        if !webView2.waitForExistence(timeout: 10) {
            // If not in reader, check library and open book
            XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5), "Neither reader nor library appeared")
            guard let openedWebView = openBook(in: app, named: "Frankenstein") else {
                XCTFail("Failed to reopen Frankenstein from library")
                return
            }
            print("Frankenstein reopened from library")
            _ = openedWebView
        } else {
            print("App auto-opened to reader (last opened book)")
        }
        sleep(2) // Let content render

        // Check the restored position
        webView2.tap()
        sleep(2)

        let pageLabel2 = app.staticTexts["scrubber-page-label"]
        if !pageLabel2.waitForExistence(timeout: 5) {
            webView2.tap()
            sleep(2)
        }
        guard pageLabel2.waitForExistence(timeout: 5) else {
            XCTFail("Page label not found after reopen")
            return
        }

        let restoredText = pageLabel2.label
        print("Restored position: \(restoredText)")

        // Verify we're NOT at Chapter 1 (starting position) - we should be restored
        guard let restoredInfo = parseScrubberLabel(restoredText) else {
            XCTFail("Could not parse restored scrubber label: \(restoredText)")
            return
        }

        // We should be within 1 chapter of where we saved (layout differences can cause small shifts)
        let chapterDiff = abs(restoredInfo.currentChapter - savedChapter)
        XCTAssertLessThanOrEqual(
            chapterDiff, 1,
            "Position should be restored near chapter \(savedChapter), got chapter \(restoredInfo.currentChapter)"
        )
        XCTAssertGreaterThan(
            restoredInfo.currentChapter, 1,
            "Position should NOT start at chapter 1 - got: \(restoredText)"
        )

        print("Position persistence verified! Saved at Ch.\(savedChapter), restored to Ch.\(restoredInfo.currentChapter)")
    }

    func testPositionRestorationOnDifferentSpine() {
        // Tests that position is correctly restored when the saved position is on a different spine
        // than spine 0. This exposes the bug where opening a book always starts at the beginning.

        // Open Frankenstein with clean state
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-webview", "--uitesting-clean-all-data"]
        app.launch()

        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 10), "Library should appear")
        sleep(2)

        guard let webView = openBook(in: app, named: "Frankenstein") else {
            XCTFail("Failed to open Frankenstein")
            return
        }
        print("Frankenstein opened (clean state)")

        // Reveal overlay
        webView.tap()
        sleep(1)

        // Navigate to a later chapter via TOC
        let tocButton = app.buttons["toc-button"]
        guard tocButton.waitForExistence(timeout: 3) else {
            XCTFail("TOC button not found")
            return
        }
        tocButton.tap()
        sleep(1)

        // Find a chapter that's NOT the first one
        let buttons = app.buttons.allElementsBoundByIndex
        for button in buttons {
            let label = button.label
            if label == "III" || label == "IV" || label.contains("Chapter 3") || label.contains("Letter 3") {
                print("Navigating to chapter: \(label)")
                button.tap()
                break
            }
        }
        sleep(3)

        // Verify we're in a later chapter
        webView.tap()
        sleep(2)

        let pageLabel = app.staticTexts["scrubber-page-label"]
        guard pageLabel.waitForExistence(timeout: 5) else {
            XCTFail("Page label not found after TOC navigation")
            return
        }

        let positionText = pageLabel.label
        print("Navigated to position: \(positionText)")

        // Swipe forward a few times to ensure we're not at the start
        webView.tap() // Hide overlay
        sleep(1)
        for _ in 1 ... 3 {
            webView.swipeLeft()
            usleep(300_000)
        }
        sleep(1)

        webView.tap()
        sleep(1)
        guard pageLabel.waitForExistence(timeout: 5) else {
            XCTFail("Page label not found after swipes")
            return
        }

        let savedPositionText = pageLabel.label
        print("Position to save: \(savedPositionText)")

        // Go back to library to ensure position is saved
        let backButton = app.buttons["Back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 3), "Back button should exist")
        backButton.tap()
        sleep(2)

        // Now relaunch app and verify position is restored
        print("Relaunching app to test position restoration...")
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-webview", "--uitesting-keep-state"]
        app.launch()

        // App may auto-open to the last book (reader) or show library
        let webView2 = app.webViews.firstMatch
        if !webView2.waitForExistence(timeout: 10) {
            // If not in reader, check library and open book
            XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5), "Neither reader nor library appeared after relaunch")
            guard let openedWebView = openBook(in: app, named: "Frankenstein") else {
                XCTFail("Failed to reopen Frankenstein from library")
                return
            }
            _ = openedWebView
        }
        print("Frankenstein reopened")

        // Check the restored position
        webView2.tap()
        sleep(2)

        let pageLabel2 = app.staticTexts["scrubber-page-label"]
        if !pageLabel2.waitForExistence(timeout: 5) {
            webView2.tap()
            sleep(2)
        }
        guard pageLabel2.waitForExistence(timeout: 5) else {
            XCTFail("Page label not found after reopen")
            return
        }

        let restoredText = pageLabel2.label
        print("Restored position: \(restoredText)")

        // The critical assertion: we should NOT be at "Page 1 of X Ch. 1"
        // We should be at the same position we saved
        XCTAssertFalse(restoredText.contains("Page 1 of") && restoredText.contains("Ch. 1"),
                       "BUG CONFIRMED: Position not restored! Started at beginning instead of saved position. Got: \(restoredText)")

        // Take screenshot
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Position Restoration Test"
        attachment.lifetime = .keepAlways
        add(attachment)

        print("Position restoration test complete. Restored to: \(restoredText)")
    }
}
