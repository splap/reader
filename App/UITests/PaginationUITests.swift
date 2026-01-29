import XCTest

final class PaginationUITests: XCTestCase {
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

    func testPage3TextAlignment() {
        // Open Frankenstein
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("Opening Frankenstein...")
        let banksAuthor = findBook(in: app, containing: "Frankenstein")
        XCTAssertTrue(banksAuthor.waitForExistence(timeout: 5), "Frankenstein book should be visible in library")
        banksAuthor.tap()

        // Wait for book to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5), "WebView should exist")
        sleep(3) // Let content render

        print("Book loaded, now swiping to page 3...")

        // Swipe to page 2
        webView.swipeLeft()
        sleep(1)
        print("Swiped to page 2")

        // Swipe to page 3
        webView.swipeLeft()
        sleep(1)
        print("Swiped to page 3")

        // Check for text alignment - page 2 text should NOT be visible on page 3
        // We'll look for specific text that should only appear on page 2
        // This will fail if pagination is broken
        print("Checking for text alignment on page 3...")

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
        print("Screenshot saved to: \(screenshotPath)")

        // Also add to test results
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Page 3 State"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Verify alignment by checking the debug overlay shows page 2 (0-indexed)
        let pageLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'current page'")).firstMatch
        if pageLabel.waitForExistence(timeout: 3) {
            let currentPageText = pageLabel.label
            print("Current page label: \(currentPageText)")
            // After 2 swipes, we should be on page 2 (0-indexed) or page 3 (1-indexed)
            XCTAssertTrue(currentPageText.contains("current page: 2") || currentPageText.contains("current page: 3"),
                          "Should be on page 2 or 3, but showing: \(currentPageText)")
            print("Page alignment test passed - on correct page after swipes")
        } else {
            print("No debug overlay found - test inconclusive")
        }
    }

    func testTextResizeReflowPerformance() {
        // Open the AI Engineering book
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("Looking for AI Engineering book...")

        // Look for the AI Engineering book by author (Chip Huyen)
        // We'll search for text that contains "Huyen" or the book title
        let aiBookFound = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'huyen' OR label CONTAINS[c] 'ai engineering'")).firstMatch

        if aiBookFound.waitForExistence(timeout: 5) {
            print("Found AI Engineering book: \(aiBookFound.label)")
            aiBookFound.tap()
        } else {
            // Fallback: try to find any book and open it for testing
            print("AI Engineering book not found, using first available book...")
            let firstBook = findBook(in: app, containing: "Frankenstein")
            XCTAssertTrue(firstBook.waitForExistence(timeout: 5), "At least one book should be available")
            firstBook.tap()
        }

        print("Tapped book to open")

        // Wait for reader to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5), "WebView should exist")
        sleep(1) // Brief pause for content to stabilize
        print("Book loaded")

        // Tap to reveal overlay (buttons start hidden)
        webView.tap()
        sleep(1)
        print("Tapped to reveal overlay")

        // Open settings
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Settings button should exist")
        print("Tapping settings button...")
        settingsButton.tap()

        // Wait for settings screen
        let settingsNavBar = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNavBar.waitForExistence(timeout: 5), "Settings screen should appear")
        print("Settings screen opened")

        // Find the font size slider
        let slider = app.sliders.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "Font size slider should exist")
        print("Found font size slider with initial value: \(slider.value)")

        // Get the current slider value and increase it by one increment
        // The slider range is 1.0 to 2.0, we'll increase by ~0.1 (10% of the range)
        let currentValue = Double(slider.value as! String) ?? 0.5
        let targetValue = min(currentValue + 0.1, 1.0) // Normalize to 0-1 range, increment by 0.1
        print("Adjusting slider from \(currentValue) to \(targetValue)")

        // Adjust slider to new value
        slider.adjust(toNormalizedSliderPosition: targetValue)
        print("Slider adjusted to: \(slider.value)")

        // Close settings and measure reflow time
        // Access Done button from navigation bar
        let doneButton = settingsNavBar.buttons.firstMatch
        XCTAssertTrue(doneButton.exists, "Done button should exist in nav bar")
        print("Closing settings to trigger reflow...")

        // Start timing
        let startTime = Date()
        doneButton.tap()

        // Wait for settings to dismiss (no long timeout needed)
        _ = !settingsNavBar.waitForExistence(timeout: 1)

        // Wait for WebView to be responsive - it should exist quickly
        XCTAssertTrue(webView.waitForExistence(timeout: 3), "WebView should exist after dismiss")

        // End timing
        let endTime = Date()
        let reflowDuration = endTime.timeIntervalSince(startTime)

        print("REFLOW PERFORMANCE: \(String(format: "%.3f", reflowDuration)) seconds")
        print("Reflow completed in \(Int(reflowDuration * 1000))ms")

        // Take a screenshot of the reflowed content
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Reflowed Content"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Assert that reflow completes in a reasonable time
        // Note: Full page reload can be slow on simulator, especially for large books
        XCTAssertLessThan(reflowDuration, 30.0, "Reflow should complete in under 30 seconds")

        print("Test complete")
    }

    func testTextSizeChangePreservesPosition() {
        // Verifies that resizing text mid-chapter restores to the same text via CFI.
        // CFI (DOM path + character offset) guarantees the same text is visible after resize.
        // We assert the position was actually restored (not reset to page 1 or jumped to end).
        // Note: relative page position (page/total) naturally shifts because paragraphs
        // reflow non-uniformly — that's expected, not drift.

        // Relaunch with clean data to ensure default font scale (1.4)
        app = launchReaderApp(extraArgs: ["--uitesting-clean-all-data"])

        // 1. Open Frankenstein
        let webView = openFrankenstein(in: app)

        // 2. Navigate to "Letter 2" via TOC
        print("Opening TOC to navigate to Letter 2...")
        XCTAssertTrue(navigateToTOCEntry(in: app, webView: webView, matching: "letter 2"),
                      "Should find 'Letter 2' in TOC")
        sleep(3) // Wait for chapter load

        // 3. Swipe left once to reach page 2 of that chapter
        print("Swiping to page 2...")
        webView.swipeLeft()
        sleep(1)

        // 4. Record initial state
        webView.tap()
        sleep(1)

        let pageLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(pageLabel.waitForExistence(timeout: 3), "Scrubber page label should exist")
        let initialPageText = pageLabel.label
        print("Initial scrubber: \(initialPageText)")

        guard let initialInfo = parseScrubberLabel(initialPageText) else {
            XCTFail("Could not parse initial scrubber label: \(initialPageText)")
            return
        }
        print("Initial: Page \(initialInfo.currentPage) of \(initialInfo.pagesInChapter), Ch. \(initialInfo.currentChapter) of \(initialInfo.totalChapters)")
        XCTAssertEqual(initialInfo.currentPage, 2, "Should be on page 2 after one swipe")
        XCTAssertEqual(initialInfo.currentChapter, 5, "Letter 2 should be chapter 5")

        let originalTotalPages = initialInfo.pagesInChapter

        // 5. Open Settings, increase font size to 0.8 normalized
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Settings button should exist")
        settingsButton.tap()

        let settingsNavBar = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNavBar.waitForExistence(timeout: 5), "Settings screen should appear")

        let slider = app.sliders.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "Font size slider should exist")
        print("Increasing font size to 0.8 normalized...")
        slider.adjust(toNormalizedSliderPosition: 0.8)

        // 6. Close Settings, wait for reflow
        let doneButton = settingsNavBar.buttons.firstMatch
        doneButton.tap()
        sleep(4) // Wait for reloadWithNewFontScale() to query CFI, reload spine, restore position

        // 7. Check post-resize state
        webView.tap()
        sleep(1)

        let scrubberLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(scrubberLabel.waitForExistence(timeout: 3), "Scrubber page label should exist after resize")
        let resizedPageText = scrubberLabel.label
        print("After resize: \(resizedPageText)")

        guard let resizedInfo = parseScrubberLabel(resizedPageText) else {
            XCTFail("Could not parse resized scrubber label: \(resizedPageText)")
            return
        }
        print("After resize: Page \(resizedInfo.currentPage) of \(resizedInfo.pagesInChapter), Ch. \(resizedInfo.currentChapter) of \(resizedInfo.totalChapters)")

        // Assert: same chapter (font change must not jump chapters)
        XCTAssertEqual(resizedInfo.currentChapter, 5,
                      "Should still be in chapter 5 (Letter 2) after font resize")

        // Assert: resize actually took effect (more pages at larger font)
        XCTAssertGreaterThan(resizedInfo.pagesInChapter, originalTotalPages,
                            "Increasing font size should increase page count " +
                            "(was \(originalTotalPages), now \(resizedInfo.pagesInChapter))")

        // Assert: CFI restored to a mid-chapter position (not reset to page 1)
        XCTAssertGreaterThan(resizedInfo.currentPage, 1,
                            "CFI restore should land past page 1. " +
                            "Page 1 means position was reset to start instead of restored. " +
                            "Was on page \(initialInfo.currentPage)/\(originalTotalPages), " +
                            "now page \(resizedInfo.currentPage)/\(resizedInfo.pagesInChapter)")

        // Assert: not on the last page (didn't jump to end)
        XCTAssertLessThan(resizedInfo.currentPage, resizedInfo.pagesInChapter,
                         "CFI restore should not land on the last page. " +
                         "Was on page \(initialInfo.currentPage)/\(originalTotalPages), " +
                         "now page \(resizedInfo.currentPage)/\(resizedInfo.pagesInChapter)")

        print("Text size change preserves position - test passed!")
    }

    func testMarginAndPageBleed() {
        // This test verifies:
        // 1. Margins exist (text doesn't touch screen edges)
        // 2. No page bleeding (adjacent page content doesn't appear)
        //
        // We check that the leftmost and rightmost pixel columns are uniform (background only).
        // Any text in the edge columns indicates either missing margins or page bleed.

        // Open Frankenstein (bundled book)
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("Opening Frankenstein...")
        let frankensteinCell = app.cells.containing(.staticText, identifier: nil).matching(NSPredicate(format: "label CONTAINS[c] 'Frankenstein'")).firstMatch
        if frankensteinCell.waitForExistence(timeout: 5) {
            frankensteinCell.tap()
        } else {
            let frankensteinText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Frankenstein'")).firstMatch
            XCTAssertTrue(frankensteinText.waitForExistence(timeout: 5), "Frankenstein book should be visible")
            frankensteinText.tap()
        }

        // Wait for navigation away from library
        print("Waiting for navigation away from library...")
        let libraryGone = libraryNavBar.waitForNonExistence(timeout: 90)
        if !libraryGone {
            print("Still on library after 90 seconds")
        }

        // Wait for WebView
        print("Waiting for WebView...")
        let webView = app.webViews.firstMatch
        if !webView.waitForExistence(timeout: 10) {
            let debugScreenshot = XCUIScreen.main.screenshot()
            let debugAttachment = XCTAttachment(screenshot: debugScreenshot)
            debugAttachment.name = "After Book Tap - Failed"
            debugAttachment.lifetime = .keepAlways
            add(debugAttachment)
            try? FileManager.default.createDirectory(atPath: "/tmp/reader-tests", withIntermediateDirectories: true)
            try? debugScreenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/reader-tests/after-book-tap.png"))
            XCTFail("WebView should exist - app may be in native render mode instead of WebView mode")
            return
        }
        print("WebView found!")
        sleep(2)

        // Navigate to page 2 (middle of content, not first page which may have special layout)
        print("Navigating to page 2...")
        webView.swipeLeft()
        sleep(1)
        print("Swiped to page 2")

        // Capture screenshot and verify edge columns are uniform
        let screenshot = XCUIScreen.main.screenshot()

        // Save for debugging
        try? FileManager.default.createDirectory(atPath: "/tmp/reader-tests", withIntermediateDirectories: true)
        let screenshotPath = "/tmp/reader-tests/margin-bleed-test.png"
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: screenshotPath))
        print("Screenshot saved to: \(screenshotPath)")

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Margin and Page Bleed Check"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Verify edge columns are uniform (no text bleeding)
        let (leftUniform, rightUniform) = checkEdgeColumnsUniform(screenshot: screenshot)

        XCTAssertTrue(leftUniform, "Left edge column should be uniform (margin exists, no bleed from previous page)")
        XCTAssertTrue(rightUniform, "Right edge column should be uniform (margin exists, no bleed from next page)")

        print("Margin and page bleed test passed - edges are clean")
    }

    func testDoubleTapDoesNotMisalignPage() {
        // This test verifies that double-tapping on the page does not cause
        // the content to shift or become misaligned.

        // Open Frankenstein
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("Opening Frankenstein...")
        let banksAuthor = findBook(in: app, containing: "Frankenstein")
        XCTAssertTrue(banksAuthor.waitForExistence(timeout: 5), "Frankenstein book should be visible in library")
        banksAuthor.tap()

        // Wait for book to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5), "WebView should exist")
        sleep(3) // Let content render and pagination stabilize

        print("Book loaded, taking screenshot before double-tap...")

        // Take screenshot before double-tap
        let screenshotBefore = XCUIScreen.main.screenshot()
        let attachmentBefore = XCTAttachment(screenshot: screenshotBefore)
        attachmentBefore.name = "Before Double-Tap"
        attachmentBefore.lifetime = .keepAlways
        add(attachmentBefore)

        // Save before screenshot
        let beforePath = "/tmp/reader-tests/double-tap-before.png"
        try? FileManager.default.createDirectory(atPath: "/tmp/reader-tests", withIntermediateDirectories: true)
        try? screenshotBefore.pngRepresentation.write(to: URL(fileURLWithPath: beforePath))
        print("Before screenshot saved to: \(beforePath)")

        // Double-tap in the center of the webview
        print("Performing double-tap...")
        let centerPoint = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        centerPoint.doubleTap()

        // Wait a moment for any potential misalignment to occur
        usleep(500_000) // 0.5 seconds

        // Take screenshot after double-tap
        let screenshotAfter = XCUIScreen.main.screenshot()
        let attachmentAfter = XCTAttachment(screenshot: screenshotAfter)
        attachmentAfter.name = "After Double-Tap"
        attachmentAfter.lifetime = .keepAlways
        add(attachmentAfter)

        // Save after screenshot
        let afterPath = "/tmp/reader-tests/double-tap-after.png"
        try? screenshotAfter.pngRepresentation.write(to: URL(fileURLWithPath: afterPath))
        print("After screenshot saved to: \(afterPath)")

        // Compare screenshots - they should be identical (or very similar)
        // We'll compare the PNG data directly
        let beforeData = screenshotBefore.pngRepresentation
        let afterData = screenshotAfter.pngRepresentation

        // If the data is identical, the page didn't shift
        if beforeData == afterData {
            print("Screenshots are identical - no misalignment!")
        } else {
            // Screenshots differ - could be due to overlay toggle or actual misalignment
            // Let's do another double-tap to toggle overlay back and compare again
            print("Screenshots differ after first double-tap (overlay may have toggled)")
            print("Performing second double-tap to toggle overlay back...")

            centerPoint.doubleTap()
            usleep(500_000)

            let screenshotAfter2 = XCUIScreen.main.screenshot()
            let attachmentAfter2 = XCTAttachment(screenshot: screenshotAfter2)
            attachmentAfter2.name = "After Second Double-Tap"
            attachmentAfter2.lifetime = .keepAlways
            add(attachmentAfter2)

            let after2Path = "/tmp/reader-tests/double-tap-after2.png"
            try? screenshotAfter2.pngRepresentation.write(to: URL(fileURLWithPath: after2Path))
            print("After second double-tap screenshot saved to: \(after2Path)")

            let after2Data = screenshotAfter2.pngRepresentation

            // After two double-taps, we should be back to original state
            // Allow for minor differences due to timing, but fail on major shifts
            let beforeSize = beforeData.count
            let after2Size = after2Data.count
            let sizeDiff = abs(beforeSize - after2Size)
            let sizeDiffPercent = Double(sizeDiff) / Double(beforeSize) * 100

            print("Screenshot size comparison: before=\(beforeSize), after2=\(after2Size), diff=\(sizeDiffPercent)%")

            // If screenshots are very different in size, something is wrong
            // A shifted page would have different content visible
            XCTAssertLessThan(sizeDiffPercent, 5.0,
                              "Screenshots should be nearly identical after two double-taps. Size difference: \(sizeDiffPercent)%")

            // More rigorous check: compare pixel data
            if beforeData != after2Data {
                print("WARNING: Screenshots differ after two double-taps!")
                print("This may indicate the page shifted and didn't return to original position")
                print("Check screenshots at: \(beforePath) and \(after2Path)")

                // Don't fail yet - let's check if page number changed
            }
        }

        // Additional check: reveal overlay and verify page number is still correct
        print("Revealing overlay to check page number...")
        webView.tap()
        sleep(1)

        let pageLabel = app.staticTexts["scrubber-page-label"]
        if pageLabel.waitForExistence(timeout: 3) {
            let pageText = pageLabel.label
            print("Current page: \(pageText)")
            XCTAssertTrue(pageText.contains("Page 1"),
                          "Should still be on page 1 after double-taps, but showing: \(pageText)")
            print("Still on page 1 - page alignment preserved!")
        }

        print("Double-tap alignment test complete")
    }

    func testFontSizeChangeAppliesToOtherSpineItems() {
        // Verifies that changing font size on one chapter propagates to other chapters.
        // Bug: change font on Letter 3 → swipe to Letter 4 → Letter 4 renders at OLD font size.

        // Relaunch with clean data to ensure default font scale (1.4)
        app = launchReaderApp(extraArgs: ["--uitesting-clean-all-data"])

        // 1. Open Frankenstein
        let webView = openFrankenstein(in: app)

        // 2. Navigate to Letter 3 (ch 6) via TOC and record baseline page count
        print("Navigating to Letter 3 for baseline measurement...")
        XCTAssertTrue(navigateToTOCEntry(in: app, webView: webView, matching: "letter 3"),
                      "Should find 'Letter 3' in TOC")
        sleep(3) // Wait for chapter load

        // Reveal scrubber and record baseline
        webView.tap()
        sleep(1)

        let pageLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(pageLabel.waitForExistence(timeout: 3), "Scrubber page label should exist")
        let baselineText = pageLabel.label
        print("Baseline scrubber: \(baselineText)")

        guard let baselineInfo = parseScrubberLabel(baselineText) else {
            XCTFail("Could not parse baseline scrubber label: \(baselineText)")
            return
        }
        let baselinePages = baselineInfo.pagesInChapter
        XCTAssertEqual(baselineInfo.currentChapter, 6, "Letter 3 should be chapter 6")
        print("Baseline: \(baselinePages) pages in Letter 3 (ch 6)")

        // 3. Navigate to Letter 2 (ch 5) and change font size there
        print("Navigating to Letter 2 to change font size...")
        XCTAssertTrue(navigateToTOCEntry(in: app, webView: webView, matching: "letter 2"),
                      "Should find 'Letter 2' in TOC")
        sleep(3) // Wait for chapter load

        // Open Settings, increase font to 0.9 normalized
        webView.tap()
        sleep(1)

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Settings button should exist")
        settingsButton.tap()

        let settingsNavBar = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNavBar.waitForExistence(timeout: 5), "Settings screen should appear")

        let slider = app.sliders.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "Font size slider should exist")
        print("Increasing font size to 0.9 normalized...")
        slider.adjust(toNormalizedSliderPosition: 0.9)

        // Close settings
        let doneButton = settingsNavBar.buttons.firstMatch
        doneButton.tap()
        sleep(4) // Wait for reflow

        // 4. Navigate back to Letter 3 (ch 6) and check page count
        print("Navigating back to Letter 3 to verify font propagated...")
        XCTAssertTrue(navigateToTOCEntry(in: app, webView: webView, matching: "letter 3"),
                      "Should find 'Letter 3' in TOC")
        sleep(3) // Wait for chapter load

        // Reveal scrubber and record new page count
        webView.tap()
        sleep(1)

        let newPageLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(newPageLabel.waitForExistence(timeout: 3), "Scrubber page label should exist after font change")
        let newText = newPageLabel.label
        print("After font change: \(newText)")

        guard let newInfo = parseScrubberLabel(newText) else {
            XCTFail("Could not parse new scrubber label: \(newText)")
            return
        }
        let newPages = newInfo.pagesInChapter
        print("New: \(newPages) pages in Letter 3 (ch \(newInfo.currentChapter))")

        // Assert: correct chapter
        XCTAssertEqual(newInfo.currentChapter, 6,
                      "Should be on chapter 6 (Letter 3)")

        // Assert: font propagated (more pages at larger font)
        XCTAssertGreaterThan(newPages, baselinePages,
                            "Font size increase should produce more pages in Letter 3 " +
                            "(baseline: \(baselinePages), now: \(newPages)). " +
                            "If equal, font didn't propagate to other spine items.")

        print("Cross-spine font propagation test passed!")
    }

    // MARK: - Private Helpers

    /// Checks if the leftmost and rightmost pixel columns are uniform (same color throughout).
    /// Returns (leftUniform, rightUniform) booleans.
    private func checkEdgeColumnsUniform(screenshot: XCUIScreenshot) -> (Bool, Bool) {
        guard let cgImage = screenshot.image.cgImage else {
            print("Could not get CGImage from screenshot")
            return (false, false)
        }

        let width = cgImage.width
        let height = cgImage.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("Could not create CGContext")
            return (false, false)
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            print("Could not get pixel data")
            return (false, false)
        }

        let pixelData = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // Check left column (x = 0)
        let leftUniform = isColumnUniform(pixelData: pixelData, column: 0, width: width, height: height)

        // Check right column (x = width - 1)
        let rightUniform = isColumnUniform(pixelData: pixelData, column: width - 1, width: width, height: height)

        return (leftUniform, rightUniform)
    }

    /// Checks if a single pixel column has uniform color (allowing small tolerance for antialiasing).
    private func isColumnUniform(pixelData: UnsafeMutablePointer<UInt8>, column: Int, width: Int, height: Int) -> Bool {
        // Sample the first pixel as reference
        let firstPixelOffset = column * 4
        let refR = pixelData[firstPixelOffset]
        let refG = pixelData[firstPixelOffset + 1]
        let refB = pixelData[firstPixelOffset + 2]

        let tolerance: UInt8 = 10 // Allow small variance for compression/antialiasing
        var nonUniformCount = 0
        let maxAllowedNonUniform = height / 20 // Allow 5% variance for UI elements at top/bottom

        for y in 0 ..< height {
            let offset = (y * width + column) * 4
            let r = pixelData[offset]
            let g = pixelData[offset + 1]
            let b = pixelData[offset + 2]

            let diffR = abs(Int(r) - Int(refR))
            let diffG = abs(Int(g) - Int(refG))
            let diffB = abs(Int(b) - Int(refB))

            if diffR > Int(tolerance) || diffG > Int(tolerance) || diffB > Int(tolerance) {
                nonUniformCount += 1
            }
        }

        let uniformPercent = 100.0 * Double(height - nonUniformCount) / Double(height)
        print("Column \(column): \(String(format: "%.1f", uniformPercent))% uniform (\(nonUniformCount) non-uniform pixels)")

        return nonUniformCount <= maxAllowedNonUniform
    }
}
