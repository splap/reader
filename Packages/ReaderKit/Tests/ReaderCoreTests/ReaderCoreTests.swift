import XCTest
import UIKit
import ZIPFoundation
@testable import ReaderCore

final class ReaderCoreTests: XCTestCase {
    func testPaginationRangesAreContiguousAndCoverText() {
        let chapter = makeChapter()
        let engine = TextEngine(chapter: chapter)

        let result = engine.paginate(
            pageSize: CGSize(width: 320, height: 480),
            insets: UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16),
            fontScale: 1.0
        )
        let pages = result.pages

        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertEqual(pages.first?.range.location, 0)

        for index in 1..<pages.count {
            let previous = pages[index - 1].range
            let current = pages[index].range
            XCTAssertEqual(current.location, previous.location + previous.length)
        }

        let lastRange = pages.last?.range ?? NSRange(location: 0, length: 0)
        let coveredLength = lastRange.location + lastRange.length
        XCTAssertGreaterThanOrEqual(coveredLength, chapter.attributedText.length)
    }

    func testCharacterOffsetMappingFindsExpectedPage() {
        let chapter = makeChapter()
        let engine = TextEngine(chapter: chapter)

        let result = engine.paginate(
            pageSize: CGSize(width: 320, height: 480),
            insets: UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16),
            fontScale: 1.0
        )
        let pages = result.pages

        XCTAssertGreaterThan(pages.count, 1)

        let secondStart = pages[1].range.location
        XCTAssertEqual(engine.pageIndex(for: secondStart, in: pages), 1)
        XCTAssertEqual(engine.pageIndex(for: secondStart - 1, in: pages), 0)

        let lastRange = pages.last?.range ?? NSRange(location: 0, length: 0)
        XCTAssertEqual(engine.pageIndex(for: lastRange.location, in: pages), pages.count - 1)
        XCTAssertEqual(
            engine.pageIndex(for: lastRange.location + lastRange.length + 10, in: pages),
            pages.count - 1
        )
    }

    func testTextContainerActualRangeIsNonEmpty() {
        let chapter = makeChapter()
        let engine = TextEngine(chapter: chapter)

        let result = engine.paginate(
            pageSize: CGSize(width: 320, height: 480),
            insets: UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16),
            fontScale: 1.0
        )

        XCTAssertGreaterThan(result.pages.count, 1)

        for (index, page) in result.pages.enumerated() {
            let actualRange = page.actualCharacterRange()
            XCTAssertGreaterThan(
                actualRange.length,
                0,
                "Page \(index) mapped to an empty character range"
            )
        }
    }

    func testPositionStoreRoundTrip() {
        let suiteName = "ReaderCoreTests.PositionStore"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = UserDefaultsPositionStore(defaults: defaults)
        let position = ReaderPosition(chapterId: "sample", pageIndex: 3, characterOffset: 120)
        store.save(position)

        XCTAssertEqual(store.load(chapterId: "sample"), position)
    }

    func testEPUBLoaderReadsSingleChapter() throws {
        let epubURL = try makeMinimalEPUB()
        let loader = EPUBLoader()
        let chapter = try loader.loadChapter(from: epubURL, maxSections: 1)

        XCTAssertTrue(chapter.attributedText.string.contains("Hello from EPUB"))
        XCTAssertEqual(chapter.title, "Sample EPUB")
    }

    func testCSSManagerGeneratesHouseCSS() {
        let css = CSSManager.houseCSS(fontScale: 2.0)

        // Verify house CSS contains critical pagination properties
        XCTAssertTrue(css.contains("font-size: 32px"), "House CSS should scale font size")
        XCTAssertTrue(css.contains("column-width: 100vw"), "House CSS should set column width for pagination")
    }

    func testCSSManagerIncludesPublisherCSS() {
        let publisherCSS = """
        p { text-indent: 1em; }
        .centered { text-align: center; }
        """

        let combined = CSSManager.generateCompleteCSS(fontScale: 1.0, publisherCSS: publisherCSS)

        // Publisher CSS should be included unchanged
        XCTAssertTrue(combined.contains("text-indent: 1em"), "Publisher CSS should be preserved")
        XCTAssertTrue(combined.contains("text-align: center"), "Publisher alignment should be preserved")
        // House CSS should also be present
        XCTAssertTrue(combined.contains("column-width: 100vw"), "House CSS should be included")
    }

    func testResolveChapterIdMatchesLabelsAndIndex() {
        let sections = [
            SectionInfo(spineItemId: "s1", title: "Chapter I", ncxLabel: "I", blockCount: 10),
            SectionInfo(spineItemId: "s2", title: "Chapter II", ncxLabel: "II", blockCount: 12)
        ]
        let context = StubBookContext(currentSpineItemId: "s1", sections: sections)

        XCTAssertEqual(ToolExecutor.resolveChapterId("current", in: context), "s1")
        XCTAssertEqual(ToolExecutor.resolveChapterId("s2", in: context), "s2")
        XCTAssertNil(ToolExecutor.resolveChapterId("II", in: context))
        XCTAssertNil(ToolExecutor.resolveChapterId("chapter ii", in: context))
        XCTAssertNil(ToolExecutor.resolveChapterId("2", in: context))
    }

    private func makeChapter() -> Chapter {
        let text = String(repeating: "Lorem ipsum dolor sit amet. ", count: 400)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14)
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        return Chapter(id: "sample", attributedText: attributedText, title: "Sample")
    }

    private func makeMinimalEPUB() throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("epub")

        let archive = try Archive(url: tempURL, accessMode: .create)
        try addFile(
            to: archive,
            path: "META-INF/container.xml",
            contents: """
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""
        )
        try addFile(
            to: archive,
            path: "OEBPS/content.opf",
            contents: """
<?xml version="1.0" encoding="UTF-8"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Sample EPUB</dc:title>
  </metadata>
  <manifest>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chapter1"/>
  </spine>
</package>
"""
        )
        try addFile(
            to: archive,
            path: "OEBPS/chapter1.xhtml",
            contents: """
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Sample EPUB</title></head>
  <body><p>Hello from EPUB</p></body>
</html>
"""
        )

        return tempURL
    }

    private func addFile(to archive: Archive, path: String, contents: String) throws {
        let data = Data(contents.utf8)
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: UInt32(data.count),
            compressionMethod: .none
        ) { position, size in
            let start = Int(position)
            let end = min(start + Int(size), data.count)
            return data[start..<end]
        }
    }

    private struct StubBookContext: BookContext {
        var bookId: String = "book1"
        var bookTitle: String = "Test Book"
        var bookAuthor: String? = nil
        var currentSpineItemId: String
        var currentBlockId: String? = nil
        var sections: [SectionInfo]

        func chapterText(spineItemId: String) -> String? {
            nil
        }

        func searchChapter(query: String) -> [SearchResult] {
            []
        }

        func searchBook(query: String) -> [SearchResult] {
            []
        }

        func blocksAround(blockId: String, count: Int) -> [Block] {
            []
        }
    }
}

// MARK: - Chunker Tests

final class ChunkerTests: XCTestCase {
    func testTokenEstimation() {
        // ~4 chars per token
        XCTAssertEqual(Chunk.estimateTokens(""), 1)  // Minimum of 1
        XCTAssertEqual(Chunk.estimateTokens("word"), 1)
        XCTAssertEqual(Chunk.estimateTokens("Hello, world!"), 3)  // 13 chars / 4 = 3
        XCTAssertEqual(Chunk.estimateTokens(String(repeating: "a", count: 400)), 100)
    }

    func testChunkingWithSmallBlocks() {
        // Create blocks that fit within one chunk
        let blocks = (0..<5).map { ordinal in
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
        let largeText = String(repeating: "Lorem ipsum dolor sit amet. ", count: 150)  // ~4350 chars
        let blocks = (0..<3).map { ordinal in
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
        let ids = Set(chunks.map { $0.id })
        XCTAssertEqual(ids.count, chunks.count)

        // Verify ordinals are sequential
        for (index, chunk) in chunks.enumerated() {
            XCTAssertEqual(chunk.ordinal, index)
        }
    }

    func testChunkOverlap() {
        // Create enough blocks to trigger overlap
        let blocks = (0..<20).map { ordinal in
            Block(
                spineItemId: "chapter1",
                type: .paragraph,
                textContent: String(repeating: "Word ", count: 200) + "[\(ordinal)]",  // ~1000 chars each
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
            Block(spineItemId: "ch1", type: .paragraph, textContent: "Chapter 1 content", htmlContent: "<p>Chapter 1 content</p>", ordinal: 0)
        ]
        let blocks2 = [
            Block(spineItemId: "ch2", type: .paragraph, textContent: "Chapter 2 content", htmlContent: "<p>Chapter 2 content</p>", ordinal: 0)
        ]

        let chapter1 = Chapter(
            id: "ch1",
            attributedText: NSAttributedString(string: "Chapter 1 content"),
            htmlSections: [HTMLSection(html: "<p>Chapter 1 content</p>", basePath: "", blocks: blocks1, spineItemId: "ch1")],
            title: "Chapter 1"
        )
        let chapter2 = Chapter(
            id: "ch2",
            attributedText: NSAttributedString(string: "Chapter 2 content"),
            htmlSections: [HTMLSection(html: "<p>Chapter 2 content</p>", basePath: "", blocks: blocks2, spineItemId: "ch2")],
            title: "Chapter 2"
        )

        let chunks = Chunker.chunkBook(chapters: [chapter1, chapter2], bookId: "book1")

        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].chapterId, "ch1")
        XCTAssertEqual(chunks[1].chapterId, "ch2")
    }
}

// MARK: - ChunkStore Tests

final class ChunkStoreTests: XCTestCase {
    var testDbPath: URL!

    override func setUp() async throws {
        // Use a unique test database
        testDbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-chunks-\(UUID().uuidString).sqlite")
    }

    override func tearDown() async throws {
        // Clean up test database
        try? FileManager.default.removeItem(at: testDbPath)
    }

    func testIndexAndRetrieveChunks() async throws {
        let store = ChunkStore.shared

        let chunks = [
            Chunk(bookId: "test-book", chapterId: "ch1", text: "The quick brown fox jumps over the lazy dog.", blockIds: ["b1"], startOffset: 0, endOffset: 44, ordinal: 0),
            Chunk(bookId: "test-book", chapterId: "ch1", text: "Pack my box with five dozen liquor jugs.", blockIds: ["b2"], startOffset: 45, endOffset: 85, ordinal: 1),
        ]

        try await store.indexBook(chunks: chunks, bookId: "test-book")

        // Verify chunks were stored
        let retrieved = try await store.getChunks(bookId: "test-book")
        XCTAssertEqual(retrieved.count, 2)

        // Verify chunk content
        let firstChunk = retrieved.first { $0.ordinal == 0 }
        XCTAssertNotNil(firstChunk)
        XCTAssertTrue(firstChunk?.text.contains("quick brown fox") ?? false)
    }

    func testFTS5Search() async throws {
        let store = ChunkStore.shared

        let chunks = [
            Chunk(bookId: "search-book", chapterId: "ch1", text: "The monster emerged from the dark forest.", blockIds: ["b1"], startOffset: 0, endOffset: 41, ordinal: 0),
            Chunk(bookId: "search-book", chapterId: "ch1", text: "She walked through the sunny meadow.", blockIds: ["b2"], startOffset: 42, endOffset: 78, ordinal: 1),
            Chunk(bookId: "search-book", chapterId: "ch2", text: "The forest was peaceful in the morning.", blockIds: ["b3"], startOffset: 0, endOffset: 39, ordinal: 0),
        ]

        try await store.indexBook(chunks: chunks, bookId: "search-book")

        // Search for "forest"
        let results = try await store.search(query: "forest", bookId: "search-book")

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.chunk.text.contains("forest") })
    }

    func testScopedSearch() async throws {
        let store = ChunkStore.shared

        let chunks = [
            Chunk(bookId: "scope-book", chapterId: "ch1", text: "Chapter one has important content.", blockIds: ["b1"], startOffset: 0, endOffset: 34, ordinal: 0),
            Chunk(bookId: "scope-book", chapterId: "ch2", text: "Chapter two also has important content.", blockIds: ["b2"], startOffset: 0, endOffset: 39, ordinal: 0),
        ]

        try await store.indexBook(chunks: chunks, bookId: "scope-book")

        // Search scoped to ch1
        let results = try await store.search(query: "important", bookId: "scope-book", chapterIds: ["ch1"])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.chunk.chapterId, "ch1")
    }

    func testDeleteBook() async throws {
        let store = ChunkStore.shared

        let chunks = [
            Chunk(bookId: "delete-book", chapterId: "ch1", text: "This will be deleted.", blockIds: ["b1"], startOffset: 0, endOffset: 21, ordinal: 0),
        ]

        try await store.indexBook(chunks: chunks, bookId: "delete-book")

        // Verify indexed
        let isIndexed = try await store.isBookIndexed(bookId: "delete-book")
        XCTAssertTrue(isIndexed)

        // Delete
        try await store.deleteBook(bookId: "delete-book")

        // Verify deleted
        let isStillIndexed = try await store.isBookIndexed(bookId: "delete-book")
        XCTAssertFalse(isStillIndexed)
    }

    func testReindexReplacesPrevious() async throws {
        let store = ChunkStore.shared

        let chunks1 = [
            Chunk(bookId: "reindex-book", chapterId: "ch1", text: "Original content version one.", blockIds: ["b1"], startOffset: 0, endOffset: 29, ordinal: 0),
        ]

        try await store.indexBook(chunks: chunks1, bookId: "reindex-book")

        let chunks2 = [
            Chunk(bookId: "reindex-book", chapterId: "ch1", text: "New content version two.", blockIds: ["b2"], startOffset: 0, endOffset: 24, ordinal: 0),
        ]

        try await store.indexBook(chunks: chunks2, bookId: "reindex-book")

        // Should only have the new content
        let results = try await store.getChunks(bookId: "reindex-book")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results.first?.text.contains("version two") ?? false)
    }
}

// MARK: - VectorStore Tests

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
            if case .mismatchedCounts(let chunks, let embeddings) = error {
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
        let wrongDimEmbedding = (0..<128).map { _ in Float.random(in: -1...1) }

        do {
            try await store.buildIndex(bookId: dimBookId, chunks: chunks, embeddings: [wrongDimEmbedding])
            XCTFail("Expected error for invalid dimension")
        } catch let error as VectorStoreError {
            if case .invalidDimension(let expected, let actual) = error {
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
        let wrongDimQuery = (0..<128).map { _ in Float.random(in: -1...1) }

        do {
            _ = try await store.search(bookId: testBookId, queryEmbedding: wrongDimQuery, k: 1)
            XCTFail("Expected error for invalid query dimension")
        } catch let error as VectorStoreError {
            if case .invalidDimension(let expected, let actual) = error {
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
        var vector = (0..<384).map { _ in Float.random(in: -1...1) }
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        vector = vector.map { $0 / norm }
        return vector
    }
}

// MARK: - Book Chat Router Tests

final class BookChatRouterTests: XCTestCase {
    func testRoutesBookQuestion() async {
        let router = BookChatRouter()

        let result = await router.route(
            question: "In this book, what happens in chapter 3?",
            bookTitle: "Sample Book",
            bookAuthor: "Sample Author",
            conceptMap: nil
        )

        XCTAssertEqual(result.route, .book)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.8)
    }

    func testRoutesNotBookQuestion() async {
        let router = BookChatRouter()

        let result = await router.route(
            question: "What is the capital of France?",
            bookTitle: "Sample Book",
            bookAuthor: "Sample Author",
            conceptMap: nil
        )

        XCTAssertEqual(result.route, .notBook)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.8)
    }

    func testConceptMapOverridesAmbiguous() async {
        let router = BookChatRouter()

        let entity = Entity(
            id: "entity-alice",
            text: "Alice",
            type: .person,
            chapterIds: ["ch1"],
            frequency: 3,
            evidence: ["Alice opened the door."],
            salience: 0.9
        )

        let stats = ConceptMap.BuildStats(
            chapterCount: 1,
            totalBlocks: 10,
            processingTimeMs: 12,
            embeddingsUsed: false
        )

        let conceptMap = ConceptMap(
            bookId: "book-1",
            entities: [entity],
            themes: [],
            events: [],
            stats: stats
        )

        let result = await router.route(
            question: "Who is Alice?",
            bookTitle: "Sample Book",
            bookAuthor: nil,
            conceptMap: conceptMap
        )

        XCTAssertEqual(result.route, .book)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.7)
    }
}

// MARK: - Guardrails Tests

final class ExecutionGuardrailsTests: XCTestCase {
    func testToolBudgetTracksCallsAndEvidence() {
        var budget = ExecutionGuardrails.ToolBudget()

        XCTAssertTrue(budget.canMakeToolCall)
        XCTAssertFalse(budget.hasEvidence)

        for _ in 0..<ExecutionGuardrails.maxToolCalls {
            XCTAssertTrue(budget.useToolCall())
        }

        XCTAssertFalse(budget.useToolCall())
        XCTAssertFalse(budget.canMakeToolCall)

        budget.recordEvidence(count: 1)
        XCTAssertTrue(budget.hasEvidence)
    }
}
