import Foundation
import ReaderCore
import ReaderUI
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    private static let logger = Log.logger(category: "app")

    var window: UIWindow?
    private var screenshotObserver: NSObjectProtocol?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Self.logger.info("ReaderApp launched! Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "unknown")")
        Self.logger.info("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")

        // Screenshot mode - headless capture and exit
        if CommandLine.arguments.contains("--screenshot-mode") {
            return handleScreenshotMode()
        }

        // Clear state if running UI tests unless explicitly told to keep state.
        let isUITesting = CommandLine.arguments.contains("--uitesting")
        let keepUIState = CommandLine.arguments.contains("--uitesting-keep-state")
        let isPositionTest = CommandLine.arguments.contains("--uitesting-position-test")
        _ = CommandLine.arguments.contains("--uitesting-webview") // Ignored, WebView is only renderer
        _ = CommandLine.arguments.contains("--uitesting-native") // Ignored, native renderer removed
        let cleanAllData = CommandLine.arguments.contains("--uitesting-clean-all-data")
        let uitestingBook = Self.parseArgument("--uitesting-book=")
        let uitestingSpineItem = Self.parseIntArgument("--uitesting-spine-item=")
        let uitestingCFI = Self.parseArgument("--uitesting-cfi=")
        let openChat = CommandLine.arguments.contains("--open-chat")

        if isUITesting, cleanAllData {
            Self.logger.info("UI Testing mode - clearing ALL app data (Application Support + UserDefaults)")
            clearAllAppData()
        } else if isUITesting, !keepUIState {
            Self.logger.info("UI Testing mode detected - clearing app state")
            clearAppStateForTesting()
        }

        // Copy bundled books on first launch, then scan for all test books
        if !isPositionTest {
            copyBundledBooksIfNeeded()
            importTestBooksIfNeeded()
        }

        // Create window
        let window = UIWindow(frame: UIScreen.main.bounds)

        // Apply saved appearance (default: dark)
        let appearance = ReaderPreferences.shared.appearanceMode
        window.overrideUserInterfaceStyle = appearance.userInterfaceStyle

        // Create library view controller
        let libraryVC = LibraryViewController()
        let navController = UINavigationController(rootViewController: libraryVC)

        let autoOpenFirstBook = CommandLine.arguments.contains("--uitesting-auto-open-first-book")
        if isPositionTest {
            let chapter = UITestChapter.makePositionTestChapter(pageCount: 120)
            let readerVC = ReaderViewController(
                chapter: chapter,
                bookId: "ui-test-position",
                bookTitle: chapter.title,
                bookAuthor: "UI Test"
            )
            navController.pushViewController(readerVC, animated: false)
        } else if let bookSlug = uitestingBook, let book = findBookBySlug(bookSlug) {
            Self.logger.info("UI test opening book by slug: \(bookSlug) -> \(book.title), openChat: \(openChat)")
            BookLibraryService.shared.updateLastOpened(bookId: book.id)
            let fileURL = BookLibraryService.shared.getFileURL(for: book)

            // Determine spine item index from explicit arg or CFI
            var spineItemIndex = uitestingSpineItem
            if spineItemIndex == nil, let cfi = uitestingCFI {
                if let parsed = CFIParser.parseBaseCFI(cfi) {
                    spineItemIndex = parsed.spineIndex
                    Self.logger.info("Parsed CFI '\(cfi)' -> spine index \(parsed.spineIndex)")
                } else {
                    Self.logger.warning("Invalid CFI format: \(cfi)")
                }
            }

            // Use ReaderContainerViewController for full functionality (chat, nav bar)
            let containerVC = ReaderContainerViewController(
                epubURL: fileURL,
                bookId: book.id.uuidString,
                bookTitle: book.title,
                bookAuthor: book.author,
                autoOpenChat: openChat
            )
            navController.pushViewController(containerVC, animated: false)
        } else if autoOpenFirstBook, let book = BookLibraryService.shared.getAllBooks().first {
            Self.logger.info("UI test auto-opening first book: \(book.title)")
            BookLibraryService.shared.updateLastOpened(bookId: book.id)
            let fileURL = BookLibraryService.shared.getFileURL(for: book)
            let readerVC = ReaderViewController(
                epubURL: fileURL,
                bookId: book.id.uuidString,
                bookTitle: book.title,
                bookAuthor: book.author
            )
            navController.pushViewController(readerVC, animated: false)
        } else if let idString = UserDefaults.standard.string(forKey: "reader.lastOpenedBookId"),
                  let uuid = UUID(uuidString: idString),
                  let book = BookLibraryService.shared.getBook(id: uuid)
        {
            Self.logger.info("Auto-opening last book: \(book.title)")

            let fileURL = BookLibraryService.shared.getFileURL(for: book)
            let readerVC = ReaderViewController(
                epubURL: fileURL,
                bookId: book.id.uuidString,
                bookTitle: book.title,
                bookAuthor: book.author
            )
            navController.pushViewController(readerVC, animated: false)
        } else {
            Self.logger.info("Showing library")
        }

        window.rootViewController = navController
        window.makeKeyAndVisible()
        self.window = window

        return true
    }

    // Handle file opens from outside the app (AirDrop, Files, Share)
    func application(
        _: UIApplication,
        open url: URL,
        options _: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        guard url.pathExtension.lowercased() == "epub" else {
            return false
        }

        // Import the file
        do {
            _ = try BookLibraryService.shared.importBook(from: url, startAccessing: false)

            // Notify library view to refresh
            NotificationCenter.default.post(
                name: .bookLibraryDidChange,
                object: nil
            )

            return true
        } catch {
            Self.logger.error("Failed to import EPUB from external source: \(error)")
            return false
        }
    }

    // MARK: - Test Helpers (Data Clearing)

    /// Clears UserDefaults and Books directory together to keep them in sync
    /// Used by regular --uitesting to avoid orphaned book copies
    private func clearAppStateForTesting() {
        let fileManager = FileManager.default

        // Clear UserDefaults
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        UserDefaults.standard.synchronize()

        // Also clear Books directory to stay in sync (prevents orphaned copies)
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let booksDir = appSupport.appendingPathComponent("Books")
            if fileManager.fileExists(atPath: booksDir.path) {
                try? fileManager.removeItem(at: booksDir)
                Self.logger.debug("Cleared Books directory")
            }
        }
    }

    /// Clears all app data including Application Support (vectors, chunks, concepts) and UserDefaults
    /// Used for integration tests that need a completely clean state
    private func clearAllAppData() {
        let fileManager = FileManager.default

        // Clear UserDefaults
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        UserDefaults.standard.synchronize()
        Self.logger.debug("Cleared UserDefaults")

        // Clear Application Support directory contents
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let readerDir = appSupport.appendingPathComponent("com.splap.reader")
            let booksDir = appSupport.appendingPathComponent("Books")

            // Clear vectors directory
            let vectorsDir = readerDir.appendingPathComponent("vectors")
            if fileManager.fileExists(atPath: vectorsDir.path) {
                try? fileManager.removeItem(at: vectorsDir)
                Self.logger.debug("Cleared vectors directory")
            }

            // Clear chunks database
            let chunksDB = readerDir.appendingPathComponent("chunks.sqlite")
            if fileManager.fileExists(atPath: chunksDB.path) {
                try? fileManager.removeItem(at: chunksDB)
                Self.logger.debug("Cleared chunks database")
            }

            // Clear concept maps
            let conceptsDir = readerDir.appendingPathComponent("concepts")
            if fileManager.fileExists(atPath: conceptsDir.path) {
                try? fileManager.removeItem(at: conceptsDir)
                Self.logger.debug("Cleared concepts directory")
            }

            // Clear imported books
            if fileManager.fileExists(atPath: booksDir.path) {
                try? fileManager.removeItem(at: booksDir)
                Self.logger.debug("Cleared Books directory")
            }
        }

        // Clear Documents/TestBooks to force re-import
        if let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let testBooksDir = documentsDir.appendingPathComponent("TestBooks")
            if fileManager.fileExists(atPath: testBooksDir.path) {
                try? fileManager.removeItem(at: testBooksDir)
                Self.logger.debug("Cleared TestBooks directory")
            }
        }

        Self.logger.info("All app data cleared successfully")
    }

    // MARK: - Bundled Books

    private func copyBundledBooksIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "BundledBooksInstalled") else { return }

        let bundledBooks = ["frankenstein", "meditations", "the-metamorphosis"]
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let testBooksURL = documentsURL.appendingPathComponent("TestBooks")

        try? FileManager.default.createDirectory(at: testBooksURL, withIntermediateDirectories: true)

        for bookName in bundledBooks {
            // Resources are flattened in the bundle
            if let bundleURL = Bundle.main.url(forResource: bookName, withExtension: "epub") {
                let destURL = testBooksURL.appendingPathComponent("\(bookName).epub")
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    try? FileManager.default.copyItem(at: bundleURL, to: destURL)
                    Self.logger.debug("Copied bundled book: \(bookName)")
                }
            } else {
                Self.logger.warning("Bundled book not found: \(bookName)")
            }
        }

        defaults.set(true, forKey: "BundledBooksInstalled")
    }

    // MARK: - Test Helpers

    private func importTestBooksIfNeeded() {
        // Use the library service's scanTestBooks which handles deduplication
        BookLibraryService.shared.scanTestBooks()

        // Notify library view to refresh
        NotificationCenter.default.post(
            name: .bookLibraryDidChange,
            object: nil
        )
    }

    // MARK: - Argument Parsing

    private static func parseArgument(_ prefix: String) -> String? {
        for arg in CommandLine.arguments where arg.hasPrefix(prefix) {
            return String(arg.dropFirst(prefix.count))
        }
        return nil
    }

    private static func parseIntArgument(_ prefix: String) -> Int? {
        guard let stringValue = parseArgument(prefix) else { return nil }
        return Int(stringValue)
    }

    private func findBookBySlug(_ slug: String) -> Book? {
        let books = BookLibraryService.shared.getAllBooks()
        // Try exact match on lowercased slug first (e.g., "frankenstein" -> "Frankenstein...")
        let slugLower = slug.lowercased()
        return books.first { book in
            book.title.lowercased().contains(slugLower)
        }
    }

    // MARK: - Screenshot Mode

    private func handleScreenshotMode() -> Bool {
        Self.logger.info("Screenshot mode activated")

        // Parse screenshot arguments
        guard let bookSlug = Self.parseArgument("--screenshot-book=") else {
            Self.logger.error("--screenshot-book= is required")
            exit(1)
        }

        guard let outputPath = Self.parseArgument("--screenshot-output=") else {
            Self.logger.error("--screenshot-output= is required")
            exit(1)
        }

        // Parse optional chapter/cfi/font-scale (renderer arg ignored, WebView only)
        let chapterIndex = Self.parseIntArgument("--screenshot-chapter=")
        let cfiString = Self.parseArgument("--screenshot-cfi=")
        _ = Self.parseArgument("--screenshot-renderer=") // Ignored, native renderer removed
        let fontScaleArg = Self.parseArgument("--screenshot-font-scale=")

        Self.logger.info("Screenshot config: book=\(bookSlug), chapter=\(String(describing: chapterIndex)), cfi=\(String(describing: cfiString)), output=\(outputPath)")

        // Copy bundled books and scan for test books
        copyBundledBooksIfNeeded()
        importTestBooksIfNeeded()

        // Find the book
        guard let book = findBookBySlug(bookSlug) else {
            Self.logger.error("Book not found: \(bookSlug)")
            exit(1)
        }

        // Determine spine item index
        var spineItemIndex: Int?
        if let chapter = chapterIndex {
            spineItemIndex = chapter
        } else if let cfi = cfiString {
            if let parsed = CFIParser.parseBaseCFI(cfi) {
                spineItemIndex = parsed.spineIndex
                Self.logger.info("Parsed CFI '\(cfi)' -> spine index \(parsed.spineIndex)")
            } else {
                Self.logger.error("Invalid CFI format: \(cfi)")
                exit(1)
            }
        }

        // Set font scale if specified (default 1.0 for consistent comparison)
        if let fontScaleStr = fontScaleArg, let scale = Double(fontScaleStr) {
            ReaderPreferences.shared.fontScale = CGFloat(scale)
            Self.logger.debug("Font scale set to \(scale)")
        } else {
            // Default to 1.0 for screenshot mode to match reference
            ReaderPreferences.shared.fontScale = 1.0
            Self.logger.debug("Font scale defaulting to 1.0")
        }

        // Create window
        let window = UIWindow(frame: UIScreen.main.bounds)

        // Apply dark mode for consistent screenshots
        window.overrideUserInterfaceStyle = .dark

        // Create reader view controller
        let fileURL = BookLibraryService.shared.getFileURL(for: book)
        let readerVC = ReaderViewController(
            epubURL: fileURL,
            bookId: book.id.uuidString,
            bookTitle: book.title,
            bookAuthor: book.author,
            initialSpineItemIndex: spineItemIndex
        )

        let navController = UINavigationController(rootViewController: readerVC)
        window.rootViewController = navController
        window.makeKeyAndVisible()
        self.window = window

        // Listen for render ready notification
        screenshotObserver = NotificationCenter.default.addObserver(
            forName: ReaderPreferences.readerRenderReadyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.captureScreenshot(outputPath: outputPath)
        }

        Self.logger.info("Waiting for render ready...")
        return true
    }

    private func captureScreenshot(outputPath: String) {
        Self.logger.info("Render ready, capturing screenshot...")

        // Remove observer
        if let observer = screenshotObserver {
            NotificationCenter.default.removeObserver(observer)
            screenshotObserver = nil
        }

        // Small delay to ensure rendering is fully complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let window = self.window else {
                Self.logger.error("No window available")
                exit(1)
            }

            // Capture the window content
            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            let image = renderer.image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }

            // Save to file
            guard let pngData = image.pngData() else {
                Self.logger.error("Failed to create PNG data")
                exit(1)
            }

            let outputURL = URL(fileURLWithPath: outputPath)
            do {
                // Create directory if needed
                let directory = outputURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

                try pngData.write(to: outputURL)
                Self.logger.info("Screenshot saved to: \(outputPath)")
                exit(0)
            } catch {
                Self.logger.error("Failed to save screenshot: \(error)")
                exit(1)
            }
        }
    }
}
