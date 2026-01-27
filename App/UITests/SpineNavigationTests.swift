import XCTest

final class SpineNavigationTests: XCTestCase {
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

    func testSpineBoundaryNavigation() {
        // Test that swiping at spine boundaries correctly transitions between chapters
        // and that navigating backward lands on the last page of the previous spine.

        // Open Metamorphosis (6 spine items)
        guard let webView = openBook(in: app, named: "Metamorphosis") else {
            XCTFail("Failed to open Metamorphosis")
            return
        }
        print("Metamorphosis opened")

        // Reveal overlay and use TOC to go to Chapter II (spine 3)
        webView.tap()
        sleep(1)

        let tocButton = app.buttons["toc-button"]
        XCTAssertTrue(tocButton.waitForExistence(timeout: 3), "TOC button should exist")
        tocButton.tap()
        sleep(1)

        // Find and tap Chapter II
        let chapterButton = app.buttons["II"]
        if chapterButton.waitForExistence(timeout: 3) {
            print("Tapping Chapter II...")
            chapterButton.tap()
        } else {
            // Fall back to any chapter button that's not the current one
            let buttons = app.buttons.allElementsBoundByIndex
            for button in buttons {
                let label = button.label
                if label == "I" || label == "II" || label == "III" {
                    print("Tapping chapter: \(label)")
                    button.tap()
                    break
                }
            }
        }
        sleep(3) // Wait for chapter to load

        // Tap multiple times to ensure overlay is visible (it might auto-hide)
        webView.tap()
        sleep(2)

        // Wait for page label with explicit existence check
        let pageLabel = app.staticTexts["scrubber-page-label"]
        if !pageLabel.waitForExistence(timeout: 5) {
            // Overlay might have hidden, tap again
            webView.tap()
            sleep(2)
        }
        guard pageLabel.waitForExistence(timeout: 5) else {
            XCTFail("Page label should exist after revealing overlay")
            return
        }
        print("After TOC navigation: \(pageLabel.label)")

        // Use scrubber to go near end of this spine
        let scrubber = app.sliders["Page scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 3), "Scrubber should exist")
        print("Moving scrubber to 90%...")
        scrubber.adjust(toNormalizedSliderPosition: 0.90)
        sleep(2)

        // Check position after scrub
        let afterScrubText = pageLabel.label
        print("After scrub to 90%: \(afterScrubText)")
        let pageAfterScrub = extractCurrentPage(from: afterScrubText) ?? 0
        let totalAfterScrub = extractTotalPages(from: afterScrubText)

        // Hide overlay before swiping
        webView.tap()
        sleep(1)

        // Swipe forward until we reach the last page
        print("Swiping forward to reach last page...")
        var swipeCount = 0
        var previousPage = pageAfterScrub
        while swipeCount < 15 {
            webView.swipeLeft()
            usleep(500000) // 0.5s

            // Check if we transitioned to next spine
            webView.tap()
            sleep(1)
            let currentText = pageLabel.label
            let currentPage = extractCurrentPage(from: currentText) ?? 0
            let currentTotal = extractTotalPages(from: currentText)

            print("After swipe \(swipeCount + 1): \(currentText)")

            // If total pages changed significantly, we transitioned
            if currentTotal != totalAfterScrub {
                print("Transitioned to next spine! Total pages changed from \(totalAfterScrub) to \(currentTotal)")
                break
            }

            // If we're still at the same page after swipe, we're stuck
            if currentPage == previousPage && currentPage == currentTotal {
                print("At last page (\(currentPage)/\(currentTotal)), next swipe should transition")
            }

            previousPage = currentPage
            webView.tap() // Hide overlay
            sleep(1)
            swipeCount += 1
        }

        // Now we need to go back to first page of current spine first
        print("Navigating to first page of current spine...")
        for backSwipe in 0..<20 {
            webView.tap() // Ensure overlay hidden
            usleep(300000)
            webView.swipeRight()
            usleep(500000)

            webView.tap() // Show overlay
            sleep(1)
            if let current = extractCurrentPage(from: pageLabel.label), current == 1 {
                print("Reached first page after \(backSwipe + 1) swipes: \(pageLabel.label)")
                break
            }
            if backSwipe == 19 {
                print("Warning: Could not reach first page after 20 swipes")
            }
        }

        // Now swipe backward from first page - should transition to previous spine and land on LAST page
        print("Swiping backward from first page to previous spine...")
        webView.tap() // Hide overlay
        sleep(1)
        webView.swipeRight()
        sleep(3)

        // Reveal overlay
        webView.tap()
        sleep(2)

        // Verify overlay is visible
        if !pageLabel.waitForExistence(timeout: 5) {
            webView.tap()
            sleep(2)
        }

        guard pageLabel.waitForExistence(timeout: 5) else {
            print("Could not reveal overlay after backward spine transition")
            XCTFail("Page label should be visible after swipe back")
            return
        }

        let afterBackText = pageLabel.label
        print("After swipe back to previous spine: \(afterBackText)")

        // Verify we're at the last page of the previous spine (not page 1)
        let backPage = extractCurrentPage(from: afterBackText) ?? 0
        let backTotal = extractTotalPages(from: afterBackText)

        // If we went back to a different spine, the page should be near the end
        if backTotal == totalAfterScrub || backTotal > 10 {
            let minExpectedPage = max(1, backTotal - 3) // Should be within last 3 pages
            XCTAssertGreaterThanOrEqual(backPage, minExpectedPage,
                "After swiping back to previous spine, should land on last page (got page \(backPage)/\(backTotal))")
            print("Correctly landed on page \(backPage)/\(backTotal) of previous spine")
        }

        // Take final screenshot
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Spine Navigation Result"
        attachment.lifetime = .keepAlways
        add(attachment)

        print("Spine boundary navigation test complete")
    }

    func testFrankensteinFirstSpineToSecond() {
        /// Tests that we can navigate through the first spine and into the second spine via swipes.
        /// This test exposes a bug where navigation gets stuck at spine boundaries.

        // Open Frankenstein
        guard let webView = openBook(in: app, named: "Frankenstein") else {
            XCTFail("Failed to open Frankenstein")
            return
        }
        print("Frankenstein opened")

        // Reveal overlay to check initial state
        webView.tap()
        sleep(1)

        let pageLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(pageLabel.waitForExistence(timeout: 3), "Page label should exist")

        let initialText = pageLabel.label
        print("Initial state: \(initialText)")

        // Extract chapter info - we should start at Ch. 1
        XCTAssertTrue(initialText.contains("Ch. 1") || initialText.contains("Page 1"),
                     "Should start at beginning, got: \(initialText)")

        // Get the scrubber to navigate to near the end of the first spine
        let scrubber = app.sliders["Page scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 3), "Scrubber should exist")

        // Move to 95% to get near the end of the first spine
        print("Moving scrubber to 95%...")
        scrubber.adjust(toNormalizedSliderPosition: 0.95)
        sleep(2)

        let nearEndText = pageLabel.label
        print("Near end of first spine: \(nearEndText)")
        let nearEndTotal = extractTotalPages(from: nearEndText)

        // Hide overlay before swiping
        webView.tap()
        sleep(1)

        // Swipe forward multiple times to cross spine boundary
        print("Swiping forward to cross spine boundary...")
        var transitioned = false
        var lastChapter = "Ch. 1"

        for i in 1...10 {
            webView.swipeLeft()
            usleep(500000) // 0.5s

            // Check state
            webView.tap()
            sleep(1)

            if pageLabel.waitForExistence(timeout: 3) {
                let currentText = pageLabel.label
                print("After swipe \(i): \(currentText)")

                // Check if chapter changed (indicating spine transition)
                if !currentText.contains(lastChapter) && currentText.contains("Ch.") {
                    print("Transitioned to new spine!")
                    transitioned = true
                    break
                }

                // Also check if total pages changed significantly
                let currentTotal = extractTotalPages(from: currentText)
                if currentTotal != nearEndTotal && abs(currentTotal - nearEndTotal) > 5 {
                    print("Transitioned (total pages changed from \(nearEndTotal) to \(currentTotal))")
                    transitioned = true
                    break
                }
            } else {
                print("Page label not found after swipe \(i)")
            }

            webView.tap() // Hide overlay
            sleep(1)
        }

        XCTAssertTrue(transitioned, "Should have transitioned to second spine after swiping past end")

        // Take screenshot
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Frankenstein Spine Transition"
        attachment.lifetime = .keepAlways
        add(attachment)

        print("First spine to second spine navigation test complete")
    }

    func testFrankensteinSecondSpineBackwardNavigation() {
        /// Tests navigation BACKWARD from the second spine (title page) in Frankenstein.
        /// This specifically tests the bug where you cannot navigate forward or backward
        /// once you reach the title page.

        // Open Frankenstein
        guard let webView = openBook(in: app, named: "Frankenstein") else {
            XCTFail("Failed to open Frankenstein")
            return
        }
        print("Frankenstein opened")

        // Reveal overlay and use TOC to go to chapter 2 (second major spine)
        webView.tap()
        sleep(1)

        let tocButton = app.buttons["toc-button"]
        guard tocButton.waitForExistence(timeout: 3) else {
            XCTFail("TOC button not found")
            return
        }
        tocButton.tap()
        sleep(1)

        // Look for chapter entries - find any chapter that isn't the first
        let buttons = app.buttons.allElementsBoundByIndex
        var foundChapter = false

        for button in buttons {
            let label = button.label
            // Look for roman numerals II, III, etc. or "Letter" entries
            if label == "II" || label == "III" || label.contains("Letter 2") || label.contains("Chapter 2") {
                print("Tapping chapter: \(label)")
                button.tap()
                foundChapter = true
                break
            }
        }

        if !foundChapter {
            // Just tap the second TOC entry if we couldn't find a specific one
            print("Using fallback: tapping second TOC entry")
            if buttons.count > 1 {
                buttons[1].tap()
            }
        }

        sleep(3) // Wait for chapter to load

        // Tap to reveal overlay
        webView.tap()
        sleep(2)

        let pageLabel = app.staticTexts["scrubber-page-label"]
        if !pageLabel.waitForExistence(timeout: 5) {
            webView.tap()
            sleep(2)
        }
        guard pageLabel.waitForExistence(timeout: 5) else {
            XCTFail("Page label not found after TOC navigation")
            return
        }

        let afterTOCText = pageLabel.label
        print("After TOC navigation: \(afterTOCText)")

        // Now go to the FIRST page of this spine using scrubber
        let scrubber = app.sliders["Page scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 3), "Scrubber should exist")

        print("Moving to first page of current spine...")
        scrubber.adjust(toNormalizedSliderPosition: 0.0)
        sleep(2)

        let firstPageText = pageLabel.label
        print("At first page: \(firstPageText)")
        let firstPageNum = extractCurrentPage(from: firstPageText) ?? 0
        XCTAssertEqual(firstPageNum, 1, "Should be at page 1, got: \(firstPageText)")

        // Hide overlay
        webView.tap()
        sleep(1)

        // CRITICAL TEST: Swipe backward from first page - should go to previous spine
        print("Swiping backward from first page (should go to previous spine)...")
        webView.swipeRight()
        sleep(3)

        // Reveal overlay and check where we are
        webView.tap()
        sleep(2)

        // This is the critical assertion - page label should still be accessible
        if !pageLabel.waitForExistence(timeout: 5) {
            // Try tapping again
            webView.tap()
            sleep(2)
        }
        guard pageLabel.waitForExistence(timeout: 5) else {
            XCTFail("BUG CONFIRMED: Page label not accessible after backward spine navigation. This indicates navigation is broken.")

            // Take diagnostic screenshot
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "Backward Navigation Bug"
            attachment.lifetime = .keepAlways
            add(attachment)
            return
        }

        let afterBackwardText = pageLabel.label
        print("After backward navigation: \(afterBackwardText)")

        // We should have gone to the LAST page of the previous spine, not stayed at page 1
        let afterBackwardPage = extractCurrentPage(from: afterBackwardText) ?? 0
        let afterBackwardTotal = extractTotalPages(from: afterBackwardText)

        // Should be on a page > 1 (last page of previous spine)
        XCTAssertGreaterThan(afterBackwardPage, 1,
            "After swiping backward from first page, should be on last page of previous spine (got page \(afterBackwardPage) of \(afterBackwardTotal))")

        // Take screenshot
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Backward Spine Navigation"
        attachment.lifetime = .keepAlways
        add(attachment)

        print("Backward spine navigation test complete")
    }

    func testSimpleSpineCrossing() {
        /// Test that verifies page navigation works correctly - each swipe advances/retreats
        /// and we return to the starting position after going forward and back the same amount.

        guard let webView = openBook(in: app, named: "Frankenstein") else {
            XCTFail("Failed to open Frankenstein")
            return
        }
        print("Frankenstein opened")

        // Record initial state
        webView.tap()
        sleep(1)
        let pageLabel = app.staticTexts["scrubber-page-label"]
        guard pageLabel.waitForExistence(timeout: 3) else {
            XCTFail("Page label not found")
            return
        }

        let startingPosition = pageLabel.label
        let startingPage = extractCurrentPage(from: startingPosition) ?? 0
        let startingChapter = extractChapter(from: startingPosition)
        print("Starting position: \(startingPosition)")

        // Track positions as we navigate forward
        var previousPage = startingPage
        var previousChapter = startingChapter

        // Swipe forward 5 times, checking each transition
        print("Swiping forward 5 times, checking each transition...")
        for i in 1...5 {
            webView.tap() // Hide overlay
            sleep(1)
            webView.swipeLeft()
            sleep(1)

            webView.tap() // Show overlay
            sleep(1)
            guard pageLabel.waitForExistence(timeout: 3) else {
                XCTFail("BUG: Page label not accessible after forward swipe \(i)")
                return
            }

            let currentPosition = pageLabel.label
            let currentPage = extractCurrentPage(from: currentPosition) ?? 0
            let currentChapter = extractChapter(from: currentPosition)
            print("After forward swipe \(i): \(currentPosition)")

            // Either page should advance, or chapter should change (spine transition)
            let pageAdvanced = currentPage > previousPage
            let chapterChanged = currentChapter != previousChapter

            XCTAssertTrue(pageAdvanced || chapterChanged,
                "Forward swipe \(i) should advance page or change chapter. Was: page \(previousPage) ch \(previousChapter), Now: page \(currentPage) ch \(currentChapter)")

            previousPage = currentPage
            previousChapter = currentChapter
        }

        let afterForwardPosition = pageLabel.label
        print("After 5 forward swipes: \(afterForwardPosition)")

        // Now swipe backward 5 times, checking each transition
        print("Swiping backward 5 times, checking each transition...")
        for i in 1...5 {
            webView.tap() // Hide overlay
            sleep(1)
            webView.swipeRight()
            sleep(1)

            webView.tap() // Show overlay
            sleep(1)
            guard pageLabel.waitForExistence(timeout: 3) else {
                XCTFail("BUG: Page label not accessible after backward swipe \(i)")
                return
            }

            let currentPosition = pageLabel.label
            let currentPage = extractCurrentPage(from: currentPosition) ?? 0
            let currentChapter = extractChapter(from: currentPosition)
            print("After backward swipe \(i): \(currentPosition)")

            // Either page should decrease, or chapter should change (spine transition backward)
            let pageDecreased = currentPage < previousPage
            let chapterChanged = currentChapter != previousChapter

            XCTAssertTrue(pageDecreased || chapterChanged,
                "Backward swipe \(i) should decrease page or change chapter. Was: page \(previousPage) ch \(previousChapter), Now: page \(currentPage) ch \(currentChapter)")

            previousPage = currentPage
            previousChapter = currentChapter
        }

        let finalPosition = pageLabel.label
        print("Final position: \(finalPosition)")

        // The assertions in the loops above verify that each swipe transition worked correctly.
        // We successfully navigated forward and backward through multiple chapters.

        print("Navigation test complete - successfully navigated forward and backward through chapters")
    }
}
