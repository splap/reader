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
        if isUITesting && !keepUIState {
            NSLog("🧪 UI Testing mode detected - clearing app state")
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
            UserDefaults.standard.synchronize()

            // Import test books if they exist
            if !isPositionTest {
                importTestBooksIfNeeded()
            }
        }

        // Create window
        let window = UIWindow(frame: UIScreen.main.bounds)

        // Apply saved appearance (default: dark)
        let appearanceMode = UserDefaults.standard.object(forKey: "AppearanceMode") as? Int ?? 0
        switch appearanceMode {
        case 0: window.overrideUserInterfaceStyle = .dark
        case 1: window.overrideUserInterfaceStyle = .light
        default: window.overrideUserInterfaceStyle = .unspecified
        }

        // Create library view controller
        let libraryVC = LibraryViewController()
        let navController = UINavigationController(rootViewController: libraryVC)

        let autoOpenFirstBook = CommandLine.arguments.contains("--uitesting-auto-open-first-book")
        if isPositionTest {
            let chapter = UITestChapter.makePositionTestChapter(pageCount: 120)
            let readerVC = ReaderViewController(
                chapter: chapter,
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

    // MARK: - Test Helpers

    private func importTestBooksIfNeeded() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let testBooksURL = documentsURL.appendingPathComponent("TestBooks")

        guard FileManager.default.fileExists(atPath: testBooksURL.path) else {
            NSLog("🧪 No TestBooks directory found at: \(testBooksURL.path)")
            return
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: testBooksURL, includingPropertiesForKeys: nil)
            let epubFiles = files.filter { $0.pathExtension.lowercased() == "epub" }

            NSLog("🧪 Found \(epubFiles.count) test books to import")

            for epubURL in epubFiles {
                do {
                    let book = try BookLibraryService.shared.importBook(from: epubURL, startAccessing: false)
                    NSLog("🧪 Imported test book: \(book.title)")
                } catch {
                    NSLog("🧪 Failed to import test book \(epubURL.lastPathComponent): \(error)")
                }
            }

            // Notify library view to refresh
            NotificationCenter.default.post(
                name: .bookLibraryDidChange,
                object: nil
            )
        } catch {
            NSLog("🧪 Failed to read TestBooks directory: \(error)")
        }
    }
}
