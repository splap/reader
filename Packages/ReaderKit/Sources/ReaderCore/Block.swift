import CryptoKit
import Foundation

/// The type of content block extracted from EPUB HTML
public enum BlockType: String, Codable, Equatable {
    case paragraph
    case heading1
    case heading2
    case heading3
    case heading4
    case heading5
    case heading6
    case listItem
    case blockquote
    case preformatted
    case image
    case unknown

    /// Maps HTML tag names to block types
    public static func from(tagName: String) -> BlockType {
        switch tagName.lowercased() {
        case "p": .paragraph
        case "h1": .heading1
        case "h2": .heading2
        case "h3": .heading3
        case "h4": .heading4
        case "h5": .heading5
        case "h6": .heading6
        case "li": .listItem
        case "blockquote": .blockquote
        case "pre": .preformatted
        case "img": .image
        case "td": .listItem // Table cells treated as list items for compact rendering (e.g., TOC tables)
        // Note: div is not matched as a block since it often wraps other block elements
        default: .unknown
        }
    }
}

/// A content block representing a semantic unit of text in the book
public struct Block: Identifiable, Codable, Equatable {
    /// Stable identifier for this block, derived from content hash
    public let id: String

    /// The spine item (chapter/file) this block belongs to
    public let spineItemId: String

    /// The type of block (paragraph, heading, etc.)
    public let type: BlockType

    /// The text content of the block (normalized, for display and hashing)
    public let textContent: String

    /// The original HTML content (for rendering)
    public let htmlContent: String

    /// Ordinal position within the spine item (0-indexed)
    public let ordinal: Int

    public init(
        spineItemId: String,
        type: BlockType,
        textContent: String,
        htmlContent: String,
        ordinal: Int
    ) {
        self.spineItemId = spineItemId
        self.type = type
        self.textContent = textContent
        self.htmlContent = htmlContent
        self.ordinal = ordinal
        id = Block.generateId(spineItemId: spineItemId, textContent: textContent, ordinal: ordinal)
    }

    /// Generates a stable, deterministic block ID from content
    /// Format: first 12 chars of SHA256(spineItemId + normalizedText + ordinal)
    private static func generateId(spineItemId: String, textContent: String, ordinal: Int) -> String {
        let normalized = normalizeText(textContent)
        let input = "\(spineItemId)|\(normalized)|\(ordinal)"
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return String(hashString.prefix(12))
    }

    /// Normalizes text for consistent hashing
    /// - Collapses whitespace
    /// - Lowercases
    /// - Removes punctuation variations
    private static func normalizeText(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - CFI Position

/// Reading position based on EPUB CFI (Canonical Fragment Identifier).
/// This is the ONLY position tracking mechanism.
public struct CFIPosition: Codable, Equatable {
    /// Identifier for the book
    public let bookId: String

    /// Full CFI string (e.g., "epubcfi(/6/4[ch02]!/4/2/1:42)")
    public let cfi: String

    /// Optional: furthest read position CFI (for progress tracking)
    public let maxCfi: String?

    public init(bookId: String, cfi: String, maxCfi: String? = nil) {
        self.bookId = bookId
        self.cfi = cfi
        self.maxCfi = maxCfi
    }

    /// Extract the spine index from this position's CFI
    public var spineIndex: Int? {
        CFIParser.parseFullCFI(cfi)?.spineIndex
    }
}
