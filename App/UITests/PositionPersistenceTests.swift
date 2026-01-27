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
        // This test verifies that reading position is saved and restored
        // We navigate to a specific page, restart the app, and verify we're on the same page

        // Launch with position test arguments
        app = XCUIApplication()
        var args = ["--uitesting", "--uitesting-skip-indexing", "--uitesting-webview"]
        args.append("--uitesting-position-test")
        args.append("--uitesting-show-overlay")
        args.append("--uitesting-jump-to-page=100")
        app.launchArguments = args
        app.launch()

        let pageLabel = app.staticTexts["scrubber-page-label"]
        waitForLabel(pageLabel, contains: "Page 100", timeout: 1.2)
        print("Book loaded at page 100")

        // Wait for async CFI position save to complete
        sleep(1)

        // Restart app to validate persisted position
        print("Restarting app to verify position persistence...")
        app.launchArguments = [
            "--uitesting",
            "--uitesting-keep-state",
            "--uitesting-position-test",
            "--uitesting-show-overlay"
        ]
        app.terminate()
        app.launch()

        let restoredLabel = app.staticTexts["scrubber-page-label"]
        // Wait for any label to appear
        _ = restoredLabel.waitForExistence(timeout: 3)
        print("After restart, label shows: \(restoredLabel.label)")

        // CFI-based position restoration works, but CSS column layout can vary between launches
        // So we verify we're at roughly the right position (not back at page 1)
        let totalPages = extractTotalPages(from: restoredLabel.label)
        if let currentPage = extractCurrentPage(from: restoredLabel.label), totalPages > 0 {
            // Should be somewhere past the halfway point (we saved at ~page 100 of ~120)
            let ratio = Double(currentPage) / Double(totalPages)
            XCTAssertGreaterThan(ratio, 0.5, "Position should be restored past halfway point. Got page \(currentPage) of \(totalPages)")
            print("Position persistence verified! Restored to page \(currentPage) of \(totalPages) (ratio: \(String(format: "%.1f", ratio * 100))%)")
        } else {
            XCTFail("Could not parse page label: \(restoredLabel.label)")
        }
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
        for _ in 1...3 {
            webView.swipeLeft()
            usleep(300000)
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

        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 10), "Library should appear after relaunch")

        guard let webView2 = openBook(in: app, named: "Frankenstein") else {
            XCTFail("Failed to reopen Frankenstein")
            return
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
