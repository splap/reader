import Foundation
import ReaderUI
import ReaderCore
import SwiftUI
import UIKit

@main
struct ReaderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var lastOpenedBookId: UUID?

    init() {
        // Load last opened book ID from UserDefaults
        if let idString = UserDefaults.standard.string(forKey: "reader.lastOpenedBookId"),
           let uuid = UUID(uuidString: idString) {
            _lastOpenedBookId = State(initialValue: uuid)
        }
    }

    var body: some Scene {
        WindowGroup {
            // Smart navigation: auto-open last book if available, otherwise show library
            if let bookId = lastOpenedBookId,
               let book = BookLibraryService.shared.getBook(id: bookId) {
                ReaderContainerView(book: book)
            } else {
                LibraryView()
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
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
