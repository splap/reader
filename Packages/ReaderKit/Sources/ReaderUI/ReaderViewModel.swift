import Foundation
import ReaderCore
import UIKit
import OSLog

final class ReaderViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.example.reader", category: "paging")
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
        ensureTextContainerOrder()

        currentPageIndex = engine.pageIndex(for: positionOffset, in: pages)
#if DEBUG
        Self.logger.debug(
            "paginate size=\(pageSize.width, privacy: .public)x\(pageSize.height, privacy: .public) pages=\(self.pages.count, privacy: .public) textLength=\(self.textStorage?.length ?? 0, privacy: .public)"
        )
#endif
    }

    func updateCurrentPage(_ index: Int) {
        guard index >= 0 && index < pages.count else { return }
        ensureTextContainerOrder()
        positionOffset = pages[index].range.location
        positionStore.save(ReaderPosition(
            chapterId: chapterId,
            pageIndex: index,
            characterOffset: positionOffset
        ))
#if DEBUG
        verifyTextContainerMapping(for: index)
#endif
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

#if DEBUG
    private func verifyTextContainerMapping(for index: Int) {
        guard let layoutManager else { return }
        let page = pages[index]
        let actualRange = page.actualCharacterRange(using: layoutManager)
        if actualRange.length == 0 {
            Self.logger.error(
                "page \(index, privacy: .public) text container mapped to empty range planned=\(page.range.location, privacy: .public)+\(page.range.length, privacy: .public)"
            )
        } else {
            Self.logger.debug(
                "page \(index, privacy: .public) text container range=\(actualRange.location, privacy: .public)+\(actualRange.length, privacy: .public)"
            )
        }
    }

    private func ensureTextContainerOrder() {
        guard let layoutManager, !pages.isEmpty else { return }

        let containers = layoutManager.textContainers
        var needsRebuild = containers.count != pages.count

        if !needsRebuild {
            for (index, page) in pages.enumerated() {
                if containers[index] !== page.textContainer {
                    needsRebuild = true
                    break
                }
            }
        }

        guard needsRebuild else { return }

        while !layoutManager.textContainers.isEmpty {
            layoutManager.removeTextContainer(at: layoutManager.textContainers.count - 1)
        }
        for page in pages {
            layoutManager.addTextContainer(page.textContainer)
        }

#if DEBUG
        Self.logger.debug(
            "rebuild layoutManager containers count=\(layoutManager.textContainers.count, privacy: .public) pages=\(self.pages.count, privacy: .public)"
        )
#endif
    }
#endif
}
