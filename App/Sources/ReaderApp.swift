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

        // Create window
        let window = UIWindow(frame: UIScreen.main.bounds)

        // Create library view controller
        let libraryVC = LibraryViewController()
        let navController = UINavigationController(rootViewController: libraryVC)

        // Check if we should auto-open last book
        if let idString = UserDefaults.standard.string(forKey: "reader.lastOpenedBookId"),
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
}
