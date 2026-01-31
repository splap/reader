import Combine
import Foundation
import OSLog
import ReaderCore
import UIKit

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

    @Published var currentPageIndex: Int = 0
    @Published var totalPages: Int = 0
    @Published var fontScale: CGFloat = FontScaleManager.shared.fontScale
    @Published var settingsPresented: Bool = false

    // CFI-based position tracking
    @Published var currentCFI: String?
    @Published var currentSpineIndex: Int = 0

    // Global page count tracking
    @Published var globalPageCountStatus: BackgroundPageCounter.Status = .idle
    private var pageCounterCancellable: AnyCancellable?

    private let cfiPositionStore: CFIPositionStoring
    let chapterId: String
    let bookId: String

    // Initial CFI to navigate to after content loads
    private(set) var initialCFI: String?

    // Background page counter (initialized when counting starts)
    private(set) var pageCounter: BackgroundPageCounter?

    init(
        chapter: Chapter,
        bookId: String? = nil,
        cfiPositionStore: CFIPositionStoring = UserDefaultsCFIPositionStore()
    ) {
        self.cfiPositionStore = cfiPositionStore
        chapterId = chapter.id
        self.bookId = bookId ?? chapter.id

        Self.debugLog("ReaderViewModel init for bookId: \(self.bookId)")

        // Load CFI position
        if let cfiPosition = cfiPositionStore.load(bookId: self.bookId) {
            Self.logger.info("CFI LOAD: found position \(cfiPosition.cfi)")
            Self.debugLog("Loaded CFI position: \(cfiPosition.cfi)")
            initialCFI = cfiPosition.cfi
            currentCFI = cfiPosition.cfi
            if let parsed = CFIParser.parseFullCFI(cfiPosition.cfi) {
                currentSpineIndex = parsed.spineIndex
            }
        } else {
            Self.logger.info("CFI LOAD: no saved position for bookId=\(self.bookId)")
            Self.debugLog("No saved position, starting at beginning")
        }
    }

    func updateCurrentPage(_ index: Int, totalPages: Int = 0) {
        currentPageIndex = index
        if totalPages > 0 {
            self.totalPages = totalPages
        }
    }

    func navigateToPage(_ pageIndex: Int) {
        guard pageIndex >= 0, pageIndex < totalPages else { return }
        currentPageIndex = pageIndex
    }

    func updateFontScale(_ scale: CGFloat) {
        fontScale = scale
        FontScaleManager.shared.fontScale = scale
    }

    // MARK: - CFI Position Tracking

    /// Update and save the current CFI position
    func updateCFIPosition(cfi: String, spineIndex: Int) {
        guard cfi != currentCFI else { return }

        currentCFI = cfi
        currentSpineIndex = spineIndex

        Self.logger.info("CFI SAVE: bookId=\(bookId) cfi=\(cfi)")
        Self.debugLog("📍 Saving CFI: \(cfi)")

        let position = CFIPosition(bookId: bookId, cfi: cfi, maxCfi: nil)
        cfiPositionStore.save(position)
    }

    /// Update spine index when navigating between spine items
    func setCurrentSpineIndex(_ index: Int) {
        currentSpineIndex = index
    }

    // MARK: - Global Page Count

    /// Start background page counting for the book
    /// - Parameters:
    ///   - htmlSections: The HTML sections (spine items) to count
    ///   - layoutKey: Current layout configuration
    @MainActor
    func startGlobalPageCounting(htmlSections: [HTMLSection], layoutKey: LayoutKey) {
        let counter = BackgroundPageCounter()
        pageCounter = counter

        // Subscribe to status updates
        pageCounterCancellable = counter.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.globalPageCountStatus = status
            }

        counter.startCounting(
            htmlSections: htmlSections,
            bookId: bookId,
            layoutKey: layoutKey
        )

        Self.logger.info("Started global page counting for \(htmlSections.count) spine items")
    }

    /// Cancel any in-progress page counting
    @MainActor
    func cancelGlobalPageCounting() {
        pageCounter?.cancel()
        pageCounter = nil
        pageCounterCancellable = nil
    }

    /// Get the global page number (1-indexed) for the current position
    /// Returns nil if counting is not complete
    var globalCurrentPage: Int? {
        guard case let .complete(pageCounts) = globalPageCountStatus else {
            return nil
        }
        return pageCounts.globalPage(spineIndex: currentSpineIndex, localPage: currentPageIndex)
    }

    /// Get the total number of pages in the book
    /// Returns nil if counting is not complete
    var globalTotalPages: Int? {
        guard case let .complete(pageCounts) = globalPageCountStatus else {
            return nil
        }
        return pageCounts.totalPages
    }

    /// Check if page counting is in progress
    var isCountingPages: Bool {
        if case .counting = globalPageCountStatus {
            return true
        }
        return false
    }
}
