import Foundation
import CryptoKit

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
        case "p": return .paragraph
        case "h1": return .heading1
        case "h2": return .heading2
        case "h3": return .heading3
        case "h4": return .heading4
        case "h5": return .heading5
        case "h6": return .heading6
        case "li": return .listItem
        case "blockquote": return .blockquote
        case "pre": return .preformatted
        case "img": return .image
        case "div": return .paragraph  // Treat div as paragraph for TOC entries etc.
        default: return .unknown
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
        self.id = Block.generateId(spineItemId: spineItemId, textContent: textContent, ordinal: ordinal)
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

/// Reading position based on block location (replaces page-based positioning)
public struct BlockPosition: Codable, Equatable {
    /// Identifier for the book
    public let bookId: String

    /// The spine item (chapter/file) containing the current position
    public let spineItemId: String

    /// The block ID at the current reading position
    public let blockId: String

    /// Optional: furthest block reached (for progress tracking)
    public let maxBlockId: String?

    /// Optional: furthest spine item reached
    public let maxSpineItemId: String?

    public init(
        bookId: String,
        spineItemId: String,
        blockId: String,
        maxBlockId: String? = nil,
        maxSpineItemId: String? = nil
    ) {
        self.bookId = bookId
        self.spineItemId = spineItemId
        self.blockId = blockId
        self.maxBlockId = maxBlockId
        self.maxSpineItemId = maxSpineItemId
    }
}
