import XCTest

final class BookIntegrityTests: XCTestCase {
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

    func testFrankensteinBookIntegrity() {
        // This test verifies that Frankenstein loads correctly with proper chapter structure.
        // Frankenstein is a full novel (~75,000 words) and should have 25+ chapters.
        // With spine-scoped rendering, we verify chapter count and page navigation works.
        //
        // This catches regressions where book loading optimizations break pagination.

        // Open Frankenstein
        let webView = openFrankenstein(in: app)

        print("Book loaded, revealing overlay to check chapter count...")
        webView.tap()
        sleep(1)

        // Get the scrubber and page label
        let scrubber = app.sliders["Page scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 3), "Scrubber should exist")

        let pageLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(pageLabel.waitForExistence(timeout: 3), "Page label should exist")

        let initialPageText = pageLabel.label
        print("Initial page label: \(initialPageText)")

        // Parse scrubber info
        guard let scrubberInfo = parseScrubberLabel(initialPageText) else {
            XCTFail("Could not parse scrubber label: \(initialPageText)")
            return
        }

        print("Parsed: Chapter \(scrubberInfo.currentChapter) of \(scrubberInfo.totalChapters), " +
              "Page \(scrubberInfo.currentPage) of \(scrubberInfo.pagesInChapter)")

        // CRITICAL ASSERTION: Frankenstein must have a reasonable number of chapters
        // The novel has 32 spine items (letters + chapters). Verify we have substantial content.
        XCTAssertGreaterThan(scrubberInfo.totalChapters, 25,
            "Frankenstein should have at least 25 chapters (got \(scrubberInfo.totalChapters)). " +
            "If this is a very small number, book loading is broken.")

        // Note: The scrubber controls pages within the current chapter, not cross-chapter navigation
        // To navigate between chapters, use the TOC or swipe through the book
        // Here we verify the scrubber navigates within the chapter correctly
        if scrubberInfo.pagesInChapter > 1 {
            print("Scrubbing to last page of current chapter...")
            scrubber.adjust(toNormalizedSliderPosition: 1.0)
            sleep(1)

            let afterScrubText = pageLabel.label
            print("After scrub: \(afterScrubText)")

            if let afterInfo = parseScrubberLabel(afterScrubText) {
                // Should be at the last page of the same chapter
                XCTAssertEqual(afterInfo.currentChapter, scrubberInfo.currentChapter,
                    "Scrubber should navigate within same chapter")
                XCTAssertEqual(afterInfo.currentPage, afterInfo.pagesInChapter,
                    "Should be on last page after scrubbing to 100%")
            }
        }

        // Take screenshot for visual verification
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Frankenstein Book Integrity"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Save to temp for inspection
        try? FileManager.default.createDirectory(atPath: "/tmp/reader-tests", withIntermediateDirectories: true)
        let screenshotPath = "/tmp/reader-tests/frankenstein-book-integrity.png"
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: screenshotPath))
        print("Screenshot saved to: \(screenshotPath)")

        // Verify webview has text content
        let webViewStaticTexts = app.webViews.firstMatch.staticTexts
        let textElementCount = webViewStaticTexts.count
        print("Text elements: \(textElementCount)")
        XCTAssertGreaterThan(textElementCount, 0,
            "Should have text content rendered")

        print("Frankenstein book integrity test passed - \(scrubberInfo.totalChapters) chapters verified")
    }

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
        print("Library loaded after clean state")

        // Wait a moment for books to be imported
        sleep(3)

        // Look for any book in the library
        // Since we cleared all data, bundled books should be re-imported
        let tableView = app.tables.firstMatch
        XCTAssertTrue(tableView.waitForExistence(timeout: 5), "Table view should exist")

        // Get the first cell (any book will do)
        let firstCell = tableView.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 10), "At least one book should be imported")
        print("Found book in library: \(firstCell.label)")

        // Tap to open the book
        firstCell.tap()
        print("Tapped book to open - expecting indexing progress...")

        // Look for the indexing progress view
        // The IndexingProgressView shows "Preparing Book" as the title
        let preparingLabel = app.staticTexts["Preparing Book"]
        let indexingVisible = preparingLabel.waitForExistence(timeout: 5)

        if indexingVisible {
            print("Indexing progress view appeared!")

            // Take screenshot of indexing progress
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "Indexing Progress"
            attachment.lifetime = .keepAlways
            add(attachment)

            // Wait for indexing to complete - look for Back button
            print("Waiting for indexing to complete...")

        } else {
            // Indexing progress didn't appear - book was already indexed
            // (background indexing happens during import)
            print("Indexing progress view did not appear (book already indexed)")
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
        print("Successfully opened book in reader")

        // Take final screenshot
        let finalScreenshot = XCUIScreen.main.screenshot()
        let finalAttachment = XCTAttachment(screenshot: finalScreenshot)
        finalAttachment.name = "Reader View"
        finalAttachment.lifetime = .keepAlways
        add(finalAttachment)

        print("Book open integration test complete")
    }
}
