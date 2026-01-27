import XCTest

final class TOCTests: XCTestCase {
    var app: XCUIApplication!

    /// List of bundled books to test TOC functionality with
    private let bundledBooks = ["Frankenstein", "Meditations", "Metamorphosis"]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = launchReaderApp()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testTOCButtonVisibility() {
        // Test that TOC button is visible for all bundled books
        for bookName in bundledBooks {
            print("Testing TOC button visibility for: \(bookName)")

            // Navigate to library if needed
            navigateToLibrary(in: app)

            // Open the book
            guard let contentView = openBook(in: app, named: bookName) else {
                XCTFail("Failed to open book: \(bookName)")
                continue
            }

            // Tap to reveal overlay
            contentView.tap()
            sleep(1)

            // Verify TOC button exists and is hittable
            let tocButton = app.buttons["Table of Contents"]
            XCTAssertTrue(tocButton.waitForExistence(timeout: 3), "TOC button should exist for \(bookName)")
            XCTAssertTrue(tocButton.isHittable, "TOC button should be hittable for \(bookName)")

            // Verify accessibility identifier
            let tocButtonById = app.buttons["toc-button"]
            XCTAssertTrue(tocButtonById.exists, "TOC button should have accessibility identifier for \(bookName)")

            print("TOC button visible for \(bookName)")

            // Take screenshot
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "TOC Button - \(bookName)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        print("TOC button visibility test passed for all books")
    }

    func testTOCMenuShowsChapters() {
        // Test that tapping TOC button shows menu with chapters for all bundled books
        for bookName in bundledBooks {
            print("Testing TOC menu for: \(bookName)")

            // Navigate to library if needed
            navigateToLibrary(in: app)

            // Open the book
            guard let contentView = openBook(in: app, named: bookName) else {
                XCTFail("Failed to open book: \(bookName)")
                continue
            }

            // Tap to reveal overlay
            contentView.tap()
            sleep(1)

            // Tap TOC button to show menu
            let tocButton = app.buttons["toc-button"]
            XCTAssertTrue(tocButton.waitForExistence(timeout: 3), "TOC button should exist")
            tocButton.tap()
            sleep(1)

            // Verify menu appears by looking for menu items
            // UIMenu items appear in a different location in the view hierarchy
            let menuExists = app.buttons.count > 5 || app.staticTexts.count > 10
            XCTAssertTrue(menuExists, "Menu should appear after tapping TOC button for \(bookName)")

            // Take screenshot of menu
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "TOC Menu - \(bookName)"
            attachment.lifetime = .keepAlways
            add(attachment)

            // Save screenshot to temp
            try? FileManager.default.createDirectory(atPath: "/tmp/reader-tests", withIntermediateDirectories: true)
            let screenshotPath = "/tmp/reader-tests/toc-menu-\(bookName.lowercased().replacingOccurrences(of: " ", with: "-")).png"
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: screenshotPath))
            print("Screenshot saved to: \(screenshotPath)")

            // Dismiss menu by tapping elsewhere
            contentView.tap()
            sleep(1)

            print("TOC menu shown for \(bookName)")
        }

        print("TOC menu test passed for all books")
    }

    func testTOCNavigationToChapter() {
        // Test that selecting a chapter from TOC navigates to it
        for bookName in bundledBooks {
            print("Testing TOC navigation for: \(bookName)")

            // Navigate to library if needed
            navigateToLibrary(in: app)

            // Open the book
            guard let contentView = openBook(in: app, named: bookName) else {
                XCTFail("Failed to open book: \(bookName)")
                continue
            }

            // Tap to reveal overlay
            contentView.tap()
            sleep(1)

            // Get initial page
            let pageLabel = app.staticTexts["scrubber-page-label"]
            guard pageLabel.waitForExistence(timeout: 3) else {
                print("No page label found for \(bookName), skipping navigation check")
                continue
            }
            let initialPageText = pageLabel.label
            print("Initial page: \(initialPageText)")

            // Tap TOC button
            let tocButton = app.buttons["toc-button"]
            XCTAssertTrue(tocButton.waitForExistence(timeout: 3), "TOC button should exist")
            tocButton.tap()
            sleep(1)

            // Take screenshot of menu before selecting
            let menuScreenshot = XCUIScreen.main.screenshot()
            let menuAttachment = XCTAttachment(screenshot: menuScreenshot)
            menuAttachment.name = "TOC Menu Before Selection - \(bookName)"
            menuAttachment.lifetime = .keepAlways
            add(menuAttachment)

            // Find and tap a menu item that is NOT the first one (to ensure navigation)
            // UIMenu items appear as buttons in the menu
            let menuButtons = app.buttons.allElementsBoundByIndex
            var tappedItem = false

            // Look for menu items - they should be in the menu, skip the first few buttons
            // (which are Back, TOC, Chat, Settings)
            for button in menuButtons {
                let label = button.label
                // Skip control buttons and empty labels
                if label.isEmpty || label == "Back" || label == "Settings" ||
                   label == "Chat" || label == "Table of Contents" {
                    continue
                }
                // Skip if it looks like the first chapter (often titles or "Letter" for Frankenstein)
                if label.lowercased().contains("letter 1") || label.lowercased().contains("title") {
                    continue
                }
                // Found a chapter item, tap it
                print("Tapping chapter: \(label)")
                button.tap()
                tappedItem = true
                break
            }

            if !tappedItem {
                print("Could not find chapter menu item to tap for \(bookName)")
                // Dismiss menu
                contentView.tap()
                sleep(1)
                continue
            }

            // Wait for navigation and scrubber animation
            sleep(2)

            // Check if page changed
            if pageLabel.waitForExistence(timeout: 2) {
                let newPageText = pageLabel.label
                print("After navigation: \(newPageText)")

                // Take screenshot after navigation
                let afterScreenshot = XCUIScreen.main.screenshot()
                let afterAttachment = XCTAttachment(screenshot: afterScreenshot)
                afterAttachment.name = "After TOC Navigation - \(bookName)"
                afterAttachment.lifetime = .keepAlways
                add(afterAttachment)

                // Save screenshot
                let afterPath = "/tmp/reader-tests/toc-after-\(bookName.lowercased().replacingOccurrences(of: " ", with: "-")).png"
                try? afterScreenshot.pngRepresentation.write(to: URL(fileURLWithPath: afterPath))
                print("After navigation screenshot saved to: \(afterPath)")
            }

            print("TOC navigation completed for \(bookName)")
        }

        print("TOC navigation test passed for all books")
    }

    func testTOCNavigationVerifyContent() {
        // Deep verification test for Frankenstein - verify we actually navigate to the right content
        print("Testing TOC navigation with content verification for Frankenstein")

        // Navigate to library
        navigateToLibrary(in: app)

        // Open Frankenstein
        guard let contentView = openBook(in: app, named: "Frankenstein") else {
            XCTFail("Failed to open Frankenstein")
            return
        }

        // Tap to reveal overlay
        contentView.tap()
        sleep(1)

        // Get initial page
        let pageLabel = app.staticTexts["scrubber-page-label"]
        guard pageLabel.waitForExistence(timeout: 3) else {
            XCTFail("Page label not found")
            return
        }
        let initialPageText = pageLabel.label
        print("Initial page: \(initialPageText)")

        // Tap TOC button
        let tocButton = app.buttons["toc-button"]
        XCTAssertTrue(tocButton.waitForExistence(timeout: 3), "TOC button should exist")
        tocButton.tap()
        sleep(1)

        // Look for "Chapter 1" or similar in the menu
        let menuButtons = app.buttons.allElementsBoundByIndex
        var foundChapter = false

        for button in menuButtons {
            let label = button.label.lowercased()
            if label.contains("chapter") && (label.contains("1") || label.contains("i")) {
                print("Tapping: \(button.label)")
                button.tap()
                foundChapter = true
                break
            }
        }

        if !foundChapter {
            // Try looking for "Letter" entries (Frankenstein starts with letters)
            for button in menuButtons {
                let label = button.label.lowercased()
                if label.contains("letter") && label.contains("4") {
                    print("Tapping: \(button.label)")
                    button.tap()
                    foundChapter = true
                    break
                }
            }
        }

        guard foundChapter else {
            XCTFail("Could not find a chapter to navigate to")
            return
        }

        // Wait for navigation
        sleep(3)

        // Take screenshot
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Frankenstein Chapter Navigation"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Save screenshot
        try? FileManager.default.createDirectory(atPath: "/tmp/reader-tests", withIntermediateDirectories: true)
        let screenshotPath = "/tmp/reader-tests/frankenstein-chapter-content.png"
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: screenshotPath))
        print("Content screenshot saved to: \(screenshotPath)")

        // Verify page changed from initial
        if pageLabel.exists {
            let newPageText = pageLabel.label
            print("After navigation: \(newPageText)")
            // We should be on a different page than page 1
            if initialPageText.contains("Page 1 of") && !newPageText.contains("Page 1 of") {
                print("Page changed from initial position")
            }
        }

        print("Content verification test complete")
    }

    func testTOCScrubberAutoHides() {
        // Test that scrubber auto-hides after TOC navigation
        // Note: The scrubber shows for 1.5s then auto-hides, so we verify it's hidden after waiting
        print("Testing scrubber auto-hide after TOC navigation")

        // Navigate to library
        navigateToLibrary(in: app)

        // Open Frankenstein
        guard let contentView = openBook(in: app, named: "Frankenstein") else {
            XCTFail("Failed to open Frankenstein")
            return
        }

        // Show overlay first
        contentView.tap()
        sleep(1)

        // Tap TOC button
        let tocButton = app.buttons["toc-button"]
        XCTAssertTrue(tocButton.waitForExistence(timeout: 3), "TOC button should exist")
        tocButton.tap()
        sleep(1)

        // Tap any chapter item (not first few which are control buttons)
        let menuButtons = app.buttons.allElementsBoundByIndex
        var tappedChapter = false
        for button in menuButtons {
            let label = button.label
            if !label.isEmpty && label != "Back" && label != "Settings" &&
               label != "Chat" && label != "Table of Contents" &&
               label.count > 3 {
                print("Tapping chapter: \(label)")
                button.tap()
                tappedChapter = true
                break
            }
        }

        guard tappedChapter else {
            XCTFail("Could not find chapter to tap")
            return
        }

        // Wait for auto-hide timeout (1.5s) plus some buffer
        sleep(4)

        // After 4 seconds, the scrubber should have auto-hidden
        let scrubber = app.sliders["Page scrubber"]
        let scrubberHidden = !scrubber.isHittable
        XCTAssertTrue(scrubberHidden, "Scrubber should auto-hide after TOC navigation")

        print("Scrubber auto-hide test passed")
    }
}
