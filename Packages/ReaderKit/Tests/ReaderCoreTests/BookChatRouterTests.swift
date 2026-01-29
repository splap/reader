@testable import ReaderCore
import XCTest

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
