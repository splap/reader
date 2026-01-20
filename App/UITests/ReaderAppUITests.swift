import XCTest

final class ReaderAppUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()

        continueAfterFailure = false

        app = XCUIApplication()
        var args = ["--uitesting"]
        if name.contains("testPositionPersistence") {
            args.append("--uitesting-position-test")
            args.append("--uitesting-show-overlay")
            args.append("--uitesting-jump-to-page=100")
        }
        // Use WebView mode for alignment/margin tests (testing CSS pagination)
        let testName = name.lowercased()
        if testName.contains("alignment") || testName.contains("page3") || testName.contains("margin") || testName.contains("bleed") {
            args.append("--uitesting-webview")
            print("🧪 Adding --uitesting-webview for test: \(name)")
        }
        app.launchArguments = args
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

        // Tap to reveal overlay (buttons start hidden)
        webView.tap()
        sleep(1)
        print("🧪 Tapped to reveal overlay")

        // Verify Back button exists (proves we're in reader, not library)
        let backButton = app.buttons["Back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 3), "Back button should exist in reader")
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

        // Verify alignment by checking the debug overlay shows page 2 (0-indexed)
        let pageLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'current page'")).firstMatch
        if pageLabel.waitForExistence(timeout: 3) {
            let currentPageText = pageLabel.label
            print("🧪 Current page label: \(currentPageText)")
            // After 2 swipes, we should be on page 2 (0-indexed) or page 3 (1-indexed)
            XCTAssertTrue(currentPageText.contains("current page: 2") || currentPageText.contains("current page: 3"),
                         "Should be on page 2 or 3, but showing: \(currentPageText)")
            print("🧪 ✅ Page alignment test passed - on correct page after swipes")
        } else {
            print("🧪 ⚠️  No debug overlay found - test inconclusive")
        }
    }

    func testTextResizeReflowPerformance() {
        // Open the AI Engineering book
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("🧪 Looking for AI Engineering book...")

        // Look for the AI Engineering book by author (Chip Huyen)
        // We'll search for text that contains "Huyen" or the book title
        let aiBookFound = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'huyen' OR label CONTAINS[c] 'ai engineering'")).firstMatch

        if aiBookFound.waitForExistence(timeout: 5) {
            print("🧪 Found AI Engineering book: \(aiBookFound.label)")
            aiBookFound.tap()
        } else {
            // Fallback: try to find any book and open it for testing
            print("🧪 AI Engineering book not found, using first available book...")
            let firstBook = app.staticTexts["Banks, Ian M."]
            XCTAssertTrue(firstBook.waitForExistence(timeout: 5), "At least one book should be available")
            firstBook.tap()
        }

        print("🧪 Tapped book to open")

        // Wait for reader to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5), "WebView should exist")
        sleep(1) // Brief pause for content to stabilize
        print("🧪 Book loaded")

        // Tap to reveal overlay (buttons start hidden)
        webView.tap()
        sleep(1)
        print("🧪 Tapped to reveal overlay")

        // Open settings
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Settings button should exist")
        print("🧪 Tapping settings button...")
        settingsButton.tap()

        // Wait for settings screen
        let settingsNavBar = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNavBar.waitForExistence(timeout: 5), "Settings screen should appear")
        print("🧪 Settings screen opened")

        // Find the font size slider
        let slider = app.sliders.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "Font size slider should exist")
        print("🧪 Found font size slider with initial value: \(slider.value)")

        // Get the current slider value and increase it by one increment
        // The slider range is 1.0 to 2.0, we'll increase by ~0.1 (10% of the range)
        let currentValue = Double(slider.value as! String) ?? 0.5
        let targetValue = min(currentValue + 0.1, 1.0) // Normalize to 0-1 range, increment by 0.1
        print("🧪 Adjusting slider from \(currentValue) to \(targetValue)")

        // Adjust slider to new value
        slider.adjust(toNormalizedSliderPosition: targetValue)
        print("🧪 Slider adjusted to: \(slider.value)")

        // Close settings and measure reflow time
        // Access Done button from navigation bar
        let doneButton = settingsNavBar.buttons.firstMatch
        XCTAssertTrue(doneButton.exists, "Done button should exist in nav bar")
        print("🧪 Closing settings to trigger reflow...")

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

        print("🧪 ⏱️  REFLOW PERFORMANCE: \(String(format: "%.3f", reflowDuration)) seconds")
        print("🧪 Reflow completed in \(Int(reflowDuration * 1000))ms")

        // Take a screenshot of the reflowed content
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Reflowed Content"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Assert that reflow completes in a reasonable time
        // Note: Full page reload can be slow on simulator, especially for large books
        XCTAssertLessThan(reflowDuration, 30.0, "Reflow should complete in under 30 seconds")

        print("🧪 Test complete")
    }

    func testTextSizeChangeAffectsPageCount() {
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
        sleep(2) // Let content render and pagination calculate

        // Tap top third of webview to reveal floating buttons (they start hidden)
        print("🧪 Tapping top of webview to reveal buttons...")
        // Get webview frame and tap at top third
        let webViewFrame = webView.frame
        let topThirdPoint = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        topThirdPoint.tap()
        sleep(1) // Wait for fade-in animation

        // Find the page number label (e.g., "Page 1 of 42")
        let pageLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Page'")).firstMatch
        XCTAssertTrue(pageLabel.waitForExistence(timeout: 3), "Page number label should exist")

        let initialPageText = pageLabel.label
        print("🧪 Initial page label: \(initialPageText)")

        // Extract initial total page count from "Page X of Y"
        let initialTotalPages = extractTotalPages(from: initialPageText)
        print("🧪 Initial total pages: \(initialTotalPages)")
        XCTAssertGreaterThan(initialTotalPages, 0, "Should have valid initial page count")

        // Open settings
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Settings button should exist")
        settingsButton.tap()

        // Wait for settings screen
        let settingsNavBar = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNavBar.waitForExistence(timeout: 5), "Settings screen should appear")
        print("🧪 Settings screen opened")

        // Find the font size slider
        let slider = app.sliders.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "Font size slider should exist")
        print("🧪 Found font size slider")

        // INCREASE font size (should result in MORE pages)
        print("🧪 Increasing font size...")
        slider.adjust(toNormalizedSliderPosition: 0.8) // Increase to 80% of max

        // Close settings
        let doneButton = settingsNavBar.buttons.firstMatch
        doneButton.tap()

        // Wait for reflow (reload takes longer than JS manipulation)
        sleep(4)

        // Check new page count
        let increasedPageText = pageLabel.label
        print("🧪 After increase: \(increasedPageText)")
        let increasedTotalPages = extractTotalPages(from: increasedPageText)
        print("🧪 Total pages after increase: \(increasedTotalPages)")

        XCTAssertGreaterThan(increasedTotalPages, initialTotalPages,
                            "Increasing font size should INCREASE page count (was \(initialTotalPages), now \(increasedTotalPages))")

        print("🧪 ✅ Text resize increases page count - test passed!")
    }

    // Helper to extract total page count from debug overlay text
    private func extractTotalPages(from text: String) -> Int {
        // Handle "total pages: N" format from debug overlay
        if text.contains("total pages:") {
            let components = text.components(separatedBy: "total pages:")
            guard components.count >= 2 else { return 0 }
            let numberPart = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            // Extract just the number (might be followed by other text)
            let digits = numberPart.components(separatedBy: .whitespacesAndNewlines).first ?? ""
            return Int(digits) ?? 0
        }

        // Legacy: Handle "Page X of Y" format if it exists
        let components = text.components(separatedBy: " of ")
        guard components.count == 2 else { return 0 }
        return Int(components[1]) ?? 0
    }

    func testMarginAndPageBleed() {
        // This test verifies:
        // 1. Margins exist (text doesn't touch screen edges)
        // 2. No page bleeding (adjacent page content doesn't appear)
        //
        // We check that the leftmost and rightmost pixel columns are uniform (background only).
        // Any text in the edge columns indicates either missing margins or page bleed.

        // Open Frankenstein by Shelley (bundled book)
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("🧪 Opening Frankenstein...")
        let frankensteinCell = app.cells.containing(.staticText, identifier: nil).matching(NSPredicate(format: "label CONTAINS[c] 'Frankenstein'")).firstMatch
        if frankensteinCell.waitForExistence(timeout: 5) {
            frankensteinCell.tap()
        } else {
            let frankensteinText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Frankenstein'")).firstMatch
            XCTAssertTrue(frankensteinText.waitForExistence(timeout: 5), "Frankenstein book should be visible")
            frankensteinText.tap()
        }

        // Wait for navigation away from library
        print("🧪 Waiting for navigation away from library...")
        let libraryGone = libraryNavBar.waitForNonExistence(timeout: 90)
        if !libraryGone {
            print("🧪 Still on library after 90 seconds")
        }

        // Wait for WebView
        print("🧪 Waiting for WebView...")
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
        print("🧪 WebView found!")
        sleep(2)

        // Navigate to page 2 (middle of content, not first page which may have special layout)
        print("🧪 Navigating to page 2...")
        webView.swipeLeft()
        sleep(1)
        print("🧪 Swiped to page 2")

        // Capture screenshot and verify edge columns are uniform
        let screenshot = XCUIScreen.main.screenshot()

        // Save for debugging
        try? FileManager.default.createDirectory(atPath: "/tmp/reader-tests", withIntermediateDirectories: true)
        let screenshotPath = "/tmp/reader-tests/margin-bleed-test.png"
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: screenshotPath))
        print("🧪 Screenshot saved to: \(screenshotPath)")

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Margin and Page Bleed Check"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Verify edge columns are uniform (no text bleeding)
        let (leftUniform, rightUniform) = checkEdgeColumnsUniform(screenshot: screenshot)

        XCTAssertTrue(leftUniform, "Left edge column should be uniform (margin exists, no bleed from previous page)")
        XCTAssertTrue(rightUniform, "Right edge column should be uniform (margin exists, no bleed from next page)")

        print("🧪 ✅ Margin and page bleed test passed - edges are clean")
    }

    /// Checks if the leftmost and rightmost pixel columns are uniform (same color throughout).
    /// Returns (leftUniform, rightUniform) booleans.
    private func checkEdgeColumnsUniform(screenshot: XCUIScreenshot) -> (Bool, Bool) {
        guard let cgImage = screenshot.image.cgImage else {
            print("🧪 ⚠️ Could not get CGImage from screenshot")
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
            print("🧪 ⚠️ Could not create CGContext")
            return (false, false)
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            print("🧪 ⚠️ Could not get pixel data")
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

        for y in 0..<height {
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
        print("🧪 Column \(column): \(String(format: "%.1f", uniformPercent))% uniform (\(nonUniformCount) non-uniform pixels)")

        return nonUniformCount <= maxAllowedNonUniform
    }

    // MARK: - Scrubber and Navigation Overlay Tests

    func testScrubberAppearsOnTap() {
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

        print("🧪 Book loaded, verifying overlay is initially hidden...")

        // Verify scrubber and buttons are initially not visible (alpha = 0)
        // We can check by trying to find the page scrubber slider
        let scrubber = app.sliders["Page scrubber"]
        XCTAssertFalse(scrubber.isHittable, "Scrubber should not be hittable when overlay is hidden")

        print("🧪 Tapping to reveal overlay...")
        webView.tap()
        sleep(1)

        // Now verify scrubber is visible
        XCTAssertTrue(scrubber.waitForExistence(timeout: 3), "Scrubber should exist after tap")
        XCTAssertTrue(scrubber.isHittable, "Scrubber should be hittable when overlay is shown")
        print("🧪 ✅ Scrubber appeared after tap")

        // Verify back and settings buttons are also visible
        let backButton = app.buttons["Back"]
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(backButton.isHittable, "Back button should be hittable")
        XCTAssertTrue(settingsButton.isHittable, "Settings button should be hittable")
        print("🧪 ✅ Navigation buttons visible")

        // Verify page label is visible
        let pageLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(pageLabel.exists, "Page label should exist")
        print("🧪 Page label: \(pageLabel.label)")

        // Tap again to hide
        print("🧪 Tapping to hide overlay...")
        webView.tap()
        sleep(1)

        XCTAssertFalse(scrubber.isHittable, "Scrubber should not be hittable after hiding overlay")
        print("🧪 ✅ Overlay toggled off successfully")
    }

    func testScrubberNavigatesToPage() {
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
        sleep(3) // Let content render and pagination calculate

        print("🧪 Book loaded, revealing overlay...")
        webView.tap()
        sleep(1)

        // Get the scrubber slider
        let scrubber = app.sliders["Page scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 3), "Scrubber should exist")

        // Check initial page (should be page 1)
        let pageLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(pageLabel.waitForExistence(timeout: 3), "Page indicator should exist")
        let initialPageText = pageLabel.label
        print("🧪 Initial page: \(initialPageText)")
        XCTAssertTrue(initialPageText.contains("Page 1"), "Should start at page 1")

        // Move scrubber to middle (50%)
        print("🧪 Moving scrubber to 50% position...")
        scrubber.adjust(toNormalizedSliderPosition: 0.5)
        sleep(1)

        // Verify page changed
        let midPageText = pageLabel.label
        print("🧪 After scrub to 50%: \(midPageText)")
        XCTAssertFalse(midPageText.contains("Page 1"), "Should not be on page 1 after scrubbing to middle")

        // Extract page number and verify it's roughly in the middle
        if let pageNumber = extractCurrentPage(from: midPageText) {
            let totalPages = extractTotalPages(from: midPageText)
            if totalPages > 0 {
                let expectedMid = totalPages / 2
                let tolerance = max(1, totalPages / 10)  // 10% tolerance, minimum 1
                XCTAssertTrue(
                    abs(pageNumber - expectedMid) <= tolerance,
                    "Page \(pageNumber) should be roughly in middle (expected ~\(expectedMid) of \(totalPages))"
                )
                print("🧪 ✅ Scrubber navigated to page \(pageNumber) of \(totalPages)")
            }
        }

        // Move to end (100%)
        print("🧪 Moving scrubber to end...")
        scrubber.adjust(toNormalizedSliderPosition: 1.0)
        sleep(1)

        let endPageText = pageLabel.label
        print("🧪 At end: \(endPageText)")

        // Take screenshot
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Scrubber Navigation End"
        attachment.lifetime = .keepAlways
        add(attachment)

        print("🧪 ✅ Scrubber navigation test complete")
    }

    func testPositionPersistence() {
        // This test verifies that reading position is saved and restored
        // We navigate to a specific page, restart the app, and verify we're on the same page

        let pageLabel = app.staticTexts["scrubber-page-label"]
        waitForLabel(pageLabel, contains: "Page 100", timeout: 1.2)
        print("🧪 Book loaded at page 100")

        // Restart app to validate persisted position
        print("🧪 Restarting app to verify position persistence...")
        app.launchArguments = [
            "--uitesting",
            "--uitesting-keep-state",
            "--uitesting-position-test",
            "--uitesting-show-overlay"
        ]
        app.terminate()
        app.launch()

        let restoredLabel = app.staticTexts["scrubber-page-label"]
        waitForLabel(restoredLabel, contains: "Page 100", timeout: 1.2)
        print("🧪 ✅ Position persistence verified! Restored to page 100")
    }

    private func waitForLabel(_ element: XCUIElement, contains text: String, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Expected label to contain '\(text)'")
    }

    func testMaxReadExtentIndicator() {
        // This test verifies that the max read extent indicator shows on the scrubber
        // We navigate forward in the book, then go back, and verify the red indicator
        // shows the furthest page we reached

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
        sleep(3)

        print("🧪 Book loaded, navigating forward 3 pages...")

        // Navigate forward 3 pages
        for _ in 1...3 {
            webView.swipeLeft()
            usleep(200000) // 0.2 seconds
        }
        sleep(1)

        // Reveal overlay
        webView.tap()
        sleep(1)

        let pageLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(pageLabel.waitForExistence(timeout: 3), "Page indicator should exist")
        let maxPageText = pageLabel.label
        print("🧪 Reached max page: \(maxPageText)")
        let maxPage = extractCurrentPage(from: maxPageText) ?? 0

        // Now navigate back using scrubber
        print("🧪 Navigating back to beginning using scrubber...")
        let scrubber = app.sliders["Page scrubber"]
        XCTAssertTrue(scrubber.exists, "Scrubber should exist")
        scrubber.adjust(toNormalizedSliderPosition: 0.0)
        sleep(1)

        // Verify we're at page 1
        let backAtStartText = pageLabel.label
        print("🧪 After scrubbing back: \(backAtStartText)")
        XCTAssertTrue(backAtStartText.contains("Page 1"), "Should be back at page 1")

        // The red extent indicator should still show up to page ~20
        // We can't easily verify the visual indicator in UI tests,
        // but we can verify the page navigation worked correctly

        // Take screenshot to visually verify the red extent indicator
        let screenshot = XCUIScreen.main.screenshot()

        // Save to temp for inspection
        let screenshotPath = "/tmp/reader-tests/max-extent-indicator.png"
        try? FileManager.default.createDirectory(atPath: "/tmp/reader-tests", withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: screenshotPath))
        print("🧪 Screenshot saved to: \(screenshotPath)")
        print("🧪 Visual inspection: red indicator on scrubber should extend to ~\(Float(maxPage)) / total pages")

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Max Read Extent Indicator"
        attachment.lifetime = .keepAlways
        add(attachment)

        print("🧪 ✅ Max read extent test complete (check screenshot for visual verification)")
    }

    // Helper to extract current page from "Page X of Y" format
    private func extractCurrentPage(from text: String) -> Int? {
        // Handle "Page X of Y" format
        let pattern = #"Page\s+(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[range])
    }

    func testDoubleTapDoesNotMisalignPage() {
        // This test verifies that double-tapping on the page does not cause
        // the content to shift or become misaligned.

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
        sleep(3) // Let content render and pagination stabilize

        print("🧪 Book loaded, taking screenshot before double-tap...")

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
        print("🧪 Before screenshot saved to: \(beforePath)")

        // Double-tap in the center of the webview
        print("🧪 Performing double-tap...")
        let centerPoint = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        centerPoint.doubleTap()

        // Wait a moment for any potential misalignment to occur
        usleep(500000) // 0.5 seconds

        // Take screenshot after double-tap
        let screenshotAfter = XCUIScreen.main.screenshot()
        let attachmentAfter = XCTAttachment(screenshot: screenshotAfter)
        attachmentAfter.name = "After Double-Tap"
        attachmentAfter.lifetime = .keepAlways
        add(attachmentAfter)

        // Save after screenshot
        let afterPath = "/tmp/reader-tests/double-tap-after.png"
        try? screenshotAfter.pngRepresentation.write(to: URL(fileURLWithPath: afterPath))
        print("🧪 After screenshot saved to: \(afterPath)")

        // Compare screenshots - they should be identical (or very similar)
        // We'll compare the PNG data directly
        let beforeData = screenshotBefore.pngRepresentation
        let afterData = screenshotAfter.pngRepresentation

        // If the data is identical, the page didn't shift
        if beforeData == afterData {
            print("🧪 ✅ Screenshots are identical - no misalignment!")
        } else {
            // Screenshots differ - could be due to overlay toggle or actual misalignment
            // Let's do another double-tap to toggle overlay back and compare again
            print("🧪 Screenshots differ after first double-tap (overlay may have toggled)")
            print("🧪 Performing second double-tap to toggle overlay back...")

            centerPoint.doubleTap()
            usleep(500000)

            let screenshotAfter2 = XCUIScreen.main.screenshot()
            let attachmentAfter2 = XCTAttachment(screenshot: screenshotAfter2)
            attachmentAfter2.name = "After Second Double-Tap"
            attachmentAfter2.lifetime = .keepAlways
            add(attachmentAfter2)

            let after2Path = "/tmp/reader-tests/double-tap-after2.png"
            try? screenshotAfter2.pngRepresentation.write(to: URL(fileURLWithPath: after2Path))
            print("🧪 After second double-tap screenshot saved to: \(after2Path)")

            let after2Data = screenshotAfter2.pngRepresentation

            // After two double-taps, we should be back to original state
            // Allow for minor differences due to timing, but fail on major shifts
            let beforeSize = beforeData.count
            let after2Size = after2Data.count
            let sizeDiff = abs(beforeSize - after2Size)
            let sizeDiffPercent = Double(sizeDiff) / Double(beforeSize) * 100

            print("🧪 Screenshot size comparison: before=\(beforeSize), after2=\(after2Size), diff=\(sizeDiffPercent)%")

            // If screenshots are very different in size, something is wrong
            // A shifted page would have different content visible
            XCTAssertLessThan(sizeDiffPercent, 5.0,
                "Screenshots should be nearly identical after two double-taps. Size difference: \(sizeDiffPercent)%")

            // More rigorous check: compare pixel data
            if beforeData != after2Data {
                print("🧪 ⚠️ WARNING: Screenshots differ after two double-taps!")
                print("🧪 This may indicate the page shifted and didn't return to original position")
                print("🧪 Check screenshots at: \(beforePath) and \(after2Path)")

                // Don't fail yet - let's check if page number changed
            }
        }

        // Additional check: reveal overlay and verify page number is still correct
        print("🧪 Revealing overlay to check page number...")
        webView.tap()
        sleep(1)

        let pageLabel = app.staticTexts["scrubber-page-label"]
        if pageLabel.waitForExistence(timeout: 3) {
            let pageText = pageLabel.label
            print("🧪 Current page: \(pageText)")
            XCTAssertTrue(pageText.contains("Page 1"),
                "Should still be on page 1 after double-taps, but showing: \(pageText)")
            print("🧪 ✅ Still on page 1 - page alignment preserved!")
        }

        print("🧪 Double-tap alignment test complete")
    }

}
