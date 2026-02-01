@testable import ReaderCore
import XCTest

// MARK: - ReaderBookContext Tests

final class ReaderBookContextTests: XCTestCase {
    var epubURL: URL!

    override func setUpWithError() throws {
        epubURL = try TestHelpers.makeMinimalEPUB()
    }

    override func tearDownWithError() throws {
        if let url = epubURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testInitializationFromEPUB() throws {
        let context = try ReaderBookContext(
            epubURL: epubURL,
            bookId: "test-book",
            bookTitle: "Test Book",
            bookAuthor: "Test Author",
            currentSpineIndex: 0,
            currentBlockId: nil
        )

        XCTAssertEqual(context.bookId, "test-book")
        XCTAssertEqual(context.bookTitle, "Test Book")
        XCTAssertEqual(context.bookAuthor, "Test Author")
        XCTAssertFalse(context.currentSpineItemId.isEmpty, "Should have a current spine item ID")
    }

    func testSectionsReturnsSpineItems() throws {
        let context = try ReaderBookContext(
            epubURL: epubURL,
            bookId: "test-book",
            bookTitle: "Test Book"
        )

        let sections = context.sections
        XCTAssertFalse(sections.isEmpty, "Should have at least one section")
        XCTAssertEqual(sections.first?.spineItemId, "chapter1", "First section should be chapter1")
    }

    func testChapterTextReturnsContent() throws {
        let context = try ReaderBookContext(
            epubURL: epubURL,
            bookId: "test-book",
            bookTitle: "Test Book"
        )

        let text = context.chapterText(spineItemId: "chapter1")
        XCTAssertNotNil(text, "Should return chapter text")
        XCTAssertTrue(text?.contains("Hello from EPUB") ?? false, "Text should contain EPUB content")
    }

    func testChapterTextReturnsNilForInvalidId() throws {
        let context = try ReaderBookContext(
            epubURL: epubURL,
            bookId: "test-book",
            bookTitle: "Test Book"
        )

        let text = context.chapterText(spineItemId: "nonexistent")
        XCTAssertNil(text, "Should return nil for invalid spine item ID")
    }

    func testBlockCountLoadsSection() throws {
        let context = try ReaderBookContext(
            epubURL: epubURL,
            bookId: "test-book",
            bookTitle: "Test Book"
        )

        let count = context.blockCount(forSpineItemId: "chapter1")
        XCTAssertGreaterThan(count, 0, "Should have at least one block")
    }

    func testBlockCountReturnsZeroForInvalidId() throws {
        let context = try ReaderBookContext(
            epubURL: epubURL,
            bookId: "test-book",
            bookTitle: "Test Book"
        )

        let count = context.blockCount(forSpineItemId: "nonexistent")
        XCTAssertEqual(count, 0, "Should return 0 for invalid spine item ID")
    }

    func testCurrentBlockIdIsStored() throws {
        let context = try ReaderBookContext(
            epubURL: epubURL,
            bookId: "test-book",
            bookTitle: "Test Book",
            currentSpineIndex: 0,
            currentBlockId: "block-123"
        )

        XCTAssertEqual(context.currentBlockId, "block-123", "Should store the current block ID")
    }

    func testCurrentSpineItemIdFromIndex() throws {
        let context = try ReaderBookContext(
            epubURL: epubURL,
            bookId: "test-book",
            bookTitle: "Test Book",
            currentSpineIndex: 0
        )

        XCTAssertEqual(context.currentSpineItemId, "chapter1", "Should set spine item ID from index")
    }
}

// MARK: - ToolExecutor Tests

final class ToolExecutorTests: XCTestCase {
    // MARK: - get_current_position

    func testGetCurrentPositionReturnsChapterInfo() {
        let sections = [
            SectionInfo(spineItemId: "ch1", title: nil, ncxLabel: "Chapter One", blockCount: 10),
            SectionInfo(spineItemId: "ch2", title: nil, ncxLabel: "Chapter Two", blockCount: 20),
        ]
        let context = TestHelpers.StubBookContext(currentSpineItemId: "ch1", sections: sections)
        let executor = ToolExecutor(context: context)

        let toolCall = makeToolCall(name: "get_current_position", args: [:])
        let result = runSync { await executor.execute(toolCall) }

        XCTAssertTrue(result.contains("Chapter One"), "Should include chapter name")
        XCTAssertTrue(result.contains("ch1"), "Should include spine item ID")
    }

    func testGetCurrentPositionReturnsUnknownWhenNoMatch() {
        let sections = [
            SectionInfo(spineItemId: "ch1", title: nil, ncxLabel: "Chapter One", blockCount: 10),
        ]
        let context = TestHelpers.StubBookContext(currentSpineItemId: "nonexistent", sections: sections)
        let executor = ToolExecutor(context: context)

        let toolCall = makeToolCall(name: "get_current_position", args: [:])
        let result = runSync { await executor.execute(toolCall) }

        XCTAssertTrue(result.contains("unknown"), "Should indicate position is unknown")
    }

    // MARK: - get_book_structure

    func testGetBookStructureReturnsSections() {
        let sections = [
            SectionInfo(spineItemId: "ch1", title: nil, ncxLabel: "Chapter One", blockCount: 10),
            SectionInfo(spineItemId: "ch2", title: nil, ncxLabel: "Chapter Two", blockCount: 20),
        ]
        let context = TestHelpers.StubBookContext(
            bookTitle: "My Book",
            bookAuthor: "Author Name",
            currentSpineItemId: "ch1",
            sections: sections
        )
        let executor = ToolExecutor(context: context)

        let toolCall = makeToolCall(name: "get_book_structure", args: [:])
        let result = runSync { await executor.execute(toolCall) }

        XCTAssertTrue(result.contains("My Book"), "Should include book title")
        XCTAssertTrue(result.contains("Author Name"), "Should include author")
        XCTAssertTrue(result.contains("Chapter One"), "Should include first chapter")
        XCTAssertTrue(result.contains("Chapter Two"), "Should include second chapter")
        XCTAssertTrue(result.contains("[current]"), "Should mark current chapter")
    }

    func testGetBookStructureIncludesBlockCounts() {
        let sections = [
            SectionInfo(spineItemId: "ch1", title: nil, ncxLabel: "Chapter One", blockCount: 42),
        ]
        let context = TestHelpers.StubBookContext(currentSpineItemId: "ch1", sections: sections)
        let executor = ToolExecutor(context: context)

        let toolCall = makeToolCall(name: "get_book_structure", args: [:])
        let result = runSync { await executor.execute(toolCall) }

        XCTAssertTrue(result.contains("42 blocks"), "Should include block count")
    }

    // MARK: - get_chapter_full_text

    func testGetChapterFullTextWithCurrentChapter() {
        let sections = [
            SectionInfo(spineItemId: "ch1", title: nil, ncxLabel: "Chapter One", blockCount: 10),
        ]
        var context = TestHelpers.StubBookContext(currentSpineItemId: "ch1", sections: sections)
        context.stubbedChapterText = "This is the chapter content."
        let executor = ToolExecutor(context: context)

        let toolCall = makeToolCall(name: "get_chapter_full_text", args: ["chapter_id": "current"])
        let result = runSync { await executor.execute(toolCall) }

        XCTAssertTrue(result.contains("This is the chapter content"), "Should return chapter text")
    }

    func testGetChapterFullTextWithSpecificChapterId() {
        let sections = [
            SectionInfo(spineItemId: "ch1", title: nil, ncxLabel: "Chapter One", blockCount: 10),
            SectionInfo(spineItemId: "ch2", title: nil, ncxLabel: "Chapter Two", blockCount: 20),
        ]
        var context = TestHelpers.StubBookContext(currentSpineItemId: "ch1", sections: sections)
        context.stubbedChapterText = "Chapter two content."
        let executor = ToolExecutor(context: context)

        let toolCall = makeToolCall(name: "get_chapter_full_text", args: ["chapter_id": "ch2"])
        let result = runSync { await executor.execute(toolCall) }

        XCTAssertTrue(result.contains("Chapter two content"), "Should return specific chapter text")
    }

    func testGetChapterFullTextWithInvalidChapterId() {
        let sections = [
            SectionInfo(spineItemId: "ch1", title: nil, ncxLabel: "Chapter One", blockCount: 10),
        ]
        let context = TestHelpers.StubBookContext(currentSpineItemId: "ch1", sections: sections)
        let executor = ToolExecutor(context: context)

        let toolCall = makeToolCall(name: "get_chapter_full_text", args: ["chapter_id": "nonexistent"])
        let result = runSync { await executor.execute(toolCall) }

        XCTAssertTrue(result.contains("Unknown chapter_id"), "Should return error for invalid ID")
    }

    // MARK: - get_surrounding_context

    func testGetSurroundingContextWithCurrentBlock() {
        let sections = [
            SectionInfo(spineItemId: "ch1", title: nil, ncxLabel: "Chapter One", blockCount: 10),
        ]
        let blocks = [
            Block(spineItemId: "ch1", type: .paragraph, textContent: "Previous paragraph.", htmlContent: "<p>Previous paragraph.</p>", ordinal: 3),
            Block(spineItemId: "ch1", type: .paragraph, textContent: "Current paragraph.", htmlContent: "<p>Current paragraph.</p>", ordinal: 4),
            Block(spineItemId: "ch1", type: .paragraph, textContent: "Next paragraph.", htmlContent: "<p>Next paragraph.</p>", ordinal: 5),
        ]
        // Use the generated ID from the middle block
        let currentBlockId = blocks[1].id
        var context = TestHelpers.StubBookContext(currentSpineItemId: "ch1", currentBlockId: currentBlockId, sections: sections)
        context.stubbedBlocks = blocks
        let executor = ToolExecutor(context: context)

        let toolCall = makeToolCall(name: "get_surrounding_context", args: ["block_id": "current", "radius": 1])
        let result = runSync { await executor.execute(toolCall) }

        XCTAssertTrue(result.contains("Previous paragraph"), "Should include previous block")
        XCTAssertTrue(result.contains("Current paragraph"), "Should include current block")
        XCTAssertTrue(result.contains("Next paragraph"), "Should include next block")
    }

    func testGetSurroundingContextWithNoCurrentBlock() {
        let sections = [
            SectionInfo(spineItemId: "ch1", title: nil, ncxLabel: "Chapter One", blockCount: 10),
        ]
        let context = TestHelpers.StubBookContext(currentSpineItemId: "ch1", currentBlockId: nil, sections: sections)
        let executor = ToolExecutor(context: context)

        let toolCall = makeToolCall(name: "get_surrounding_context", args: ["block_id": "current"])
        let result = runSync { await executor.execute(toolCall) }

        XCTAssertTrue(result.contains("No current position"), "Should indicate no position available")
    }

    // MARK: - Unknown tool

    func testUnknownToolReturnsError() {
        let context = TestHelpers.StubBookContext(currentSpineItemId: "ch1", sections: [])
        let executor = ToolExecutor(context: context)

        let toolCall = makeToolCall(name: "nonexistent_tool", args: [:])
        let result = runSync { await executor.execute(toolCall) }

        XCTAssertTrue(result.contains("Unknown tool"), "Should return error for unknown tool")
    }

    // MARK: - Helpers

    private func makeToolCall(name: String, args: [String: Any]) -> ToolCall {
        let argsJson = try? JSONSerialization.data(withJSONObject: args)
        let argsString = argsJson.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return ToolCall(
            id: "test-\(UUID().uuidString)",
            function: FunctionCall(name: name, arguments: argsString)
        )
    }

    private func runSync<T>(_ operation: @escaping () async -> T) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T!
        Task {
            result = await operation()
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }
}
