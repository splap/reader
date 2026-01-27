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

    /// Extracts total page count from page label text
    /// - Parameter text: The page label text (e.g., "Page 1 of 185" or "total pages: 185")
    /// - Returns: The total page count, or 0 if parsing fails
    func extractTotalPages(from text: String) -> Int {
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
        // Extract just the number part before any additional text
        let numberPart = components[1].components(separatedBy: CharacterSet.decimalDigits.inverted).first ?? ""
        return Int(numberPart) ?? 0
    }

    /// Extracts current page number from page label text
    /// - Parameter text: The page label text (e.g., "Page 5 of 185")
    /// - Returns: The current page number, or nil if parsing fails
    func extractCurrentPage(from text: String) -> Int? {
        // Handle "Page X of Y" format
        let pattern = #"Page\s+(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[range])
    }

    /// Extracts chapter number from page label text
    /// - Parameter text: The page label text (e.g., "Page 1 of 4 Ch. 5 of 32")
    /// - Returns: The chapter number, or 0 if parsing fails
    func extractChapter(from text: String) -> Int {
        let pattern = #"Ch\.\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return 0
        }
        return Int(text[range]) ?? 0
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
