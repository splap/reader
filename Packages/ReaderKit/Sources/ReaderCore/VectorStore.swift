import Foundation
import OSLog
import USearch

/// Manages HNSW vector indices for semantic search
/// Uses USearch for efficient approximate nearest neighbor search
public actor VectorStore {
    private static let logger = Logger(subsystem: "com.splap.reader", category: "VectorStore")

    /// Shared instance
    public static let shared = VectorStore()

    /// Directory for storing vector indices
    private let storeDirectory: URL

    /// In-memory cache of loaded indices
    private var loadedIndices: [String: USearchIndex] = [:]

    /// Mapping from chunk ID to vector position for each book
    private var chunkIdMappings: [String: [String: UInt64]] = [:]

    /// Reverse mapping from vector position to chunk ID
    private var positionToChunkId: [String: [UInt64: String]] = [:]

    /// Cached chunks for each book (for retrieving text after search)
    private var cachedChunks: [String: [String: Chunk]] = [:]

    /// Embedding dimension (bge-small-en-v1.5 produces 384-dim vectors)
    public static let dimension: UInt32 = 384

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let readerDir = appSupport.appendingPathComponent("com.splap.reader", isDirectory: true)
        self.storeDirectory = readerDir.appendingPathComponent("vectors", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Index Building

    /// Builds a vector index for a book from chunks and their embeddings
    /// - Parameters:
    ///   - bookId: The book identifier
    ///   - chunks: The chunks to index
    ///   - embeddings: The embeddings for each chunk (must match chunks count)
    public func buildIndex(bookId: String, chunks: [Chunk], embeddings: [[Float]]) throws {
        guard chunks.count == embeddings.count else {
            throw VectorStoreError.mismatchedCounts(chunks: chunks.count, embeddings: embeddings.count)
        }

        guard !chunks.isEmpty else {
            Self.logger.info("No chunks to index for book \(bookId)")
            return
        }

        // Verify embedding dimensions
        if let firstEmbedding = embeddings.first, firstEmbedding.count != Int(Self.dimension) {
            throw VectorStoreError.invalidDimension(expected: Int(Self.dimension), actual: firstEmbedding.count)
        }

        Self.logger.info("Building vector index for book \(bookId) with \(chunks.count) chunks")

        // Create index with HNSW parameters
        let index = try USearchIndex.make(
            metric: .cos,           // Cosine similarity for text embeddings
            dimensions: Self.dimension,
            connectivity: 16,       // M parameter - connections per node
            quantization: .f32      // Full precision for quality
        )

        // Reserve capacity
        try index.reserve(UInt32(chunks.count))

        // Build mappings and add vectors
        var idMapping: [String: UInt64] = [:]
        var reverseMapping: [UInt64: String] = [:]

        for (position, (chunk, embedding)) in zip(chunks, embeddings).enumerated() {
            let key = UInt64(position)
            idMapping[chunk.id] = key
            reverseMapping[key] = chunk.id

            // Add vector to index
            try index.add(key: key, vector: embedding)
        }

        // Save index to disk
        let indexPath = indexPath(for: bookId)
        try index.save(path: indexPath.path)

        // Save mappings
        let mappingPath = mappingPath(for: bookId)
        try saveMappings(idMapping, to: mappingPath)

        // Save chunks (for text retrieval after search)
        let chunksPath = chunksPath(for: bookId)
        try saveChunks(chunks, to: chunksPath)

        // Build chunk lookup
        var chunkLookup: [String: Chunk] = [:]
        for chunk in chunks {
            chunkLookup[chunk.id] = chunk
        }

        // Cache in memory
        loadedIndices[bookId] = index
        chunkIdMappings[bookId] = idMapping
        positionToChunkId[bookId] = reverseMapping
        cachedChunks[bookId] = chunkLookup

        Self.logger.info("Successfully built vector index for book \(bookId)")
    }

    // MARK: - Search

    /// Searches for similar chunks using vector similarity
    /// - Parameters:
    ///   - bookId: The book to search in
    ///   - queryEmbedding: The query vector (384-dim)
    ///   - k: Number of results to return
    ///   - chapterIds: Optional chapter filter
    /// - Returns: Array of chunk IDs with similarity scores, sorted by relevance
    public func search(
        bookId: String,
        queryEmbedding: [Float],
        k: Int = 10,
        chapterIds: [String]? = nil
    ) throws -> [(chunkId: String, score: Float)] {
        guard queryEmbedding.count == Int(Self.dimension) else {
            throw VectorStoreError.invalidDimension(expected: Int(Self.dimension), actual: queryEmbedding.count)
        }

        // Load index if not cached
        let index = try loadIndex(for: bookId)
        let reverseMapping = try loadReverseMapping(for: bookId)

        // Search with extra results if we need to filter by chapter
        let searchK = chapterIds != nil ? k * 3 : k
        let (keys, distances) = try index.search(vector: queryEmbedding, count: searchK)

        var matches: [(chunkId: String, score: Float)] = []

        for i in 0..<keys.count {
            let key = keys[i]
            let distance = distances[i]

            guard let chunkId = reverseMapping[key] else { continue }

            // Convert distance to similarity score (cosine distance → similarity)
            let score = 1.0 - distance

            matches.append((chunkId: chunkId, score: score))
        }

        // Filter by chapter if specified (requires lookup from ChunkStore)
        // Note: For now, return all results. Chapter filtering will be done at the search layer
        // where we have access to chunk metadata.

        return Array(matches.prefix(k))
    }

    // MARK: - Index Management

    /// Checks if a book has a vector index
    public func isIndexed(bookId: String) -> Bool {
        let path = indexPath(for: bookId)
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// Deletes the vector index for a book
    public func deleteBook(bookId: String) throws {
        // Remove from memory cache
        loadedIndices.removeValue(forKey: bookId)
        chunkIdMappings.removeValue(forKey: bookId)
        positionToChunkId.removeValue(forKey: bookId)
        cachedChunks.removeValue(forKey: bookId)

        // Remove files
        let indexPath = indexPath(for: bookId)
        let mappingPath = mappingPath(for: bookId)
        let chunksPath = chunksPath(for: bookId)

        try? FileManager.default.removeItem(at: indexPath)
        try? FileManager.default.removeItem(at: mappingPath)
        try? FileManager.default.removeItem(at: chunksPath)

        Self.logger.info("Deleted vector index for book \(bookId)")
    }

    /// Clears all cached indices from memory (indices remain on disk)
    public func clearCache() {
        loadedIndices.removeAll()
        chunkIdMappings.removeAll()
        positionToChunkId.removeAll()
        cachedChunks.removeAll()
        Self.logger.info("Cleared vector index cache")
    }

    /// Retrieves a chunk by ID (for getting text after semantic search)
    public func getChunk(bookId: String, chunkId: String) throws -> Chunk? {
        // Check cache first
        if let cached = cachedChunks[bookId]?[chunkId] {
            return cached
        }

        // Load from disk
        let chunks = try loadChunks(for: bookId)
        return chunks[chunkId]
    }

    // MARK: - Private Helpers

    private func indexPath(for bookId: String) -> URL {
        storeDirectory.appendingPathComponent("\(bookId).usearch")
    }

    private func mappingPath(for bookId: String) -> URL {
        storeDirectory.appendingPathComponent("\(bookId).mapping.json")
    }

    private func chunksPath(for bookId: String) -> URL {
        storeDirectory.appendingPathComponent("\(bookId).chunks.json")
    }

    private func loadIndex(for bookId: String) throws -> USearchIndex {
        // Check cache first
        if let cached = loadedIndices[bookId] {
            return cached
        }

        // Load from disk
        let path = indexPath(for: bookId)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw VectorStoreError.indexNotFound(bookId: bookId)
        }

        let index = try USearchIndex.make(
            metric: .cos,
            dimensions: Self.dimension,
            connectivity: 16,
            quantization: .f32
        )

        try index.load(path: path.path)
        loadedIndices[bookId] = index

        Self.logger.debug("Loaded vector index for book \(bookId)")
        return index
    }

    private func loadReverseMapping(for bookId: String) throws -> [UInt64: String] {
        // Check cache first
        if let cached = positionToChunkId[bookId] {
            return cached
        }

        // Load from disk
        let path = mappingPath(for: bookId)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw VectorStoreError.indexNotFound(bookId: bookId)
        }

        let data = try Data(contentsOf: path)
        let idMapping = try JSONDecoder().decode([String: UInt64].self, from: data)

        // Build reverse mapping
        var reverseMapping: [UInt64: String] = [:]
        for (chunkId, position) in idMapping {
            reverseMapping[position] = chunkId
        }

        chunkIdMappings[bookId] = idMapping
        positionToChunkId[bookId] = reverseMapping

        return reverseMapping
    }

    private func saveMappings(_ mapping: [String: UInt64], to path: URL) throws {
        let data = try JSONEncoder().encode(mapping)
        try data.write(to: path)
    }

    private func saveChunks(_ chunks: [Chunk], to path: URL) throws {
        let data = try JSONEncoder().encode(chunks)
        try data.write(to: path)
    }

    private func loadChunks(for bookId: String) throws -> [String: Chunk] {
        // Check cache first
        if let cached = cachedChunks[bookId] {
            return cached
        }

        // Load from disk
        let path = chunksPath(for: bookId)
        guard FileManager.default.fileExists(atPath: path.path) else {
            return [:]
        }

        let data = try Data(contentsOf: path)
        let chunks = try JSONDecoder().decode([Chunk].self, from: data)

        // Build lookup
        var lookup: [String: Chunk] = [:]
        for chunk in chunks {
            lookup[chunk.id] = chunk
        }

        cachedChunks[bookId] = lookup
        return lookup
    }
}

/// Errors that can occur in VectorStore operations
public enum VectorStoreError: Error, LocalizedError {
    case indexNotFound(bookId: String)
    case invalidDimension(expected: Int, actual: Int)
    case mismatchedCounts(chunks: Int, embeddings: Int)
    case searchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .indexNotFound(let bookId):
            return "Vector index not found for book: \(bookId)"
        case .invalidDimension(let expected, let actual):
            return "Invalid embedding dimension: expected \(expected), got \(actual)"
        case .mismatchedCounts(let chunks, let embeddings):
            return "Mismatched counts: \(chunks) chunks but \(embeddings) embeddings"
        case .searchFailed(let message):
            return "Search failed: \(message)"
        }
    }
}
