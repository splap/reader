import Foundation
import ReaderCore
import UIKit
import OSLog

struct LLMPayload: Identifiable {
    let id = UUID()
    let selection: SelectionPayload
}

final class ReaderViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.example.reader", category: "paging")

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
    @Published var totalPages: Int = 0  // For WebView mode
    @Published var maxReadPageIndex: Int = 0  // Furthest page user has reached
    @Published var fontScale: CGFloat = FontScaleManager.shared.fontScale
    @Published var settingsPresented: Bool = false
    @Published var llmPayload: LLMPayload?

    // Block-based position tracking
    @Published var currentBlockId: String?
    @Published var currentSpineItemId: String?

    private let engine: TextEngine
    private let positionStore: ReaderPositionStoring
    private let blockPositionStore: BlockPositionStoring
    let chapterId: String
    let bookId: String  // For block position storage
    private var lastPageSize: CGSize = .zero
    private var lastInsets: UIEdgeInsets = .zero
    private var positionOffset: Int = 0

    // Initial page to navigate to after content loads (for position restoration)
    private(set) var initialPageIndex: Int = 0

    // Initial block ID to navigate to after content loads (preferred over page)
    private(set) var initialBlockId: String?
    private(set) var initialSpineItemId: String?

    init(
        chapter: Chapter,
        bookId: String? = nil,
        positionStore: ReaderPositionStoring = UserDefaultsPositionStore(),
        blockPositionStore: BlockPositionStoring = UserDefaultsBlockPositionStore()
    ) {
        self.engine = TextEngine(chapter: chapter)
        self.positionStore = positionStore
        self.blockPositionStore = blockPositionStore
        self.chapterId = chapter.id
        self.bookId = bookId ?? chapter.id  // Fall back to chapterId if no bookId provided

        Self.debugLog("📍 ReaderViewModel init for chapter: \(chapter.id), bookId: \(self.bookId)")

        // Try to load block-based position first (preferred)
        if let blockPosition = blockPositionStore.load(bookId: self.bookId) {
            Self.debugLog("📍 Loaded block position: spineItem=\(blockPosition.spineItemId), block=\(blockPosition.blockId)")
            initialBlockId = blockPosition.blockId
            initialSpineItemId = blockPosition.spineItemId
            currentBlockId = blockPosition.blockId
            currentSpineItemId = blockPosition.spineItemId
        }
        // Fall back to legacy page-based position
        else if let position = positionStore.load(chapterId: chapter.id) {
            Self.debugLog("📍 Loaded legacy position: page \(position.pageIndex), max \(position.maxReadPageIndex)")
            positionOffset = position.characterOffset
            currentPageIndex = position.pageIndex
            maxReadPageIndex = position.maxReadPageIndex
            initialPageIndex = position.pageIndex
        } else {
            Self.debugLog("📍 No saved position found for chapter: \(chapter.id)")
        }
    }

    func updateLayout(pageSize: CGSize, insets: UIEdgeInsets) {
        guard pageSize != .zero else { return }

        lastPageSize = pageSize
        lastInsets = insets

        let result = engine.paginate(pageSize: pageSize, insets: insets, fontScale: fontScale)
        pages = result.pages

        currentPageIndex = engine.pageIndex(for: positionOffset, in: pages)
#if DEBUG
        Self.logger.debug(
            "paginate size=\(pageSize.width, privacy: .public)x\(pageSize.height, privacy: .public) pages=\(self.pages.count, privacy: .public)"
        )
        for (index, page) in pages.prefix(5).enumerated() {
            Self.logger.debug(
                "page \(index, privacy: .public) planned=\(page.range.location, privacy: .public)+\(page.range.length, privacy: .public)"
            )
        }
#endif
    }

    func updateCurrentPage(_ index: Int, totalPages: Int = 0) {
        currentPageIndex = index
        if totalPages > 0 {
            self.totalPages = totalPages
        }

        // Update max read extent if this is further than before
        if index > maxReadPageIndex {
            maxReadPageIndex = index
        }

        // Save position for TextKit mode
        if !pages.isEmpty && index < pages.count {
            positionOffset = pages[index].range.location
            positionStore.save(ReaderPosition(
                chapterId: chapterId,
                pageIndex: index,
                characterOffset: positionOffset,
                maxReadPageIndex: maxReadPageIndex
            ))
        } else {
            // WebView mode - save position without character offset
            Self.debugLog("📍 Saving position: chapter=\(chapterId), page=\(index), maxRead=\(maxReadPageIndex)")
            positionStore.save(ReaderPosition(
                chapterId: chapterId,
                pageIndex: index,
                characterOffset: 0,
                maxReadPageIndex: maxReadPageIndex
            ))
        }
    }

    // Navigate to a specific page (used by scrubber)
    func navigateToPage(_ pageIndex: Int) {
        guard pageIndex >= 0 && pageIndex < totalPages else { return }
        // Don't update maxReadPageIndex here - that only advances when scrolling forward
        currentPageIndex = pageIndex
    }

    func updateFontScale(_ scale: CGFloat) {
        fontScale = scale
        FontScaleManager.shared.fontScale = scale  // Persist to UserDefaults
        updateLayout(pageSize: lastPageSize, insets: lastInsets)
    }

    func presentSelection(range: NSRange) {
        // Note: This function is currently unused with isolated text systems
        // Selection is handled directly in PageTextView via page.textStorage
    }

    func navigateToNextPage() {
        guard currentPageIndex < pages.count - 1 else { return }
        currentPageIndex += 1
    }

    func navigateToPreviousPage() {
        guard currentPageIndex > 0 else { return }
        currentPageIndex -= 1
    }

    // MARK: - Block Position Tracking

    /// Update the current block position (called from WebView on scroll-end)
    /// - Parameters:
    ///   - blockId: The ID of the first visible block
    ///   - spineItemId: The spine item containing the block (optional, uses current if nil)
    func updateBlockPosition(blockId: String, spineItemId: String? = nil) {
        let effectiveSpineItemId = spineItemId ?? currentSpineItemId ?? ""

        // Only save if position actually changed
        guard blockId != currentBlockId || effectiveSpineItemId != currentSpineItemId else {
            return
        }

        currentBlockId = blockId
        currentSpineItemId = effectiveSpineItemId

        Self.debugLog("📍 Saving block position: bookId=\(bookId), spineItem=\(effectiveSpineItemId), block=\(blockId)")

        let position = BlockPosition(
            bookId: bookId,
            spineItemId: effectiveSpineItemId,
            blockId: blockId,
            maxBlockId: nil,  // TODO: Track max progress
            maxSpineItemId: nil
        )

        blockPositionStore.save(position)
    }

    /// Set the current spine item ID (called when loading a new section)
    func setCurrentSpineItem(_ spineItemId: String) {
        currentSpineItemId = spineItemId
    }
}
