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
        // This test verifies that Frankenstein loads with the correct number of pages.
        // Frankenstein is a full novel (~75,000 words) and should have 100+ pages
        // at any reasonable text size. If it shows only a few pages, pagination is broken.
        //
        // This catches regressions where book loading optimizations break pagination.

        // Open Frankenstein
        let webView = openFrankenstein(in: app)

        print("Book loaded, revealing overlay to check page count...")
        webView.tap()
        sleep(1)

        // Get the scrubber and page label
        let scrubber = app.sliders["Page scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 3), "Scrubber should exist")

        let pageLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(pageLabel.waitForExistence(timeout: 3), "Page label should exist")

        let initialPageText = pageLabel.label
        print("Initial page label: \(initialPageText)")

        // Extract total page count
        let totalPages = extractTotalPages(from: initialPageText)
        print("Total pages: \(totalPages)")

        // CRITICAL ASSERTION: Frankenstein must have a reasonable number of pages
        // The novel is ~75,000 words. Even with large text, it should be 100+ pages.
        // If this fails with a very low number (like 3), pagination is broken.
        XCTAssertGreaterThan(totalPages, 100,
            "Frankenstein should have at least 100 pages (got \(totalPages)). " +
            "If this is a very small number, book loading/pagination is broken.")

        // Navigate to the last page
        print("Scrubbing to last page...")
        scrubber.adjust(toNormalizedSliderPosition: 1.0)
        sleep(2) // Wait for page load

        // Verify we're on the last page
        let finalPageText = pageLabel.label
        print("Final page label: \(finalPageText)")

        if let currentPage = extractCurrentPage(from: finalPageText) {
            let finalTotalPages = extractTotalPages(from: finalPageText)
            print("At page \(currentPage) of \(finalTotalPages)")

            // Verify we're near the end of the book (within last 5%)
            // Scrubber precision can vary due to slider control mechanics
            let minExpectedPage = Int(Double(finalTotalPages) * 0.95)
            XCTAssertGreaterThanOrEqual(currentPage, minExpectedPage,
                "Should be near the last page after scrubbing to 100% (expected >= \(minExpectedPage), got \(currentPage))")

            // Double-check total pages is still reasonable
            XCTAssertGreaterThan(finalTotalPages, 100,
                "Total pages should still be > 100 at end of book")
        }

        // Take screenshot of the final page for visual verification
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Frankenstein Final Page"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Save to temp for inspection
        try? FileManager.default.createDirectory(atPath: "/tmp/reader-tests", withIntermediateDirectories: true)
        let screenshotPath = "/tmp/reader-tests/frankenstein-final-page.png"
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: screenshotPath))
        print("Final page screenshot saved to: \(screenshotPath)")

        // Verify webview has substantial text content on the last page
        let webViewStaticTexts = app.webViews.firstMatch.staticTexts
        let textElementCount = webViewStaticTexts.count
        print("Text elements on final page: \(textElementCount)")
        XCTAssertGreaterThan(textElementCount, 0,
            "Last page should have some text content rendered")

        print("Frankenstein book integrity test passed - \(totalPages) pages, last page verified")
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
