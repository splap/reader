import XCTest

final class ScrubberTests: XCTestCase {
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

    func testScrubberAppearsOnTap() {
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

        print("Book loaded, verifying overlay is initially hidden...")

        // Verify scrubber and buttons are initially not visible (alpha = 0)
        // We can check by trying to find the page scrubber slider
        let scrubber = app.sliders["Page scrubber"]
        XCTAssertFalse(scrubber.isHittable, "Scrubber should not be hittable when overlay is hidden")

        print("Tapping to reveal overlay...")
        webView.tap()
        sleep(1)

        // Now verify scrubber is visible
        XCTAssertTrue(scrubber.waitForExistence(timeout: 3), "Scrubber should exist after tap")
        XCTAssertTrue(scrubber.isHittable, "Scrubber should be hittable when overlay is shown")
        print("Scrubber appeared after tap")

        // Verify back and settings buttons are also visible
        let backButton = app.buttons["Back"]
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(backButton.isHittable, "Back button should be hittable")
        XCTAssertTrue(settingsButton.isHittable, "Settings button should be hittable")
        print("Navigation buttons visible")

        // Verify page label is visible
        let pageLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(pageLabel.exists, "Page label should exist")
        print("Page label: \(pageLabel.label)")

        // Tap again to hide
        print("Tapping to hide overlay...")
        webView.tap()
        sleep(1)

        XCTAssertFalse(scrubber.isHittable, "Scrubber should not be hittable after hiding overlay")
        print("Overlay toggled off successfully")
    }

    func testScrubberNavigatesToPage() {
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
        sleep(3) // Let content render and pagination calculate

        print("Book loaded, revealing overlay...")
        webView.tap()
        sleep(1)

        // Get the scrubber slider
        let scrubber = app.sliders["Page scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 3), "Scrubber should exist")

        // Check initial page (should be page 1)
        let pageLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(pageLabel.waitForExistence(timeout: 3), "Page indicator should exist")
        let initialPageText = pageLabel.label
        print("Initial page: \(initialPageText)")
        XCTAssertTrue(initialPageText.contains("Page 1"), "Should start at page 1")

        // Move scrubber to middle (50%)
        print("Moving scrubber to 50% position...")
        scrubber.adjust(toNormalizedSliderPosition: 0.5)
        sleep(1)

        // Verify page changed
        let midPageText = pageLabel.label
        print("After scrub to 50%: \(midPageText)")
        XCTAssertFalse(midPageText.contains("Page 1"), "Should not be on page 1 after scrubbing to middle")

        // Extract page number and verify it's roughly in the middle
        if let pageNumber = extractCurrentPage(from: midPageText) {
            let totalPages = extractTotalPages(from: midPageText)
            if totalPages > 0 {
                let expectedMid = totalPages / 2
                let tolerance = max(1, totalPages / 10) // 10% tolerance, minimum 1
                XCTAssertTrue(
                    abs(pageNumber - expectedMid) <= tolerance,
                    "Page \(pageNumber) should be roughly in middle (expected ~\(expectedMid) of \(totalPages))"
                )
                print("Scrubber navigated to page \(pageNumber) of \(totalPages)")
            }
        }

        // Move to end (100%)
        print("Moving scrubber to end...")
        scrubber.adjust(toNormalizedSliderPosition: 1.0)
        sleep(1)

        let endPageText = pageLabel.label
        print("At end: \(endPageText)")

        // Take screenshot
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Scrubber Navigation End"
        attachment.lifetime = .keepAlways
        add(attachment)

        print("Scrubber navigation test complete")
    }

    func testMaxReadExtentIndicator() {
        // This test verifies that the max read extent indicator shows on the scrubber
        // We navigate forward in the book, then go back, and verify the red indicator
        // shows the furthest page we reached

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
        sleep(3)

        print("Book loaded, navigating forward 5 pages...")

        // Navigate forward 5 pages to establish max read extent
        for i in 1 ... 5 {
            webView.swipeLeft()
            usleep(300_000) // 0.3 seconds
            print("Swiped to page \(i + 1)")
        }
        sleep(1)

        // Reveal overlay and check current page
        webView.tap()
        sleep(1)

        let pageLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(pageLabel.waitForExistence(timeout: 3), "Page indicator should exist")
        let maxPageText = pageLabel.label
        print("Reached max page: \(maxPageText)")
        let maxPage = extractCurrentPage(from: maxPageText) ?? 0
        XCTAssertGreaterThan(maxPage, 1, "Should have navigated forward")

        // Hide overlay first (tap to toggle off)
        print("Hiding overlay before navigating back...")
        webView.tap()
        sleep(1)

        // Navigate back 3 pages using swipes
        print("Navigating back 3 pages...")
        for i in 1 ... 3 {
            webView.swipeRight()
            usleep(500_000) // 0.5 seconds between swipes
            print("Swiped back \(i) page(s)")
        }
        sleep(2) // Wait for page animation to settle

        // Reveal overlay again - tap and wait for scrubber to appear
        print("Tapping to reveal overlay...")
        webView.tap()
        sleep(1)

        // Wait for the scrubber to become visible
        let scrubber = app.sliders["Page scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5), "Scrubber should appear after tap")

        // Check we're now at a lower page but max extent should still show the furthest point
        let currentPageLabel = app.staticTexts["scrubber-page-label"]
        XCTAssertTrue(currentPageLabel.waitForExistence(timeout: 3), "Page indicator should exist")
        let currentPageText = currentPageLabel.label
        print("After navigating back: \(currentPageText)")
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
        print("Screenshot saved to: \(screenshotPath)")
        print("Visual inspection: red indicator on scrubber should extend to ~\(Float(maxPage)) / total pages")

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Max Read Extent Indicator"
        attachment.lifetime = .keepAlways
        add(attachment)

        print("Max read extent test complete (check screenshot for visual verification)")
    }
}
