import Foundation
import ReaderCore
import UIKit
import OSLog

final class ReaderViewModel: ObservableObject {
    private static let logger = Log.logger(category: "paging")

    private static func debugLog(_ message: String) {
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("reader-position-debug.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] \(message)\n"
        if let data = entry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    @Published var pages: [Page] = []
    @Published var currentPageIndex: Int = 0
    @Published var totalPages: Int = 0
    @Published var fontScale: CGFloat = FontScaleManager.shared.fontScale
    @Published var settingsPresented: Bool = false

    // CFI-based position tracking
    @Published var currentCFI: String?
    @Published var currentSpineIndex: Int = 0

    private let engine: TextEngine
    private let cfiPositionStore: CFIPositionStoring
    let chapterId: String
    let bookId: String
    private var lastPageSize: CGSize = .zero
    private var lastInsets: UIEdgeInsets = .zero

    // Initial CFI to navigate to after content loads
    private(set) var initialCFI: String?

    init(
        chapter: Chapter,
        bookId: String? = nil,
        cfiPositionStore: CFIPositionStoring = UserDefaultsCFIPositionStore()
    ) {
        self.engine = TextEngine(chapter: chapter)
        self.cfiPositionStore = cfiPositionStore
        self.chapterId = chapter.id
        self.bookId = bookId ?? chapter.id

        Self.debugLog("📍 ReaderViewModel init for bookId: \(self.bookId)")

        // Load CFI position
        if let cfiPosition = cfiPositionStore.load(bookId: self.bookId) {
            Self.logger.info("CFI LOAD: found position \(cfiPosition.cfi)")
            Self.debugLog("📍 Loaded CFI position: \(cfiPosition.cfi)")
            initialCFI = cfiPosition.cfi
            currentCFI = cfiPosition.cfi
            if let parsed = CFIParser.parseFullCFI(cfiPosition.cfi) {
                currentSpineIndex = parsed.spineIndex
            }
        } else {
            Self.logger.info("CFI LOAD: no saved position for bookId=\(self.bookId)")
            Self.debugLog("📍 No saved position, starting at beginning")
        }
    }

    func updateLayout(pageSize: CGSize, insets: UIEdgeInsets) {
        guard pageSize != .zero else { return }

        lastPageSize = pageSize
        lastInsets = insets

        let result = engine.paginate(pageSize: pageSize, insets: insets, fontScale: fontScale)
        pages = result.pages

#if DEBUG
        Self.logger.debug(
            "paginate size=\(pageSize.width)x\(pageSize.height) pages=\(self.pages.count)"
        )
#endif
    }

    func updateCurrentPage(_ index: Int, totalPages: Int = 0) {
        currentPageIndex = index
        if totalPages > 0 {
            self.totalPages = totalPages
        }
    }

    func navigateToPage(_ pageIndex: Int) {
        guard pageIndex >= 0 && pageIndex < totalPages else { return }
        currentPageIndex = pageIndex
    }

    func updateFontScale(_ scale: CGFloat) {
        fontScale = scale
        FontScaleManager.shared.fontScale = scale
        updateLayout(pageSize: lastPageSize, insets: lastInsets)
    }

    func navigateToNextPage() {
        guard currentPageIndex < pages.count - 1 else { return }
        currentPageIndex += 1
    }

    func navigateToPreviousPage() {
        guard currentPageIndex > 0 else { return }
        currentPageIndex -= 1
    }

    // MARK: - CFI Position Tracking

    /// Update and save the current CFI position
    func updateCFIPosition(cfi: String, spineIndex: Int) {
        guard cfi != currentCFI else { return }

        currentCFI = cfi
        currentSpineIndex = spineIndex

        Self.logger.info("CFI SAVE: bookId=\(self.bookId) cfi=\(cfi)")
        Self.debugLog("📍 Saving CFI: \(cfi)")

        let position = CFIPosition(bookId: bookId, cfi: cfi, maxCfi: nil)
        cfiPositionStore.save(position)
    }

    /// Update spine index when navigating between spine items
    func setCurrentSpineIndex(_ index: Int) {
        currentSpineIndex = index
    }
}
