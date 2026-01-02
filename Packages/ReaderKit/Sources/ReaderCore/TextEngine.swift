import Foundation
import UIKit

public struct PaginationResult {
    public let pages: [Page]
    public let layoutManager: NSLayoutManager
    public let textStorage: NSTextStorage

    public init(pages: [Page], layoutManager: NSLayoutManager, textStorage: NSTextStorage) {
        self.pages = pages
        self.layoutManager = layoutManager
        self.textStorage = textStorage
    }
}

public final class TextEngine {
    private struct InsetsKey: Hashable {
        let top: CGFloat
        let left: CGFloat
        let bottom: CGFloat
        let right: CGFloat

        init(_ insets: UIEdgeInsets) {
            top = insets.top
            left = insets.left
            bottom = insets.bottom
            right = insets.right
        }
    }

    private struct PaginationKey: Hashable {
        let chapterId: String
        let pageSize: CGSize
        let insets: InsetsKey
        let fontScale: CGFloat
    }

    public let chapter: Chapter
    private var cache: [PaginationKey: PaginationResult] = [:]
    private var scaledTextCache: [CGFloat: NSAttributedString] = [:]

    public init(chapter: Chapter) {
        self.chapter = chapter
    }

    public func paginate(pageSize: CGSize, insets: UIEdgeInsets, fontScale: CGFloat) -> PaginationResult {
        let key = PaginationKey(
            chapterId: chapter.id,
            pageSize: pageSize,
            insets: InsetsKey(insets),
            fontScale: fontScale
        )
        if let cachedResult = cache[key] {
            return cachedResult
        }

        let availableSize = CGSize(
            width: max(1, pageSize.width - insets.left - insets.right),
            height: max(1, pageSize.height - insets.top - insets.bottom)
        )
        if availableSize.width <= 1 || availableSize.height <= 1 {
            let result = PaginationResult(pages: [], layoutManager: NSLayoutManager(), textStorage: NSTextStorage())
            cache[key] = result
            return result
        }

        let textStorage = NSTextStorage(attributedString: scaledAttributedString(for: fontScale))
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = false
        textStorage.addLayoutManager(layoutManager)

        var pages: [Page] = []
        var lastRange = NSRange(location: 0, length: 0)

        while NSMaxRange(lastRange) < textStorage.length {
            let textContainer = NSTextContainer(size: availableSize)
            textContainer.lineFragmentPadding = 0
            layoutManager.addTextContainer(textContainer)

            let glyphRange = layoutManager.glyphRange(for: textContainer)
            let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let rangeEnd = NSMaxRange(characterRange)
            let previousEnd = NSMaxRange(lastRange)

            if characterRange.length == 0 || rangeEnd <= previousEnd {
                break
            }

            let pageIndex = pages.count
            pages.append(
                Page(
                    id: pageIndex,
                    containerIndex: pageIndex,
                    range: characterRange,
                    textContainer: textContainer
                )
            )

            lastRange = characterRange
        }

        let result = PaginationResult(pages: pages, layoutManager: layoutManager, textStorage: textStorage)
        cache[key] = result
        return result
    }

    public func pageIndex(for characterOffset: Int, in pages: [Page]) -> Int {
        guard !pages.isEmpty else { return 0 }

        let clampedOffset = max(0, characterOffset)
        for (index, page) in pages.enumerated() {
            if NSLocationInRange(clampedOffset, page.range) {
                return index
            }
            if clampedOffset < page.range.location {
                return index
            }
        }

        return max(0, pages.count - 1)
    }

    private func scaledAttributedString(for fontScale: CGFloat) -> NSAttributedString {
        if let cached = scaledTextCache[fontScale] {
            return cached
        }

        guard fontScale != 1.0 else {
            let base = chapter.attributedText
            scaledTextCache[fontScale] = base
            return base
        }

        let scaled = NSMutableAttributedString(attributedString: chapter.attributedText)
        scaled.enumerateAttribute(.font, in: NSRange(location: 0, length: scaled.length)) { value, range, _ in
            guard let font = value as? UIFont else { return }
            let scaledFont = font.withSize(font.pointSize * fontScale)
            scaled.addAttribute(.font, value: scaledFont, range: range)
        }

        scaledTextCache[fontScale] = scaled
        return scaled
    }
}
