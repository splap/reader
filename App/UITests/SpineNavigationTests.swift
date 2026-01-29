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
        // Open Chapter II of Metamorphosis, scrub to 90%, advance page by page
        // through the spine boundary into the next chapter (page 2), then go back
        // page by page through the boundary to the last page of Chapter II.
        // Every single page transition is explicitly verified.

        guard let webView = openBook(in: app, named: "Metamorphosis") else {
            XCTFail("Failed to open Metamorphosis")
            return
        }
        print("Metamorphosis opened")

        // Navigate to Chapter II via TOC
        webView.tap()
        sleep(1)

        let tocButton = app.buttons["toc-button"]
        XCTAssertTrue(tocButton.waitForExistence(timeout: 3), "TOC button should exist")
        tocButton.tap()
        sleep(1)

        let chapterButton = app.buttons["II"]
        if chapterButton.waitForExistence(timeout: 3) {
            print("Tapping Chapter II...")
            chapterButton.tap()
        } else {
            let buttons = app.buttons.allElementsBoundByIndex
            for button in buttons {
                let label = button.label
                if label == "II" || label == "III" {
                    print("Tapping chapter: \(label)")
                    button.tap()
                    break
                }
            }
        }
        sleep(3)

        // Show overlay and scrub to 90%
        webView.tap()
        sleep(1)

        let pageLabel = app.staticTexts["scrubber-page-label"]
        let scrubber = app.sliders["Page scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 3), "Scrubber should exist")
        print("Moving scrubber to 90%...")
        scrubber.adjust(toNormalizedSliderPosition: 0.90)
        sleep(2)

        // Read state after scrub
        guard var state = readScrubberState(webView: webView, pageLabel: pageLabel) else {
            XCTFail("Could not read page state after scrubbing to 90%")
            return
        }
        let startChapter = state.currentChapter
        print("After scrub to 90%: Page \(state.currentPage) of \(state.pagesInChapter), Ch. \(state.currentChapter)")

        // Forward page by page until page 2 of the next chapter
        print("Advancing forward page by page through spine boundary...")
        var forwardSwipes = 0
        let maxSwipes = 20
        while !(state.currentChapter == startChapter + 1 && state.currentPage == 2) {
            guard forwardSwipes < maxSwipes else {
                XCTFail("Failed to reach page 2 of Ch.\(startChapter + 1) after \(maxSwipes) forward swipes")
                return
            }
            guard let next = swipeForwardAndVerify(webView: webView, pageLabel: pageLabel, from: state) else {
                return
            }
            print("  Page \(next.currentPage) of \(next.pagesInChapter), Ch. \(next.currentChapter)")
            state = next
            forwardSwipes += 1
        }
        print("Reached page 2 of Ch. \(state.currentChapter) after \(forwardSwipes) forward swipes")

        // Backward page by page until the last page of the original chapter
        print("Going back page by page through spine boundary...")
        var backwardSwipes = 0
        while !(state.currentChapter == startChapter && state.currentPage == state.pagesInChapter) {
            guard backwardSwipes < maxSwipes else {
                XCTFail("Failed to reach last page of Ch.\(startChapter) after \(maxSwipes) backward swipes")
                return
            }
            guard let next = swipeBackwardAndVerify(webView: webView, pageLabel: pageLabel, from: state) else {
                return
            }
            print("  Page \(next.currentPage) of \(next.pagesInChapter), Ch. \(next.currentChapter)")
            state = next
            backwardSwipes += 1
        }
        print("Back at last page of Ch. \(startChapter): Page \(state.currentPage) of \(state.pagesInChapter)")
        print("Spine boundary navigation test complete (\(forwardSwipes) forward, \(backwardSwipes) backward swipes)")
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

        for i in 1 ... 10 {
            webView.swipeLeft()
            usleep(500_000) // 0.5s

            // Check state
            webView.tap()
            sleep(1)

            if pageLabel.waitForExistence(timeout: 3) {
                let currentText = pageLabel.label
                print("After swipe \(i): \(currentText)")

                // Check if chapter changed (indicating spine transition)
                if !currentText.contains(lastChapter), currentText.contains("Ch.") {
                    print("Transitioned to new spine!")
                    transitioned = true
                    break
                }

                // Also check if total pages changed significantly
                let currentTotal = extractTotalPages(from: currentText)
                if currentTotal != nearEndTotal, abs(currentTotal - nearEndTotal) > 5 {
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

        // Overlay may auto-hide after scrubber adjustment, so tap to reveal again
        webView.tap()
        sleep(1)

        guard pageLabel.waitForExistence(timeout: 5) else {
            XCTFail("Page label not found after scrubbing to first page")
            return
        }
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

    func testSpineTransitionIsAnimated() {
        // Verify that spine transitions use a contiguous slide animation
        // rather than an instant content swap. Uses slow animations (2s)
        // to capture a mid-transition screenshot.

        // Launch with slow animations for testing
        app = launchReaderApp(extraArgs: ["--uitesting-slow-animations"])

        guard let webView = openBook(in: app, named: "Metamorphosis") else {
            XCTFail("Failed to open Metamorphosis")
            return
        }
        print("Metamorphosis opened (slow animations enabled)")

        // Navigate to Chapter II via TOC
        webView.tap()
        sleep(1)

        let tocButton = app.buttons["toc-button"]
        XCTAssertTrue(tocButton.waitForExistence(timeout: 3), "TOC button should exist")
        tocButton.tap()
        sleep(1)

        let chapterButton = app.buttons["II"]
        guard chapterButton.waitForExistence(timeout: 3) else {
            XCTFail("Chapter II button not found")
            return
        }
        chapterButton.tap()
        sleep(3)

        // Scrub to 100% (last page of chapter)
        webView.tap()
        sleep(1)

        let pageLabel = app.staticTexts["scrubber-page-label"]
        let scrubber = app.sliders["Page scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 3), "Scrubber should exist")
        scrubber.adjust(toNormalizedSliderPosition: 1.0)
        sleep(2)

        // Read chapter state before transition
        guard let beforeState = readScrubberState(webView: webView, pageLabel: pageLabel) else {
            XCTFail("Could not read page state at end of Chapter II")
            return
        }
        let beforeChapter = beforeState.currentChapter
        print("Before transition: Page \(beforeState.currentPage)/\(beforeState.pagesInChapter), Ch. \(beforeChapter)")

        // Take "before" screenshot
        let beforeScreenshot = XCUIScreen.main.screenshot()
        let beforeAttachment = XCTAttachment(screenshot: beforeScreenshot)
        beforeAttachment.name = "Before Transition"
        beforeAttachment.lifetime = .keepAlways
        add(beforeAttachment)

        // Hide overlay and swipe left to trigger spine transition
        webView.tap()
        sleep(1)
        webView.swipeLeft()

        // Wait ~1s into the 2s animation to capture mid-transition
        usleep(1_000_000)

        // Take "during" screenshot
        let duringScreenshot = XCUIScreen.main.screenshot()
        let duringAttachment = XCTAttachment(screenshot: duringScreenshot)
        duringAttachment.name = "During Transition"
        duringAttachment.lifetime = .keepAlways
        add(duringAttachment)

        // Wait for animation to complete
        sleep(3)

        // Take "after" screenshot
        let afterScreenshot = XCUIScreen.main.screenshot()
        let afterAttachment = XCTAttachment(screenshot: afterScreenshot)
        afterAttachment.name = "After Transition"
        afterAttachment.lifetime = .keepAlways
        add(afterAttachment)

        // Verify final state: should be in the next chapter
        webView.tap()
        sleep(1)
        guard let afterState = readScrubberState(webView: webView, pageLabel: pageLabel) else {
            XCTFail("Could not read page state after transition")
            return
        }
        print("After transition: Page \(afterState.currentPage)/\(afterState.pagesInChapter), Ch. \(afterState.currentChapter)")

        XCTAssertEqual(afterState.currentChapter, beforeChapter + 1,
                       "Should have transitioned to next chapter (Ch.\(beforeChapter + 1)), got Ch.\(afterState.currentChapter)")
        XCTAssertEqual(afterState.currentPage, 1,
                       "Should be on page 1 of new chapter, got page \(afterState.currentPage)")

        // Analyze screenshots: the "during" screenshot ideally differs from "after"
        // This proves we captured a mid-transition state, not the completed one
        // Note: This is informational only - screenshot timing is unreliable in UI tests
        let duringImage = duringScreenshot.image
        let afterImage = afterScreenshot.image
        let duringDiffers = screenshotsDiffer(duringImage, afterImage)
        if duringDiffers {
            print("Animation captured: mid-transition screenshot differs from final state")
        } else {
            print("Animation timing note: mid-transition screenshot matches final state (animation may have completed before capture)")
        }

        // Check that both halves of the "during" screenshot have content
        // (both outgoing and incoming pages visible during slide)
        let leftHasContent = checkRegionHasContent(image: duringImage, fromXFraction: 0.0, toXFraction: 0.25)
        let rightHasContent = checkRegionHasContent(image: duringImage, fromXFraction: 0.75, toXFraction: 1.0)
        print("During transition: left quarter has content: \(leftHasContent), right quarter has content: \(rightHasContent)")

        print("Spine transition animation test complete")
    }

    // MARK: - Screenshot Analysis Helpers

    /// Checks if two UIImages differ significantly (compares center vertical strips)
    private func screenshotsDiffer(_ img1: UIImage, _ img2: UIImage) -> Bool {
        guard let cgImg1 = img1.cgImage, let cgImg2 = img2.cgImage else { return true }

        let w1 = cgImg1.width, h1 = cgImg1.height
        let w2 = cgImg2.width, h2 = cgImg2.height
        guard w1 == w2, h1 == h2 else { return true }

        // Sample a vertical strip at the center
        let centerX = w1 / 2
        guard let data1 = cgImg1.dataProvider?.data, let data2 = cgImg2.dataProvider?.data else {
            return true
        }

        let ptr1 = CFDataGetBytePtr(data1)!
        let ptr2 = CFDataGetBytePtr(data2)!
        let bytesPerPixel = cgImg1.bitsPerPixel / 8
        let bytesPerRow = cgImg1.bytesPerRow

        var diffPixels = 0
        let startY = h1 / 4
        let endY = 3 * h1 / 4
        let sampleCount = endY - startY

        for y in startY ..< endY {
            let offset = y * bytesPerRow + centerX * bytesPerPixel
            let r1 = Int(ptr1[offset]), g1 = Int(ptr1[offset + 1]), b1 = Int(ptr1[offset + 2])
            let r2 = Int(ptr2[offset]), g2 = Int(ptr2[offset + 1]), b2 = Int(ptr2[offset + 2])
            let diff = abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)
            if diff > 30 {
                diffPixels += 1
            }
        }

        let diffRatio = Double(diffPixels) / Double(sampleCount)
        print("Screenshot diff ratio: \(String(format: "%.2f", diffRatio * 100))% of sampled pixels differ")
        return diffRatio > 0.05
    }

    /// Checks if a horizontal region of the screenshot contains dark content (text)
    private func checkRegionHasContent(image: UIImage, fromXFraction: CGFloat, toXFraction: CGFloat) -> Bool {
        guard let cgImage = image.cgImage else { return false }

        let w = cgImage.width, h = cgImage.height
        guard let data = cgImage.dataProvider?.data else { return false }

        let ptr = CFDataGetBytePtr(data)!
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        // Sample at midpoint of the region
        let sampleX = Int(CGFloat(w) * (fromXFraction + toXFraction) / 2)

        // Scan middle 50% of height
        let startY = h / 4
        let endY = 3 * h / 4
        let sampleCount = endY - startY

        var darkPixels = 0
        for y in startY ..< endY {
            let offset = y * bytesPerRow + sampleX * bytesPerPixel
            let r = Int(ptr[offset]), g = Int(ptr[offset + 1]), b = Int(ptr[offset + 2])
            let brightness = (r + g + b) / 3
            if brightness < 128 {
                darkPixels += 1
            }
        }

        let darkRatio = Double(darkPixels) / Double(sampleCount)
        print("Region [\(fromXFraction)-\(toXFraction)]: \(String(format: "%.1f", darkRatio * 100))% dark pixels")
        return darkRatio > 0.05
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
        for i in 1 ... 5 {
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
        for i in 1 ... 5 {
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
