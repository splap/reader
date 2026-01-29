import Foundation

/// Represents the boundary of a single page in a chapter layout
public struct PageOffset: Codable, Equatable {
    /// Page index (0-based)
    public let pageIndex: Int

    /// Block ID of the first block that appears on this page
    public let firstBlockId: String

    /// Character offset within the first block where this page starts
    /// (0 means the block starts fresh on this page)
    public let firstBlockCharOffset: Int

    /// Block ID of the last block that appears on this page
    public let lastBlockId: String

    /// Character offset within the last block where this page ends
    public let lastBlockCharOffset: Int

    /// Character range in the attributed string (for quick rendering)
    /// Stored as location and length since NSRange isn't directly Codable
    public let rangeLocation: Int
    public let rangeLength: Int

    /// Convenience accessor for NSRange
    public var characterRange: NSRange {
        NSRange(location: rangeLocation, length: rangeLength)
    }

    public init(
        pageIndex: Int,
        firstBlockId: String,
        firstBlockCharOffset: Int,
        lastBlockId: String,
        lastBlockCharOffset: Int,
        characterRange: NSRange
    ) {
        self.pageIndex = pageIndex
        self.firstBlockId = firstBlockId
        self.firstBlockCharOffset = firstBlockCharOffset
        self.lastBlockId = lastBlockId
        self.lastBlockCharOffset = lastBlockCharOffset
        rangeLocation = characterRange.location
        rangeLength = characterRange.length
    }
}

/// Layout parameters that affect pagination
public struct LayoutConfig: Codable, Equatable, Hashable {
    /// Font scale (1.0 - 1.8)
    public let fontScale: CGFloat

    /// Page width in points
    public let pageWidth: CGFloat

    /// Page height in points
    public let pageHeight: CGFloat

    /// Horizontal padding
    public let horizontalPadding: CGFloat

    /// Vertical padding
    public let verticalPadding: CGFloat

    public init(
        fontScale: CGFloat,
        pageWidth: CGFloat,
        pageHeight: CGFloat,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat
    ) {
        self.fontScale = fontScale
        self.pageWidth = pageWidth
        self.pageHeight = pageHeight
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    /// Generates a stable key for cache lookup
    /// Rounded to avoid float precision issues
    public var cacheKey: String {
        let w = Int(pageWidth)
        let h = Int(pageHeight)
        let scale = Int(fontScale * 10)
        let hPad = Int(horizontalPadding)
        let vPad = Int(verticalPadding)
        return "\(w)x\(h)_s\(scale)_p\(hPad)x\(vPad)"
    }

    /// The effective page size after padding
    public var contentSize: CGSize {
        CGSize(
            width: pageWidth - (horizontalPadding * 2),
            height: pageHeight - (verticalPadding * 2)
        )
    }
}

/// Complete layout information for a chapter under a specific configuration
public struct ChapterLayout: Codable {
    /// Version number for cache invalidation on format changes
    public static let formatVersion = 6

    /// Unique identifier combining book, spine item, and config
    public let layoutKey: String

    /// Book ID this layout belongs to
    public let bookId: String

    /// Spine item ID for the chapter
    public let spineItemId: String

    /// Layout parameters that affect pagination
    public let config: LayoutConfig

    /// Page offsets for each page
    public let pageOffsets: [PageOffset]

    /// Timestamp when this layout was computed
    public let computedAt: Date

    /// Version of this format
    public let version: Int

    /// Total page count
    public var totalPages: Int { pageOffsets.count }

    public init(
        bookId: String,
        spineItemId: String,
        config: LayoutConfig,
        pageOffsets: [PageOffset],
        computedAt: Date = Date()
    ) {
        self.bookId = bookId
        self.spineItemId = spineItemId
        self.config = config
        self.pageOffsets = pageOffsets
        self.computedAt = computedAt
        version = Self.formatVersion
        layoutKey = Self.generateLayoutKey(bookId: bookId, spineItemId: spineItemId, config: config)
    }

    /// Generates a unique key for this layout
    public static func generateLayoutKey(bookId: String, spineItemId: String, config: LayoutConfig) -> String {
        "\(bookId)_\(spineItemId)_\(config.cacheKey)"
    }
}
