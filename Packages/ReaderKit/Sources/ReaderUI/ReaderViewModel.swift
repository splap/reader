import Foundation
import ReaderCore
import UIKit

final class ReaderViewModel: ObservableObject {
    @Published var pages: [Page] = []
    @Published var layoutManager: NSLayoutManager?
    @Published var textStorage: NSTextStorage?
    @Published var currentPageIndex: Int = 0
    @Published var fontScale: CGFloat = 1.0
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
        layoutManager = result.layoutManager
        textStorage = result.textStorage

        currentPageIndex = engine.pageIndex(for: positionOffset, in: pages)
    }

    func updateCurrentPage(_ index: Int) {
        guard index >= 0 && index < pages.count else { return }
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
        guard let textStorage else { return }
        let selection = SelectionExtractor.payload(in: textStorage, range: range)
        llmPayload = LLMPayload(selection: selection)
    }
}
