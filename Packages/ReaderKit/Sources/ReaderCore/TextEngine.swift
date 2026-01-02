import Foundation
import UIKit
import OSLog

public struct PaginationResult {
    public let pages: [Page]

    public init(pages: [Page]) {
        self.pages = pages
    }
}

public final class TextEngine {
    private static let logger = Logger(subsystem: "com.example.reader", category: "text-engine")

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
            let result = PaginationResult(pages: [])
            cache[key] = result
            return result
        }

        let fullText = scaledAttributedString(for: fontScale)

        // Step 1: Use temporary text system to calculate page ranges
        let tempStorage = NSTextStorage(attributedString: fullText)
        let tempLayoutManager = NSLayoutManager()
        tempLayoutManager.allowsNonContiguousLayout = false
        tempStorage.addLayoutManager(tempLayoutManager)

        Self.logger.info("📐 Calculating page ranges for \(tempStorage.length, privacy: .public) characters")

        var pageRanges: [NSRange] = []
        var lastRange = NSRange(location: 0, length: 0)

        while NSMaxRange(lastRange) < tempStorage.length {
            let tempContainer = NSTextContainer(size: availableSize)
            tempContainer.lineFragmentPadding = 0
            tempLayoutManager.addTextContainer(tempContainer)
            tempLayoutManager.ensureLayout(for: tempContainer)

            let glyphRange = tempLayoutManager.glyphRange(for: tempContainer)
            let characterRange = tempLayoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

            if characterRange.length == 0 || NSMaxRange(characterRange) <= NSMaxRange(lastRange) {
                break
            }

            pageRanges.append(characterRange)
            Self.logger.info("📐 Page \(pageRanges.count - 1, privacy: .public) range: \(characterRange.location, privacy: .public)+\(characterRange.length, privacy: .public)")

            lastRange = characterRange
        }

        // Step 2: Create isolated text system for each page
        var pages: [Page] = []
        for (index, range) in pageRanges.enumerated() {
            // Extract just this page's text
            let pageText = fullText.attributedSubstring(from: range)
            let pageStorage = NSTextStorage(attributedString: pageText)

            // Create dedicated layout manager
            let pageLayoutManager = NSLayoutManager()
            pageLayoutManager.allowsNonContiguousLayout = false
            pageStorage.addLayoutManager(pageLayoutManager)

            // Create container
            let pageContainer = NSTextContainer(size: availableSize)
            pageContainer.lineFragmentPadding = 0
            pageContainer.widthTracksTextView = false
            pageContainer.heightTracksTextView = false
            pageLayoutManager.addTextContainer(pageContainer)

            // Force layout
            pageLayoutManager.ensureLayout(for: pageContainer)

            let page = Page(
                id: index,
                range: range,
                textStorage: pageStorage,
                layoutManager: pageLayoutManager,
                textContainer: pageContainer
            )
            pages.append(page)
        }

        let result = PaginationResult(pages: pages)
        Self.logger.info("✅ Created \(pages.count, privacy: .public) pages with ISOLATED text systems")

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
