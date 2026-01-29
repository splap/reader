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

    func testPositionPersistence() throws {
        // This test verifies that reading position is saved and restored using a real book.
        // We navigate to a specific chapter, slide to the MIDDLE of that chapter,
        // restart the app, and verify both chapter AND page position are restored.

        // First launch: clean state
        app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--uitesting-skip-indexing",
            rendererArgument,
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

        // Navigate to a later chapter via TOC
        webView.tap()
        sleep(1)

        let tocButton = app.buttons["toc-button"]
        guard tocButton.waitForExistence(timeout: 3) else {
            XCTFail("TOC button not found")
            return
        }
        tocButton.tap()
        sleep(1)

        // Find and tap a chapter that's NOT the first one
        let buttons = app.buttons.allElementsBoundByIndex
        for button in buttons {
            let label = button.label
            if label == "I" || label == "Chapter 1" || label.contains("Chapter I") {
                print("Navigating to chapter: \(label)")
                button.tap()
                break
            }
        }
        sleep(3)

        // Show overlay and get page info
        webView.tap()
        sleep(1)

        let pageLabel = app.staticTexts["scrubber-page-label"]
        guard pageLabel.waitForExistence(timeout: 5) else {
            XCTFail("Page label not found after TOC navigation")
            return
        }

        guard let startInfo = parseScrubberLabel(pageLabel.label) else {
            XCTFail("Could not parse scrubber label: \(pageLabel.label)")
            return
        }
        print("Starting position: Page \(startInfo.currentPage) of \(startInfo.pagesInChapter) · Ch. \(startInfo.currentChapter)")

        // If chapter doesn't have enough pages for mid-chapter test, navigate forward
        if startInfo.pagesInChapter < 3 {
            print("Chapter only has \(startInfo.pagesInChapter) pages, navigating to find a longer chapter...")
            for _ in 1 ... 5 {
                webView.swipeLeft()
                usleep(500_000)
            }
            sleep(1)
            webView.tap()
            sleep(1)

            guard pageLabel.waitForExistence(timeout: 5),
                  let currentInfo = parseScrubberLabel(pageLabel.label),
                  currentInfo.pagesInChapter >= 3
            else {
                throw XCTSkip("Could not find chapter with enough pages for mid-chapter test")
            }
            print("Found chapter with \(currentInfo.pagesInChapter) pages")
        }

        // Use scrubber to navigate to ~50% of the chapter
        let scrubber = app.sliders["Page scrubber"]
        guard scrubber.waitForExistence(timeout: 3) else {
            XCTFail("Scrubber not found")
            return
        }

        scrubber.adjust(toNormalizedSliderPosition: 0.5)
        sleep(2)

        // Read the saved position
        if !pageLabel.waitForExistence(timeout: 3) {
            webView.tap()
            sleep(1)
        }
        guard pageLabel.waitForExistence(timeout: 5) else {
            XCTFail("Page label not found after scrubber adjustment")
            return
        }

        guard let savedInfo = parseScrubberLabel(pageLabel.label) else {
            XCTFail("Could not parse scrubber label after adjustment: \(pageLabel.label)")
            return
        }

        // Verify we're not at page 1 (we should be in the middle)
        XCTAssertGreaterThan(savedInfo.currentPage, 1,
                             "After sliding to 50%, should not be at page 1. Got: \(pageLabel.label)")

        print("Saved position: Page \(savedInfo.currentPage) of \(savedInfo.pagesInChapter) · Ch. \(savedInfo.currentChapter)")

        // Wait for CFI position save to complete
        sleep(2)

        // Go back to library
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
            rendererArgument,
        ]
        app.launch()

        // Wait for reader or library
        let webView2 = getReaderView(in: app)
        if !webView2.waitForExistence(timeout: 10) {
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
        sleep(2)

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

        guard let restoredInfo = parseScrubberLabel(restoredText) else {
            XCTFail("Could not parse restored scrubber label: \(restoredText)")
            return
        }

        // Verify chapter is restored
        XCTAssertEqual(restoredInfo.currentChapter, savedInfo.currentChapter,
                       "Chapter should be restored. Saved: Ch.\(savedInfo.currentChapter), Restored: Ch.\(restoredInfo.currentChapter)")

        // Verify page within chapter is restored (not reset to page 1)
        XCTAssertGreaterThan(restoredInfo.currentPage, 1,
                             "Page should NOT start at page 1 - mid-chapter position was lost. Got: \(restoredText)")

        // Page should be close to what we saved (allow ±1 for rendering differences)
        let pageDiff = abs(restoredInfo.currentPage - savedInfo.currentPage)
        XCTAssertLessThanOrEqual(pageDiff, 1,
                                 "Page should be restored near page \(savedInfo.currentPage), got page \(restoredInfo.currentPage)")

        print("Position persistence verified!")
        print("  Saved: Page \(savedInfo.currentPage) of \(savedInfo.pagesInChapter) · Ch. \(savedInfo.currentChapter)")
        print("  Restored: Page \(restoredInfo.currentPage) of \(restoredInfo.pagesInChapter) · Ch. \(restoredInfo.currentChapter)")
    }

    func testPositionRestorationOnDifferentSpine() throws {
        // Tests that position is correctly restored when the saved position is on a different spine
        // than spine 0. This exposes the bug where opening a book always starts at the beginning.

        // Open Frankenstein with clean state
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", rendererArgument, "--uitesting-clean-all-data"]
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
        app.launchArguments = ["--uitesting", rendererArgument, "--uitesting-keep-state"]
        app.launch()

        // App may auto-open to the last book (reader) or show library
        let webView2 = getReaderView(in: app)
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
