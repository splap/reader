import CryptoKit
import Foundation

/// A text chunk representing a group of blocks for search and chat
/// Chunks are ~800 tokens with 10% overlap between adjacent chunks
public struct Chunk: Identifiable, Codable, Equatable {
    /// Stable identifier for this chunk, derived from content hash
    public let id: String

    /// Identifier for the book this chunk belongs to
    public let bookId: String

    /// The spine item (chapter/file) this chunk belongs to
    public let chapterId: String

    /// The plain text content of the chunk
    public let text: String

    /// Approximate token count (text.count / 4)
    public let tokenCount: Int

    /// The block IDs that make up this chunk (for mapping back to source)
    public let blockIds: [String]

    /// Character offset where this chunk starts in the chapter
    public let startOffset: Int

    /// Character offset where this chunk ends in the chapter
    public let endOffset: Int

    /// Ordinal position of this chunk within the chapter
    public let ordinal: Int

    public init(
        bookId: String,
        chapterId: String,
        text: String,
        blockIds: [String],
        startOffset: Int,
        endOffset: Int,
        ordinal: Int
    ) {
        id = Chunk.generateId(bookId: bookId, chapterId: chapterId, ordinal: ordinal)
        self.bookId = bookId
        self.chapterId = chapterId
        self.text = text
        tokenCount = Chunk.estimateTokens(text)
        self.blockIds = blockIds
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.ordinal = ordinal
    }

    /// Internal initializer for loading from database with pre-computed values
    init(
        id: String,
        bookId: String,
        chapterId: String,
        text: String,
        tokenCount: Int,
        blockIds: [String],
        startOffset: Int,
        endOffset: Int,
        ordinal: Int
    ) {
        self.id = id
        self.bookId = bookId
        self.chapterId = chapterId
        self.text = text
        self.tokenCount = tokenCount
        self.blockIds = blockIds
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.ordinal = ordinal
    }

    /// Estimates token count using simple character-based approximation
    /// Average of ~4 characters per token for English text
    public static func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    /// Generates a stable, deterministic chunk ID
    /// Format: first 16 chars of SHA256(bookId + chapterId + ordinal)
    private static func generateId(bookId: String, chapterId: String, ordinal: Int) -> String {
        let input = "\(bookId)|\(chapterId)|\(ordinal)"
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return String(hashString.prefix(16))
    }
}

/// A search result from the chunk store
public struct ChunkMatch: Identifiable, Equatable {
    public var id: String { chunk.id }

    /// The matched chunk
    public let chunk: Chunk

    /// FTS5 rank score (higher = better match)
    public let score: Double

    /// Snippet with highlighted matches (optional)
    public let snippet: String?

    public init(chunk: Chunk, score: Double, snippet: String? = nil) {
        self.chunk = chunk
        self.score = score
        self.snippet = snippet
    }
}
