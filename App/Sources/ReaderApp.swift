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
        if isUITesting && !keepUIState {
            NSLog("🧪 UI Testing mode detected - clearing app state")
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
            UserDefaults.standard.synchronize()
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

    // MARK: - Bundled Books

    private func copyBundledBooksIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "BundledBooksInstalled") else { return }

        let bundledBooks = ["frankenstein", "meditations", "the-metamorphosis"]
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let testBooksURL = documentsURL.appendingPathComponent("TestBooks")

        try? FileManager.default.createDirectory(at: testBooksURL, withIntermediateDirectories: true)

        for bookName in bundledBooks {
            if let bundleURL = Bundle.main.url(forResource: bookName, withExtension: "epub") {
                let destURL = testBooksURL.appendingPathComponent("\(bookName).epub")
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    try? FileManager.default.copyItem(at: bundleURL, to: destURL)
                }
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
}
