import Foundation
import ReaderUI
import SwiftUI
import UIKit

@main
struct ReaderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ReaderRootView()
        }
    }
}

private struct ReaderRootView: UIViewControllerRepresentable {
    private let epubURL = ReaderAppEnvironment.epubURL()

    func makeUIViewController(context: Context) -> UINavigationController {
        let readerVC: ReaderViewController
        if let epubURL {
            readerVC = ReaderViewController(epubURL: epubURL)
        } else {
            readerVC = ReaderViewController()
        }
        let navController = UINavigationController(rootViewController: readerVC)
        return navController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // No updates needed
    }
}

private enum ReaderAppEnvironment {
    static func epubURL() -> URL? {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let epubURL = documentsURL.appendingPathComponent("Imported.epub")
        return FileManager.default.fileExists(atPath: epubURL.path) ? epubURL : nil
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }
}
