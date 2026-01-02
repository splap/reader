import Foundation
import ReaderCore
import UIKit
import OSLog

final class ReaderViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.example.reader", category: "paging")
    @Published var pages: [Page] = []
    @Published var currentPageIndex: Int = 0
    @Published var fontScale: CGFloat = 1.4
    @Published var settingsPresented: Bool = false
    @Published var llmPayload: LLMPayload?

    private let engine: TextEngine
    private let positionStore: ReaderPositionStoring
    private let chapterId: String
    private var lastPageSize: CGSize = .zero
    private var lastInsets: UIEdgeInsets = .zero
    private var positionOffset: Int = 0

    init(chapter: Chapter, positionStore: ReaderPositionStoring = UserDefaultsPositionStore()) {
        self.engine = TextEngine(chapter: chapter)
        self.positionStore = positionStore
        self.chapterId = chapter.id

        if let position = positionStore.load(chapterId: chapter.id) {
            positionOffset = position.characterOffset
            currentPageIndex = position.pageIndex
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

    func updateCurrentPage(_ index: Int) {
        guard index >= 0 && index < pages.count else { return }
        currentPageIndex = index
        positionOffset = pages[index].range.location
        positionStore.save(ReaderPosition(
            chapterId: chapterId,
            pageIndex: index,
            characterOffset: positionOffset
        ))
    }

    func updateFontScale(_ scale: CGFloat) {
        fontScale = scale
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

}
