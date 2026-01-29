@testable import ReaderCore
import XCTest

final class VectorStoreTests: XCTestCase {
    let testBookId = "vector-test-book-\(UUID().uuidString)"

    override func tearDown() async throws {
        // Clean up test index
        try? await VectorStore.shared.deleteBook(bookId: testBookId)
    }

    func testBuildAndSearchIndex() async throws {
        let store = VectorStore.shared

        // Create test chunks
        let chunks = [
            Chunk(bookId: testBookId, chapterId: "ch1", text: "The quick brown fox", blockIds: ["b1"], startOffset: 0, endOffset: 19, ordinal: 0),
            Chunk(bookId: testBookId, chapterId: "ch1", text: "jumps over the lazy dog", blockIds: ["b2"], startOffset: 20, endOffset: 43, ordinal: 1),
            Chunk(bookId: testBookId, chapterId: "ch2", text: "A completely different sentence", blockIds: ["b3"], startOffset: 0, endOffset: 31, ordinal: 0),
        ]

        // Create mock embeddings (384-dim normalized vectors)
        let embeddings = chunks.map { _ in createMockEmbedding() }

        // Build index
        try await store.buildIndex(bookId: testBookId, chunks: chunks, embeddings: embeddings)

        // Verify indexed
        let isIndexed = await store.isIndexed(bookId: testBookId)
        XCTAssertTrue(isIndexed)

        // Search with first embedding (should return itself as top match)
        let results = try await store.search(bookId: testBookId, queryEmbedding: embeddings[0], k: 3)

        XCTAssertEqual(results.count, 3)
        // First result should be the chunk whose embedding we used as query
        XCTAssertEqual(results[0].chunkId, chunks[0].id)
        XCTAssertGreaterThan(results[0].score, 0.99) // Should be ~1.0 for exact match
    }

    func testDeleteIndex() async throws {
        let store = VectorStore.shared
        let deleteBookId = "delete-vector-\(UUID().uuidString)"

        // Create and index a chunk
        let chunks = [
            Chunk(bookId: deleteBookId, chapterId: "ch1", text: "Test content", blockIds: ["b1"], startOffset: 0, endOffset: 12, ordinal: 0),
        ]
        let embeddings = [createMockEmbedding()]

        try await store.buildIndex(bookId: deleteBookId, chunks: chunks, embeddings: embeddings)

        // Verify indexed
        var isIndexed = await store.isIndexed(bookId: deleteBookId)
        XCTAssertTrue(isIndexed)

        // Delete
        try await store.deleteBook(bookId: deleteBookId)

        // Verify deleted
        isIndexed = await store.isIndexed(bookId: deleteBookId)
        XCTAssertFalse(isIndexed)
    }

    func testMismatchedCountsThrows() async throws {
        let store = VectorStore.shared
        let mismatchBookId = "mismatch-\(UUID().uuidString)"

        let chunks = [
            Chunk(bookId: mismatchBookId, chapterId: "ch1", text: "Chunk 1", blockIds: ["b1"], startOffset: 0, endOffset: 7, ordinal: 0),
            Chunk(bookId: mismatchBookId, chapterId: "ch1", text: "Chunk 2", blockIds: ["b2"], startOffset: 8, endOffset: 15, ordinal: 1),
        ]

        // Only one embedding for two chunks
        let embeddings = [createMockEmbedding()]

        do {
            try await store.buildIndex(bookId: mismatchBookId, chunks: chunks, embeddings: embeddings)
            XCTFail("Expected error for mismatched counts")
        } catch let error as VectorStoreError {
            if case let .mismatchedCounts(chunks, embeddings) = error {
                XCTAssertEqual(chunks, 2)
                XCTAssertEqual(embeddings, 1)
            } else {
                XCTFail("Expected mismatchedCounts error")
            }
        }
    }

    func testInvalidDimensionThrows() async throws {
        let store = VectorStore.shared
        let dimBookId = "dim-\(UUID().uuidString)"

        let chunks = [
            Chunk(bookId: dimBookId, chapterId: "ch1", text: "Test", blockIds: ["b1"], startOffset: 0, endOffset: 4, ordinal: 0),
        ]

        // Wrong dimension (128 instead of 384)
        let wrongDimEmbedding = (0 ..< 128).map { _ in Float.random(in: -1 ... 1) }

        do {
            try await store.buildIndex(bookId: dimBookId, chunks: chunks, embeddings: [wrongDimEmbedding])
            XCTFail("Expected error for invalid dimension")
        } catch let error as VectorStoreError {
            if case let .invalidDimension(expected, actual) = error {
                XCTAssertEqual(expected, 384)
                XCTAssertEqual(actual, 128)
            } else {
                XCTFail("Expected invalidDimension error")
            }
        }
    }

    func testSearchInvalidDimensionThrows() async throws {
        let store = VectorStore.shared

        // Create index first
        let chunks = [
            Chunk(bookId: testBookId, chapterId: "ch1", text: "Test", blockIds: ["b1"], startOffset: 0, endOffset: 4, ordinal: 0),
        ]
        let embeddings = [createMockEmbedding()]
        try await store.buildIndex(bookId: testBookId, chunks: chunks, embeddings: embeddings)

        // Search with wrong dimension
        let wrongDimQuery = (0 ..< 128).map { _ in Float.random(in: -1 ... 1) }

        do {
            _ = try await store.search(bookId: testBookId, queryEmbedding: wrongDimQuery, k: 1)
            XCTFail("Expected error for invalid query dimension")
        } catch let error as VectorStoreError {
            if case let .invalidDimension(expected, actual) = error {
                XCTAssertEqual(expected, 384)
                XCTAssertEqual(actual, 128)
            } else {
                XCTFail("Expected invalidDimension error")
            }
        }
    }

    func testEmptyChunksHandledGracefully() async throws {
        let store = VectorStore.shared
        let emptyBookId = "empty-\(UUID().uuidString)"

        // Empty chunks should not throw, just do nothing
        try await store.buildIndex(bookId: emptyBookId, chunks: [], embeddings: [])

        // Should not be indexed (no index file created for empty)
        let isIndexed = await store.isIndexed(bookId: emptyBookId)
        XCTAssertFalse(isIndexed)
    }

    // MARK: - Helpers

    private func createMockEmbedding() -> [Float] {
        // Create a random 384-dim vector and L2 normalize it
        var vector = (0 ..< 384).map { _ in Float.random(in: -1 ... 1) }
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        vector = vector.map { $0 / norm }
        return vector
    }
}
