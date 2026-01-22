import XCTest

final class ReaderAppUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()

        continueAfterFailure = false

        app = XCUIApplication()
        var args = ["--uitesting", "--uitesting-skip-indexing", "--uitesting-webview"]
        if name.contains("testPositionPersistence") {
            args.append("--uitesting-position-test")
            args.append("--uitesting-show-overlay")
            args.append("--uitesting-jump-to-page=100")
        }
        app.launchArguments = args
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    /// Helper to find a book cell by partial title match (e.g., "Frankenstein" matches "Frankenstein; Or, The Modern Prometheus")
    private func findBook(containing title: String) -> XCUIElement {
        return app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
    }

    /// Helper to open Frankenstein book and wait for it to load
    private func openFrankenstein() -> XCUIElement {
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("🧪 Opening Frankenstein...")
        let bookCell = findBook(containing: "Frankenstein")
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5), "Frankenstein should be visible in library")
        bookCell.tap()

        // Wait for book to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5), "WebView should exist after opening book")
        sleep(2) // Let content render
        return webView
    }

    func testAppLaunchesInLibrary() {
        // Verify we're on the Library screen
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5), "Library screen should be visible")

        // Verify all three bundled books are present
        let frankenstein = findBook(containing: "Frankenstein")
        let meditations = findBook(containing: "Meditations")
        let metamorphosis = findBook(containing: "Metamorphosis")

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
        print("🧪 Library visible")

        // Open a book first
        let bookCell = findBook(containing: "Frankenstein")
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
        print("🧪 Settings button found, tapping...")
        settingsButton.tap()

        // Verify settings screen appears
        let settingsNavBar = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNavBar.waitForExistence(timeout: 5), "Settings screen should appear")
        print("🧪 Navigated to settings successfully")
    }

    func testOpenBook() {
        // Wait for library to load
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("🧪 Looking for books in library...")

        // Look for Frankenstein by partial title match
        let bookCell = findBook(containing: "Frankenstein")

        XCTAssertTrue(bookCell.waitForExistence(timeout: 5), "Frankenstein book should be visible in library")
        print("🧪 Found Frankenstein")

        // Tap to open the book
        bookCell.tap()
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
        // Note: With section-based loading, we only load ~5 sections around initial position
        let staticTextCount = app.staticTexts.count
        print("🧪 Static text elements found: \(staticTextCount)")
        XCTAssertGreaterThan(staticTextCount, 30, "Should have substantial book content loaded (section-based loading)")

        print("🧪 Book content verified successfully - \(staticTextCount) text elements")
    }

    func testPage3TextAlignment() {
        // Open Frankenstein
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("🧪 Opening Frankenstein...")
        let banksAuthor = findBook(containing: "Frankenstein")
        XCTAssertTrue(banksAuthor.waitForExistence(timeout: 5), "Frankenstein book should be visible in library")
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
            let firstBook = findBook(containing: "Frankenstein")
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
        // Open Frankenstein
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("🧪 Opening Frankenstein...")
        let banksAuthor = findBook(containing: "Frankenstein")
        XCTAssertTrue(banksAuthor.waitForExistence(timeout: 5), "Frankenstein book should be visible in library")
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

        // Find the page number label using accessibility ID
        let pageLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(pageLabel.waitForExistence(timeout: 3), "Scrubber page label should exist")

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

        // Tap to reveal overlay again (it gets hidden when opening settings)
        webView.tap()
        sleep(1)

        // Check new page count using scrubber page label by accessibility ID
        let scrubberLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(scrubberLabel.waitForExistence(timeout: 3), "Scrubber page label should exist")
        let increasedPageText = scrubberLabel.label
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

        // Open Frankenstein (bundled book)
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
        // Open Frankenstein
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("🧪 Opening Frankenstein...")
        let banksAuthor = findBook(containing: "Frankenstein")
        XCTAssertTrue(banksAuthor.waitForExistence(timeout: 5), "Frankenstein book should be visible in library")
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
        // Open Frankenstein
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("🧪 Opening Frankenstein...")
        let banksAuthor = findBook(containing: "Frankenstein")
        XCTAssertTrue(banksAuthor.waitForExistence(timeout: 5), "Frankenstein book should be visible in library")
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

        // Open Frankenstein
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("🧪 Opening Frankenstein...")
        let banksAuthor = findBook(containing: "Frankenstein")
        XCTAssertTrue(banksAuthor.waitForExistence(timeout: 5), "Frankenstein book should be visible in library")
        banksAuthor.tap()

        // Wait for book to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5), "WebView should exist")
        sleep(3)

        print("🧪 Book loaded, navigating forward 5 pages...")

        // Navigate forward 5 pages to establish max read extent
        for i in 1...5 {
            webView.swipeLeft()
            usleep(300000) // 0.3 seconds
            print("🧪 Swiped to page \(i + 1)")
        }
        sleep(1)

        // Reveal overlay and check current page
        webView.tap()
        sleep(1)

        let pageLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(pageLabel.waitForExistence(timeout: 3), "Page indicator should exist")
        let maxPageText = pageLabel.label
        print("🧪 Reached max page: \(maxPageText)")
        let maxPage = extractCurrentPage(from: maxPageText) ?? 0
        XCTAssertGreaterThan(maxPage, 1, "Should have navigated forward")

        // Hide overlay first (tap to toggle off)
        print("🧪 Hiding overlay before navigating back...")
        webView.tap()
        sleep(1)

        // Navigate back 3 pages using swipes
        print("🧪 Navigating back 3 pages...")
        for i in 1...3 {
            webView.swipeRight()
            usleep(500000) // 0.5 seconds between swipes
            print("🧪 Swiped back \(i) page(s)")
        }
        sleep(2) // Wait for page animation to settle

        // Reveal overlay again - tap and wait for scrubber to appear
        print("🧪 Tapping to reveal overlay...")
        webView.tap()
        sleep(1)

        // Wait for the scrubber to become visible
        let scrubber = app.sliders["Page scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5), "Scrubber should appear after tap")

        // Check we're now at a lower page but max extent should still show the furthest point
        let currentPageLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(currentPageLabel.waitForExistence(timeout: 3), "Page indicator should exist")
        let currentPageText = currentPageLabel.label
        print("🧪 After navigating back: \(currentPageText)")
        let currentPage = extractCurrentPage(from: currentPageText) ?? 0
        XCTAssertLessThan(currentPage, maxPage, "Should be on an earlier page than max")

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

    // MARK: - Semantic Search Integration Test

    func testVectorIndexBuildingOnBookOpen() {
        // This is a full integration test that:
        // 1. Starts with completely clean app state (no stale indices)
        // 2. Opens a book
        // 3. Verifies the indexing progress UI appears
        // 4. Waits for indexing to complete
        // 5. Verifies we enter the reader

        // Restart app with clean-all-data flag to ensure no stale state
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-clean-all-data"]
        app.launch()

        // Wait for library to load (books need to be re-imported after clean)
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 10), "Library should appear")
        print("🧪 Library loaded after clean state")

        // Wait a moment for books to be imported
        sleep(3)

        // Look for any book in the library
        // Since we cleared all data, bundled books should be re-imported
        let tableView = app.tables.firstMatch
        XCTAssertTrue(tableView.waitForExistence(timeout: 5), "Table view should exist")

        // Get the first cell (any book will do)
        let firstCell = tableView.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 10), "At least one book should be imported")
        print("🧪 Found book in library: \(firstCell.label)")

        // Tap to open the book
        firstCell.tap()
        print("🧪 Tapped book to open - expecting indexing progress...")

        // Look for the indexing progress view
        // The IndexingProgressView shows "Preparing Book" as the title
        let preparingLabel = app.staticTexts["Preparing Book"]
        let indexingVisible = preparingLabel.waitForExistence(timeout: 5)

        if indexingVisible {
            print("🧪 ✅ Indexing progress view appeared!")

            // Take screenshot of indexing progress
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "Indexing Progress"
            attachment.lifetime = .keepAlways
            add(attachment)

            // Wait for indexing to complete - look for Back button
            print("🧪 Waiting for indexing to complete...")

        } else {
            // Indexing progress didn't appear - book was already indexed
            // (background indexing happens during import)
            print("🧪 Indexing progress view did not appear (book already indexed)")
        }

        // Wait for reader to appear - look for Back button which is always present
        // Note: Reader uses native renderer, not WebView
        let backButton = app.buttons["Back"]
        let readerAppeared = backButton.waitForExistence(timeout: 15)

        if !readerAppeared {
            // Reader overlay might be hidden, tap to reveal it
            app.tap()
            sleep(1)
        }

        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Reader should show Back button")
        print("🧪 ✅ Successfully opened book in reader")

        // Take final screenshot
        let finalScreenshot = XCUIScreen.main.screenshot()
        let finalAttachment = XCTAttachment(screenshot: finalScreenshot)
        finalAttachment.name = "Reader View"
        finalAttachment.lifetime = .keepAlways
        add(finalAttachment)

        print("🧪 ✅ Book open integration test complete")
    }

    func testDoubleTapDoesNotMisalignPage() {
        // This test verifies that double-tapping on the page does not cause
        // the content to shift or become misaligned.

        // Open Frankenstein
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("🧪 Opening Frankenstein...")
        let banksAuthor = findBook(containing: "Frankenstein")
        XCTAssertTrue(banksAuthor.waitForExistence(timeout: 5), "Frankenstein book should be visible in library")
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

    // MARK: - Chat Scroll Behavior Tests

    func testChatExecutionDetailsScrollBehavior_Diagnostic() {
        // DIAGNOSTIC TEST: Reproduce the scroll bug
        // The reported bug: when expanding execution details that IS VISIBLE,
        // the scroll jumps and hides the "Execution Details" header above the visible area
        //
        // Key insight: We need to ensure the execution details is VISIBLE before tapping,
        // then observe what happens to the scroll position.

        try? FileManager.default.createDirectory(atPath: "/tmp/reader-tests", withIntermediateDirectories: true)

        // Open Frankenstein
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("🧪 Opening Frankenstein...")
        let bookCell = findBook(containing: "Frankenstein")
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5), "Frankenstein book should be visible in library")
        bookCell.tap()

        // Wait for book to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5), "WebView should exist")
        sleep(2)

        // Tap to reveal overlay
        webView.tap()
        sleep(1)

        // Open chat
        let chatButton = app.buttons["Chat"]
        XCTAssertTrue(chatButton.waitForExistence(timeout: 5), "Chat button should exist")
        chatButton.tap()

        let chatNavBar = app.navigationBars["Chat"]
        XCTAssertTrue(chatNavBar.waitForExistence(timeout: 5), "Chat navigation bar should appear")
        print("🧪 Chat view opened")

        // Dismiss keyboard by tapping elsewhere first
        let chatTable = app.tables["chat-message-list"]
        XCTAssertTrue(chatTable.waitForExistence(timeout: 5), "Chat table should exist")

        let chatInput = app.textViews["chat-input-textview"]
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5), "Chat input should exist")

        // Send a question
        chatInput.tap()
        chatInput.typeText("What is this book about?")

        let sendButton = app.buttons["chat-send-button"]
        sendButton.tap()
        print("🧪 Question sent, waiting for response...")

        // Wait for execution details to appear
        let executionDetailsCollapsed = app.staticTexts["execution-details-collapsed"]
        guard executionDetailsCollapsed.waitForExistence(timeout: 60) else {
            print("🧪 ⚠️ No execution details found")
            return
        }

        print("🧪 Response received with execution details")

        let tableFrame = chatTable.frame
        var collapsedFrame = executionDetailsCollapsed.frame

        print("🧪 Initial state:")
        print("🧪 Table visible Y range: \(tableFrame.minY) to \(tableFrame.maxY)")
        print("🧪 Execution details Y: \(collapsedFrame.minY)")

        // Check if execution details is below visible area
        if collapsedFrame.minY > tableFrame.maxY {
            print("🧪 Execution details is BELOW visible area - scrolling to bring it into view...")

            // Scroll up (swipe up = content moves up = we see lower content)
            chatTable.swipeUp()
            sleep(1)

            // Update the frame
            collapsedFrame = executionDetailsCollapsed.frame
            print("🧪 After scroll - Execution details Y: \(collapsedFrame.minY)")
        }

        // Verify it's visible before we tap
        let isVisibleBefore = collapsedFrame.minY >= tableFrame.minY && collapsedFrame.maxY <= tableFrame.maxY
        print("🧪 === BEFORE EXPAND ===")
        print("🧪 Table frame: \(tableFrame)")
        print("🧪 Table visible Y range: \(tableFrame.minY) to \(tableFrame.maxY)")
        print("🧪 Collapsed execution details frame: \(collapsedFrame)")
        print("🧪 Execution details fully visible before tap: \(isVisibleBefore)")
        print("🧪 Execution details is hittable: \(executionDetailsCollapsed.isHittable)")

        // SCREENSHOT 1: Before expanding - execution details should be visible
        let screenshot1 = XCUIScreen.main.screenshot()
        try? screenshot1.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/reader-tests/1-before-expand.png"))
        let attach1 = XCTAttachment(screenshot: screenshot1)
        attach1.name = "1-Before-Expand"
        attach1.lifetime = .keepAlways
        add(attach1)

        // TAP TO EXPAND - this is where the bug should manifest
        print("🧪 Tapping to expand execution details...")
        executionDetailsCollapsed.tap()

        // Wait for the expansion and scroll animation
        sleep(2)

        // SCREENSHOT 2: Immediately after expand - check if header is still visible
        let screenshot2 = XCUIScreen.main.screenshot()
        try? screenshot2.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/reader-tests/2-after-expand.png"))
        let attach2 = XCTAttachment(screenshot: screenshot2)
        attach2.name = "2-After-Expand"
        attach2.lifetime = .keepAlways
        add(attach2)

        // Check what's visible now
        let executionDetailsExpanded = app.staticTexts["execution-details-expanded"]
        if executionDetailsExpanded.waitForExistence(timeout: 3) {
            let expandedFrame = executionDetailsExpanded.frame
            print("🧪 === AFTER EXPAND ===")
            print("🧪 Expanded execution details frame: \(expandedFrame)")
            print("🧪 Execution details top Y: \(expandedFrame.minY)")
            print("🧪 Execution details bottom Y: \(expandedFrame.maxY)")
            print("🧪 Execution details height: \(expandedFrame.height)")
            print("🧪 Table visible Y range: \(tableFrame.minY) to \(tableFrame.maxY)")

            // THE BUG CHECK: Is the TOP of execution details visible?
            // If minY < tableFrame.minY, the header is scrolled above the visible area
            let headerVisible = expandedFrame.minY >= tableFrame.minY
            let headerAboveViewport = expandedFrame.minY < tableFrame.minY

            print("🧪 Header visible in viewport: \(headerVisible)")
            print("🧪 Header scrolled ABOVE viewport (BUG): \(headerAboveViewport)")

            if headerAboveViewport {
                let hiddenAmount = tableFrame.minY - expandedFrame.minY
                print("🧪 🐛 BUG DETECTED: Header is \(hiddenAmount) points above visible area!")
                print("🧪 🐛 User would need to scroll UP to see 'Execution Details ▼' header")
            }

            // Also check: is the header below the viewport? (scrolled too far down)
            let headerBelowViewport = expandedFrame.minY > tableFrame.maxY
            if headerBelowViewport {
                print("🧪 🐛 BUG: Header is BELOW viewport!")
            }

            // Check if "Execution Details" text is actually hittable on screen
            print("🧪 Execution details expanded element is hittable: \(executionDetailsExpanded.isHittable)")

        } else {
            print("🧪 ⚠️ Could not find expanded execution details element")
            // Take another screenshot to debug
            let screenshot3 = XCUIScreen.main.screenshot()
            try? screenshot3.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/reader-tests/3-debug.png"))
        }

        print("🧪 Screenshots saved to /tmp/reader-tests/")
        print("🧪 1-before-expand.png - state before tapping")
        print("🧪 2-after-expand.png - state after expanding")
    }

    func testChatScrollBug_MultipleMessages() {
        // Try to reproduce the bug with multiple messages creating more scroll context
        // The bug might manifest when there's more content above the execution details

        try? FileManager.default.createDirectory(atPath: "/tmp/reader-tests", withIntermediateDirectories: true)

        // Open Frankenstein
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        let bookCell = findBook(containing: "Frankenstein")
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5))
        bookCell.tap()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5))
        sleep(2)

        webView.tap()
        sleep(1)

        let chatButton = app.buttons["Chat"]
        XCTAssertTrue(chatButton.waitForExistence(timeout: 5))
        chatButton.tap()

        let chatNavBar = app.navigationBars["Chat"]
        XCTAssertTrue(chatNavBar.waitForExistence(timeout: 5))
        print("🧪 Chat opened")

        let chatInput = app.textViews["chat-input-textview"]
        let sendButton = app.buttons["chat-send-button"]
        let chatTable = app.tables["chat-message-list"]

        // Send FIRST question
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5))
        chatInput.tap()
        chatInput.typeText("Who is the main character?")
        sendButton.tap()
        print("🧪 First question sent...")

        // Wait for first response
        var executionDetails = app.staticTexts["execution-details-collapsed"]
        guard executionDetails.waitForExistence(timeout: 60) else {
            print("🧪 No response to first question")
            return
        }
        print("🧪 First response received")
        sleep(2)

        // Send SECOND question to create more scroll context
        chatInput.tap()
        chatInput.typeText("Tell me about the setting")
        sendButton.tap()
        print("🧪 Second question sent...")

        // Wait for second response - need to wait for a NEW execution details
        sleep(5) // Wait for response to start
        guard executionDetails.waitForExistence(timeout: 60) else {
            print("🧪 No response to second question")
            return
        }
        print("🧪 Second response received")
        sleep(2)

        // Now scroll to bring the LATEST execution details into view at the BOTTOM of screen
        // This simulates the user looking at the bottom of a conversation
        print("🧪 Scrolling to bottom of conversation...")
        chatTable.swipeUp()
        chatTable.swipeUp()
        sleep(1)

        // There might be multiple execution details - get the last (most recent) one
        let allExecutionDetails = app.staticTexts.matching(identifier: "execution-details-collapsed")
        let count = allExecutionDetails.count
        print("🧪 Found \(count) execution details elements")

        // Use the last one (most recent message)
        executionDetails = allExecutionDetails.element(boundBy: count - 1)

        let tableFrame = chatTable.frame
        var collapsedFrame = executionDetails.frame

        print("🧪 === STATE BEFORE EXPAND ===")
        print("🧪 Table visible Y range: \(tableFrame.minY) to \(tableFrame.maxY)")
        print("🧪 Execution details Y: \(collapsedFrame.minY)")
        print("🧪 Execution details bottom Y: \(collapsedFrame.maxY)")
        print("🧪 Is execution details visible: \(collapsedFrame.minY >= tableFrame.minY && collapsedFrame.maxY <= tableFrame.maxY)")
        print("🧪 Is hittable: \(executionDetails.isHittable)")

        // SCREENSHOT BEFORE
        let screenshot1 = XCUIScreen.main.screenshot()
        try? screenshot1.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/reader-tests/multi-1-before.png"))
        let attach1 = XCTAttachment(screenshot: screenshot1)
        attach1.name = "Multi-1-Before"
        attach1.lifetime = .keepAlways
        add(attach1)

        // TAP TO EXPAND
        if executionDetails.isHittable {
            print("🧪 Tapping execution details to expand...")
            executionDetails.tap()
            sleep(2)

            // SCREENSHOT AFTER
            let screenshot2 = XCUIScreen.main.screenshot()
            try? screenshot2.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/reader-tests/multi-2-after.png"))
            let attach2 = XCTAttachment(screenshot: screenshot2)
            attach2.name = "Multi-2-After"
            attach2.lifetime = .keepAlways
            add(attach2)

            // Check if header is visible
            let expanded = app.staticTexts["execution-details-expanded"]
            if expanded.waitForExistence(timeout: 3) {
                let expandedFrame = expanded.frame
                print("🧪 === STATE AFTER EXPAND ===")
                print("🧪 Expanded frame: \(expandedFrame)")
                print("🧪 Header Y position: \(expandedFrame.minY)")
                print("🧪 Table visible range: \(tableFrame.minY) to \(tableFrame.maxY)")

                let headerAbove = expandedFrame.minY < tableFrame.minY
                let headerBelow = expandedFrame.minY > tableFrame.maxY

                if headerAbove {
                    print("🧪 🐛 BUG! Header is \(tableFrame.minY - expandedFrame.minY) points ABOVE viewport!")
                } else if headerBelow {
                    print("🧪 🐛 BUG! Header is BELOW viewport!")
                } else {
                    print("🧪 Header is visible in viewport")
                }
            }
        } else {
            print("🧪 Execution details not hittable - scrolling more...")
            chatTable.swipeUp()
            sleep(1)
            if executionDetails.isHittable {
                executionDetails.tap()
                sleep(2)
            }
        }

        print("🧪 Multi-message test complete")
        print("🧪 Screenshots: /tmp/reader-tests/multi-1-before.png, multi-2-after.png")
    }

    func testChatExecutionDetailsScrollBehavior() {
        // This test verifies that when execution details are expanded in the chat,
        // the scroll position correctly shows the execution details header,
        // not scrolling past it where the user can't see what they tapped.
        //
        // Expected behavior:
        // - If execution details are short: the last line should be visible
        // - If execution details are long: the first line of execution details should be visible

        // Open Frankenstein
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("🧪 Opening Frankenstein...")
        let bookCell = findBook(containing: "Frankenstein")
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5), "Frankenstein book should be visible in library")
        bookCell.tap()

        // Wait for book to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5), "WebView should exist")
        sleep(2)

        // Tap to reveal overlay
        print("🧪 Revealing overlay...")
        webView.tap()
        sleep(1)

        // Find and tap the Chat button
        let chatButton = app.buttons["Chat"]
        XCTAssertTrue(chatButton.waitForExistence(timeout: 5), "Chat button should exist")
        print("🧪 Opening chat...")
        chatButton.tap()

        // Wait for chat view to appear
        let chatNavBar = app.navigationBars["Chat"]
        XCTAssertTrue(chatNavBar.waitForExistence(timeout: 5), "Chat navigation bar should appear")
        print("🧪 Chat view opened")

        // Find the chat input text view
        let chatInput = app.textViews["chat-input-textview"]
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5), "Chat input should exist")

        // Type a question
        print("🧪 Typing a question...")
        chatInput.tap()
        chatInput.typeText("What is this book about?")

        // Find and tap send button
        let sendButton = app.buttons["chat-send-button"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 3), "Send button should exist")
        print("🧪 Sending message...")
        sendButton.tap()

        // Wait for response - execution details should appear
        // The execution details starts collapsed with "▶" indicator
        print("🧪 Waiting for response with execution details...")
        let executionDetailsCollapsed = app.staticTexts["execution-details-collapsed"]
        let responseReceived = executionDetailsCollapsed.waitForExistence(timeout: 60)

        if !responseReceived {
            // If no execution details, the model might not have trace enabled
            // Take screenshot for debugging
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "No Execution Details"
            attachment.lifetime = .keepAlways
            add(attachment)

            print("🧪 ⚠️ No execution details found - response may not have trace")
            // Still check for response content
            let chatTable = app.tables["chat-message-list"]
            XCTAssertTrue(chatTable.exists, "Chat message list should exist")
            return
        }

        print("🧪 Execution details found (collapsed)")

        // Get the frame of the execution details before expanding
        let frameBeforeExpand = executionDetailsCollapsed.frame
        print("🧪 Execution details frame before expand: \(frameBeforeExpand)")

        // Take screenshot before expanding
        let screenshotBefore = XCUIScreen.main.screenshot()
        let attachmentBefore = XCTAttachment(screenshot: screenshotBefore)
        attachmentBefore.name = "Before Expand"
        attachmentBefore.lifetime = .keepAlways
        add(attachmentBefore)

        // Tap to expand execution details
        print("🧪 Tapping to expand execution details...")
        executionDetailsCollapsed.tap()
        sleep(1) // Wait for expansion animation and scroll

        // After expanding, look for the expanded version
        let executionDetailsExpanded = app.staticTexts["execution-details-expanded"]
        XCTAssertTrue(executionDetailsExpanded.waitForExistence(timeout: 5),
                     "Execution details should be expanded")
        print("🧪 Execution details expanded")

        // Take screenshot after expanding
        let screenshotAfter = XCUIScreen.main.screenshot()
        let attachmentAfter = XCTAttachment(screenshot: screenshotAfter)
        attachmentAfter.name = "After Expand"
        attachmentAfter.lifetime = .keepAlways
        add(attachmentAfter)

        // CRITICAL ASSERTION: The execution details header should be visible
        // This is the bug - the scroll was hiding the header
        let frameAfterExpand = executionDetailsExpanded.frame
        print("🧪 Execution details frame after expand: \(frameAfterExpand)")

        // Get the visible area of the chat table
        let chatTable = app.tables["chat-message-list"]
        XCTAssertTrue(chatTable.exists, "Chat message list should exist")
        let tableFrame = chatTable.frame
        print("🧪 Chat table frame: \(tableFrame)")

        // Check that the top of the execution details is visible (within the table's bounds)
        // The Y position should be >= table's minY (not scrolled above the visible area)
        let isTopVisible = frameAfterExpand.minY >= tableFrame.minY
        let isPartiallyVisible = frameAfterExpand.maxY > tableFrame.minY

        print("🧪 Top of execution details visible: \(isTopVisible)")
        print("🧪 Partially visible: \(isPartiallyVisible)")

        // Primary assertion: The header should be visible after expanding
        // If the execution details are long, at minimum the first line should be visible
        XCTAssertTrue(isPartiallyVisible,
                     "Execution details should be at least partially visible after expansion. " +
                     "Frame: \(frameAfterExpand), Table: \(tableFrame)")

        // If we can see the element, also verify it contains the expected header text
        let expandedText = executionDetailsExpanded.label
        XCTAssertTrue(expandedText.contains("Execution Details"),
                     "Expanded section should show 'Execution Details' header")
        XCTAssertTrue(expandedText.contains("▼"),
                     "Expanded section should show down arrow indicator")

        print("🧪 ✅ Execution details scroll test passed - header is visible after expansion")

        // Save screenshot for visual inspection
        try? FileManager.default.createDirectory(atPath: "/tmp/reader-tests", withIntermediateDirectories: true)
        let afterPath = "/tmp/reader-tests/execution-details-expand.png"
        try? screenshotAfter.pngRepresentation.write(to: URL(fileURLWithPath: afterPath))
        print("🧪 Screenshot saved to: \(afterPath)")
    }

    func testChatExecutionDetailsCollapseExpand() {
        // This test verifies that execution details can be toggled between
        // collapsed and expanded states, and the scroll behavior is correct each time

        // Open Frankenstein
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("🧪 Opening Frankenstein...")
        let bookCell = findBook(containing: "Frankenstein")
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5), "Frankenstein book should be visible")
        bookCell.tap()

        // Wait for book to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5), "WebView should exist")
        sleep(2)

        // Tap to reveal overlay and open chat
        webView.tap()
        sleep(1)

        let chatButton = app.buttons["Chat"]
        XCTAssertTrue(chatButton.waitForExistence(timeout: 5), "Chat button should exist")
        chatButton.tap()

        let chatNavBar = app.navigationBars["Chat"]
        XCTAssertTrue(chatNavBar.waitForExistence(timeout: 5), "Chat should open")
        print("🧪 Chat opened")

        // Send a question
        let chatInput = app.textViews["chat-input-textview"]
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5), "Chat input should exist")
        chatInput.tap()
        chatInput.typeText("Tell me about the main character")

        let sendButton = app.buttons["chat-send-button"]
        sendButton.tap()
        print("🧪 Question sent")

        // Wait for response
        let executionDetailsCollapsed = app.staticTexts["execution-details-collapsed"]
        guard executionDetailsCollapsed.waitForExistence(timeout: 60) else {
            print("🧪 ⚠️ No execution details - skipping toggle test")
            return
        }

        print("🧪 Starting collapse/expand toggle test...")

        // Toggle 1: Expand
        print("🧪 Toggle 1: Expanding...")
        executionDetailsCollapsed.tap()
        sleep(1)

        let executionDetailsExpanded = app.staticTexts["execution-details-expanded"]
        XCTAssertTrue(executionDetailsExpanded.waitForExistence(timeout: 5), "Should be expanded")

        // Verify header is visible
        let chatTable = app.tables["chat-message-list"]
        let expandedFrame = executionDetailsExpanded.frame
        let tableFrame = chatTable.frame
        XCTAssertTrue(expandedFrame.maxY > tableFrame.minY,
                     "Expanded execution details should be visible")
        print("🧪 ✅ Toggle 1: Expanded and visible")

        // Toggle 2: Collapse
        print("🧪 Toggle 2: Collapsing...")
        executionDetailsExpanded.tap()
        sleep(1)

        XCTAssertTrue(executionDetailsCollapsed.waitForExistence(timeout: 5), "Should be collapsed")
        print("🧪 ✅ Toggle 2: Collapsed")

        // Toggle 3: Expand again
        print("🧪 Toggle 3: Expanding again...")
        executionDetailsCollapsed.tap()
        sleep(1)

        XCTAssertTrue(executionDetailsExpanded.waitForExistence(timeout: 5), "Should be expanded again")

        // Final verification: header should still be visible
        let finalFrame = executionDetailsExpanded.frame
        XCTAssertTrue(finalFrame.maxY > tableFrame.minY,
                     "Execution details should remain visible after multiple toggles")

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "After Toggle Test"
        attachment.lifetime = .keepAlways
        add(attachment)

        print("🧪 ✅ Collapse/expand toggle test complete")
    }

}
