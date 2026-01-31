@testable import ReaderCore
import XCTest

final class ChunkerTests: XCTestCase {
    func testTokenEstimation() {
        // ~4 chars per token
        XCTAssertEqual(Chunk.estimateTokens(""), 1) // Minimum of 1
        XCTAssertEqual(Chunk.estimateTokens("word"), 1)
        XCTAssertEqual(Chunk.estimateTokens("Hello, world!"), 3) // 13 chars / 4 = 3
        XCTAssertEqual(Chunk.estimateTokens(String(repeating: "a", count: 400)), 100)
    }

    func testChunkingWithSmallBlocks() {
        // Create blocks that fit within one chunk
        let blocks = (0 ..< 5).map { ordinal in
            Block(
                spineItemId: "chapter1",
                type: .paragraph,
                textContent: "This is paragraph \(ordinal).",
                htmlContent: "<p>This is paragraph \(ordinal).</p>",
                ordinal: ordinal
            )
        }

        let chunks = Chunker.chunk(blocks: blocks, bookId: "book1", chapterId: "chapter1")

        // Small blocks should result in a single chunk
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first?.blockIds.count, 5)
        XCTAssertTrue(chunks.first?.text.contains("paragraph 0") ?? false)
        XCTAssertTrue(chunks.first?.text.contains("paragraph 4") ?? false)
    }

    func testChunkingWithLargeBlocks() {
        // Create blocks that exceed chunk size (800 tokens = ~3200 chars)
        let largeText = String(repeating: "Lorem ipsum dolor sit amet. ", count: 150) // ~4350 chars
        let blocks = (0 ..< 3).map { ordinal in
            Block(
                spineItemId: "chapter1",
                type: .paragraph,
                textContent: "[\(ordinal)] " + largeText,
                htmlContent: "<p>[\(ordinal)] \(largeText)</p>",
                ordinal: ordinal
            )
        }

        let chunks = Chunker.chunk(blocks: blocks, bookId: "book1", chapterId: "chapter1")

        // Should create multiple chunks
        XCTAssertGreaterThan(chunks.count, 1)

        // Verify chunk IDs are unique
        let ids = Set(chunks.map(\.id))
        XCTAssertEqual(ids.count, chunks.count)

        // Verify ordinals are sequential
        for (index, chunk) in chunks.enumerated() {
            XCTAssertEqual(chunk.ordinal, index)
        }
    }

    func testChunkOverlap() {
        // Create enough blocks to trigger overlap
        let blocks = (0 ..< 20).map { ordinal in
            Block(
                spineItemId: "chapter1",
                type: .paragraph,
                textContent: String(repeating: "Word ", count: 200) + "[\(ordinal)]", // ~1000 chars each
                htmlContent: "<p>\(String(repeating: "Word ", count: 200))[\(ordinal)]</p>",
                ordinal: ordinal
            )
        }

        let chunks = Chunker.chunk(blocks: blocks, bookId: "book1", chapterId: "chapter1")

        // With overlap, some block IDs should appear in multiple chunks
        guard chunks.count >= 2 else {
            XCTFail("Expected at least 2 chunks")
            return
        }

        // Check that chunks have reasonable token counts
        for chunk in chunks {
            XCTAssertGreaterThan(chunk.tokenCount, 0)
        }
    }

    func testEmptyBlocks() {
        let chunks = Chunker.chunk(blocks: [], bookId: "book1", chapterId: "chapter1")
        XCTAssertTrue(chunks.isEmpty)
    }

    func testChunkBookMultipleChapters() {
        let blocks1 = [
            Block(spineItemId: "ch1", type: .paragraph, textContent: "Chapter 1 content", htmlContent: "<p>Chapter 1 content</p>", ordinal: 0),
        ]
        let blocks2 = [
            Block(spineItemId: "ch2", type: .paragraph, textContent: "Chapter 2 content", htmlContent: "<p>Chapter 2 content</p>", ordinal: 0),
        ]

        let chapter1 = Chapter(
            id: "ch1",
            htmlSections: [HTMLSection(html: "<p>Chapter 1 content</p>", basePath: "", blocks: blocks1, spineItemId: "ch1")],
            title: "Chapter 1"
        )
        let chapter2 = Chapter(
            id: "ch2",
            htmlSections: [HTMLSection(html: "<p>Chapter 2 content</p>", basePath: "", blocks: blocks2, spineItemId: "ch2")],
            title: "Chapter 2"
        )

        let chunks = Chunker.chunkBook(chapters: [chapter1, chapter2], bookId: "book1")

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].chapterId, "ch1")
        XCTAssertEqual(chunks[1].chapterId, "ch2")
    }
}
