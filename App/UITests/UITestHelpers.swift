import XCTest

extension XCTestCase {
    /// Launches the Reader app with standard UI testing arguments
    /// - Parameter extraArgs: Additional launch arguments to append
    /// - Returns: The launched XCUIApplication instance
    func launchReaderApp(extraArgs: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["--uitesting", "--uitesting-skip-indexing", "--uitesting-webview"]
        args.append(contentsOf: extraArgs)
        app.launchArguments = args
        app.launch()
        return app
    }

    /// Helper to find a book cell by partial title match
    /// - Parameters:
    ///   - app: The XCUIApplication instance
    ///   - title: Partial title to search for (e.g., "Frankenstein" matches "Frankenstein; Or, The Modern Prometheus")
    /// - Returns: The matching XCUIElement
    func findBook(in app: XCUIApplication, containing title: String) -> XCUIElement {
        return app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
    }

    /// Helper to open Frankenstein book and wait for it to load
    /// - Parameter app: The XCUIApplication instance
    /// - Returns: The WebView element containing the book content
    func openFrankenstein(in app: XCUIApplication) -> XCUIElement {
        let libraryNavBar = app.navigationBars["Library"]
        XCTAssertTrue(libraryNavBar.waitForExistence(timeout: 5))

        print("Opening Frankenstein...")
        let bookCell = findBook(in: app, containing: "Frankenstein")
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5), "Frankenstein should be visible in library")
        bookCell.tap()

        // Wait for book to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5), "WebView should exist after opening book")
        sleep(2) // Let content render
        return webView
    }

    // MARK: - Scrubber Label Parsing

    /// Parsed scrubber label information
    /// Format: "Page X of Y · Ch. A of B"
    struct ScrubberInfo {
        let currentPage: Int       // X - current page within chapter
        let pagesInChapter: Int    // Y - total pages in current chapter
        let currentChapter: Int    // A - current chapter number
        let totalChapters: Int     // B - total chapters in book

        /// Estimates a global page position for comparison purposes
        /// This is approximate since chapters have varying page counts
        var estimatedGlobalPosition: Double {
            guard totalChapters > 0, pagesInChapter > 0 else { return 0 }
            let chapterProgress = Double(currentPage) / Double(pagesInChapter)
            return (Double(currentChapter - 1) + chapterProgress) / Double(totalChapters)
        }
    }

    /// Parses the scrubber label into structured info
    /// - Parameter text: The scrubber label text (e.g., "Page 1 of 4 · Ch. 5 of 32")
    /// - Returns: Parsed ScrubberInfo, or nil if parsing fails
    func parseScrubberLabel(_ text: String) -> ScrubberInfo? {
        // Pattern matches: "Page X of Y · Ch. A of B" or "Page X of Y"
        // The chapter part is optional for backwards compatibility
        let pattern = #"Page\s+(\d+)\s+of\s+(\d+)(?:\s*·\s*Ch\.\s*(\d+)\s+of\s+(\d+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }

        func extractInt(at index: Int) -> Int? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return Int(text[range])
        }

        guard let currentPage = extractInt(at: 1),
              let pagesInChapter = extractInt(at: 2) else {
            return nil
        }

        let currentChapter = extractInt(at: 3) ?? 1
        let totalChapters = extractInt(at: 4) ?? 1

        return ScrubberInfo(
            currentPage: currentPage,
            pagesInChapter: pagesInChapter,
            currentChapter: currentChapter,
            totalChapters: totalChapters
        )
    }

    /// Extracts total chapters from page label text
    /// - Parameter text: The page label text (e.g., "Page 1 of 4 · Ch. 5 of 32")
    /// - Returns: The total chapter count, or 0 if parsing fails
    func extractTotalChapters(from text: String) -> Int {
        parseScrubberLabel(text)?.totalChapters ?? 0
    }

    /// Extracts pages in current chapter from page label text
    /// - Parameter text: The page label text (e.g., "Page 1 of 4 · Ch. 5 of 32")
    /// - Returns: The page count in current chapter, or 0 if parsing fails
    func extractPagesInChapter(from text: String) -> Int {
        parseScrubberLabel(text)?.pagesInChapter ?? 0
    }

    /// Extracts total page count from page label text
    /// For spine-scoped rendering, this returns pages in the current chapter
    /// - Parameter text: The page label text
    /// - Returns: The page count (per-chapter), or 0 if parsing fails
    func extractTotalPages(from text: String) -> Int {
        // Handle "total pages: N" format from debug overlay (legacy)
        if text.contains("total pages:") {
            let components = text.components(separatedBy: "total pages:")
            guard components.count >= 2 else { return 0 }
            let numberPart = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let digits = numberPart.components(separatedBy: .whitespacesAndNewlines).first ?? ""
            return Int(digits) ?? 0
        }

        // Use the structured parser
        return parseScrubberLabel(text)?.pagesInChapter ?? 0
    }

    /// Extracts current page number from page label text
    /// - Parameter text: The page label text (e.g., "Page 5 of 10 · Ch. 3 of 32")
    /// - Returns: The current page number within chapter, or nil if parsing fails
    func extractCurrentPage(from text: String) -> Int? {
        parseScrubberLabel(text)?.currentPage
    }

    /// Extracts chapter number from page label text
    /// - Parameter text: The page label text (e.g., "Page 1 of 4 · Ch. 5 of 32")
    /// - Returns: The chapter number, or 0 if parsing fails
    func extractChapter(from text: String) -> Int {
        parseScrubberLabel(text)?.currentChapter ?? 0
    }

    /// Helper to navigate back to library from reader
    /// - Parameter app: The XCUIApplication instance
    func navigateToLibrary(in app: XCUIApplication) {
        // Check if we're already in the library
        let libraryNavBar = app.navigationBars["Library"]
        if libraryNavBar.exists {
            return
        }

        // If we're in the reader, tap to show overlay and press back
        let backButton = app.buttons["Back"]

        // First tap to reveal overlay (buttons start hidden)
        if !backButton.isHittable {
            // Try tapping the webview or screen to reveal overlay
            let webView = app.webViews.firstMatch
            if webView.exists {
                webView.tap()
            } else {
                app.tap()
            }
            sleep(1)
        }

        // Now try to tap back
        if backButton.waitForExistence(timeout: 3) && backButton.isHittable {
            backButton.tap()
            sleep(1)
        }

        // Wait for library to appear
        _ = libraryNavBar.waitForExistence(timeout: 5)
    }

    /// Opens a book by name and returns the content view
    /// - Parameters:
    ///   - app: The XCUIApplication instance
    ///   - bookName: The name of the book to open
    /// - Returns: The WebView element, or nil if opening failed
    func openBook(in app: XCUIApplication, named bookName: String) -> XCUIElement? {
        let bookCell = findBook(in: app, containing: bookName)
        guard bookCell.waitForExistence(timeout: 5) else {
            return nil
        }
        bookCell.tap()

        // Wait for book to load
        let webView = app.webViews.firstMatch
        guard webView.waitForExistence(timeout: 10) else {
            return nil
        }
        sleep(2) // Let content render
        return webView
    }

    /// Waits for a label element to contain specific text
    /// - Parameters:
    ///   - element: The element to check
    ///   - text: The text to wait for
    ///   - timeout: Maximum time to wait
    func waitForLabel(_ element: XCUIElement, contains text: String, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Expected label to contain '\(text)'")
    }
}
