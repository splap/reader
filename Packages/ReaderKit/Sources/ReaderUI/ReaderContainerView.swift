import SwiftUI
import UIKit
import ReaderCore

public struct ReaderContainerView: UIViewControllerRepresentable {
    let book: Book

    public init(book: Book) {
        self.book = book
    }

    public func makeUIViewController(context: Context) -> UINavigationController {
        let fileURL = BookLibraryService.shared.getFileURL(for: book)
        let readerVC = ReaderViewController(epubURL: fileURL)

        // Update last opened date
        BookLibraryService.shared.updateLastOpened(bookId: book.id)

        let navController = UINavigationController(rootViewController: readerVC)
        return navController
    }

    public func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
