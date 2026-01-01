import Foundation
import ReaderUI
import SwiftUI

@main
struct ReaderApp: App {
    var body: some Scene {
        WindowGroup {
            ReaderRootView()
        }
    }
}

private struct ReaderRootView: View {
    private let epubURL = ReaderAppEnvironment.epubURL()

    var body: some View {
        if let epubURL {
            ReaderView(epubURL: epubURL)
        } else {
            ReaderView()
        }
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
