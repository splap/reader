import Foundation
import ReaderUI
import ReaderCore
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NSLog("🚀 ReaderApp launched! Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "unknown")")
        NSLog("🚀 Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")

        // Clear state if running UI tests unless explicitly told to keep state.
        let isUITesting = CommandLine.arguments.contains("--uitesting")
        let keepUIState = CommandLine.arguments.contains("--uitesting-keep-state")
        let isPositionTest = CommandLine.arguments.contains("--uitesting-position-test")
        let useWebView = CommandLine.arguments.contains("--uitesting-webview")
        let cleanAllData = CommandLine.arguments.contains("--uitesting-clean-all-data")
        let uitestingBook = Self.parseArgument("--uitesting-book=")
        let uitestingSpineItem = Self.parseIntArgument("--uitesting-spine-item=")

        if isUITesting && cleanAllData {
            NSLog("🧪 UI Testing mode - clearing ALL app data (Application Support + UserDefaults)")
            clearAllAppData()
        } else if isUITesting && !keepUIState {
            NSLog("🧪 UI Testing mode detected - clearing app state")
            clearAppStateForTesting()
        }

        // Set render mode for UI testing
        if useWebView {
            ReaderPreferences.shared.renderMode = .webView
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
            NSLog("🚀 UI test opening book by slug: \(bookSlug) -> \(book.title)")
            BookLibraryService.shared.updateLastOpened(bookId: book.id)
            let fileURL = BookLibraryService.shared.getFileURL(for: book)
            let readerVC = ReaderViewController(
                epubURL: fileURL,
                bookId: book.id.uuidString,
                bookTitle: book.title,
                bookAuthor: book.author,
                initialSpineItemIndex: uitestingSpineItem
            )
            navController.pushViewController(readerVC, animated: false)
        } else if autoOpenFirstBook, let book = BookLibraryService.shared.getAllBooks().first {
            NSLog("🚀 UI test auto-opening first book: \(book.title)")
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
                  let book = BookLibraryService.shared.getBook(id: uuid) {
            NSLog("🚀 Auto-opening last book: \(book.title)")

            let fileURL = BookLibraryService.shared.getFileURL(for: book)
            let readerVC = ReaderViewController(
                epubURL: fileURL,
                bookId: book.id.uuidString,
                bookTitle: book.title,
                bookAuthor: book.author
            )
            navController.pushViewController(readerVC, animated: false)
        } else {
            NSLog("🚀 Showing library")
        }

        window.rootViewController = navController
        window.makeKeyAndVisible()
        self.window = window

        return true
    }

    // Handle file opens from outside the app (AirDrop, Files, Share)
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
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
            print("Failed to import EPUB from external source: \(error)")
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
                NSLog("🧪 Cleared Books directory")
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
        NSLog("🧪 Cleared UserDefaults")

        // Clear Application Support directory contents
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let readerDir = appSupport.appendingPathComponent("com.splap.reader")
            let booksDir = appSupport.appendingPathComponent("Books")

            // Clear vectors directory
            let vectorsDir = readerDir.appendingPathComponent("vectors")
            if fileManager.fileExists(atPath: vectorsDir.path) {
                try? fileManager.removeItem(at: vectorsDir)
                NSLog("🧪 Cleared vectors directory")
            }

            // Clear chunks database
            let chunksDB = readerDir.appendingPathComponent("chunks.sqlite")
            if fileManager.fileExists(atPath: chunksDB.path) {
                try? fileManager.removeItem(at: chunksDB)
                NSLog("🧪 Cleared chunks database")
            }

            // Clear concept maps
            let conceptsDir = readerDir.appendingPathComponent("concepts")
            if fileManager.fileExists(atPath: conceptsDir.path) {
                try? fileManager.removeItem(at: conceptsDir)
                NSLog("🧪 Cleared concepts directory")
            }

            // Clear imported books
            if fileManager.fileExists(atPath: booksDir.path) {
                try? fileManager.removeItem(at: booksDir)
                NSLog("🧪 Cleared Books directory")
            }
        }

        // Clear Documents/TestBooks to force re-import
        if let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let testBooksDir = documentsDir.appendingPathComponent("TestBooks")
            if fileManager.fileExists(atPath: testBooksDir.path) {
                try? fileManager.removeItem(at: testBooksDir)
                NSLog("🧪 Cleared TestBooks directory")
            }
        }

        NSLog("🧪 All app data cleared successfully")
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
                    NSLog("📚 Copied bundled book: \(bookName)")
                }
            } else {
                NSLog("⚠️ Bundled book not found: \(bookName)")
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
}
