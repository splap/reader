@testable import ReaderCore
import XCTest

final class BookPageCountsTests: XCTestCase {
    func testGlobalPageCalculation() {
        // Create page counts: spine 0 has 10 pages, spine 1 has 5 pages, spine 2 has 8 pages
        let layoutKey = LayoutKey(fontScale: 1.0, marginSize: 32, viewportWidth: 800, viewportHeight: 600)
        let pageCounts = BookPageCounts(
            bookId: "test-book",
            layoutKey: layoutKey,
            spinePageCounts: [10, 5, 8]
        )

        // Total pages should be 23
        XCTAssertEqual(pageCounts.totalPages, 23)

        // Spine 0, page 0 -> global page 1
        XCTAssertEqual(pageCounts.globalPage(spineIndex: 0, localPage: 0), 1)

        // Spine 0, page 9 -> global page 10
        XCTAssertEqual(pageCounts.globalPage(spineIndex: 0, localPage: 9), 10)

        // Spine 1, page 0 -> global page 11 (after 10 pages in spine 0)
        XCTAssertEqual(pageCounts.globalPage(spineIndex: 1, localPage: 0), 11)

        // Spine 1, page 4 -> global page 15
        XCTAssertEqual(pageCounts.globalPage(spineIndex: 1, localPage: 4), 15)

        // Spine 2, page 0 -> global page 16 (after 10+5=15 pages)
        XCTAssertEqual(pageCounts.globalPage(spineIndex: 2, localPage: 0), 16)

        // Spine 2, page 7 -> global page 23
        XCTAssertEqual(pageCounts.globalPage(spineIndex: 2, localPage: 7), 23)
    }

    func testStartingPageForSpine() {
        let layoutKey = LayoutKey(fontScale: 1.0, marginSize: 32, viewportWidth: 800, viewportHeight: 600)
        let pageCounts = BookPageCounts(
            bookId: "test-book",
            layoutKey: layoutKey,
            spinePageCounts: [10, 5, 8]
        )

        // Spine 0 starts at page 1
        XCTAssertEqual(pageCounts.startingPage(forSpine: 0), 1)

        // Spine 1 starts at page 11
        XCTAssertEqual(pageCounts.startingPage(forSpine: 1), 11)

        // Spine 2 starts at page 16
        XCTAssertEqual(pageCounts.startingPage(forSpine: 2), 16)
    }

    func testGlobalPageWithInvalidSpineIndex() {
        let layoutKey = LayoutKey(fontScale: 1.0, marginSize: 32, viewportWidth: 800, viewportHeight: 600)
        let pageCounts = BookPageCounts(
            bookId: "test-book",
            layoutKey: layoutKey,
            spinePageCounts: [10, 5]
        )

        // Invalid spine index should return 1
        XCTAssertEqual(pageCounts.globalPage(spineIndex: -1, localPage: 0), 1)
        XCTAssertEqual(pageCounts.globalPage(spineIndex: 5, localPage: 0), 1)
    }

    func testSingleSpineBook() {
        let layoutKey = LayoutKey(fontScale: 1.0, marginSize: 32, viewportWidth: 800, viewportHeight: 600)
        let pageCounts = BookPageCounts(
            bookId: "test-book",
            layoutKey: layoutKey,
            spinePageCounts: [20]
        )

        XCTAssertEqual(pageCounts.totalPages, 20)
        XCTAssertEqual(pageCounts.globalPage(spineIndex: 0, localPage: 0), 1)
        XCTAssertEqual(pageCounts.globalPage(spineIndex: 0, localPage: 19), 20)
    }

    func testEmptyBook() {
        let layoutKey = LayoutKey(fontScale: 1.0, marginSize: 32, viewportWidth: 800, viewportHeight: 600)
        let pageCounts = BookPageCounts(
            bookId: "test-book",
            layoutKey: layoutKey,
            spinePageCounts: []
        )

        XCTAssertEqual(pageCounts.totalPages, 0)
    }

    func testLocalPositionFromGlobalPage() {
        // Create page counts: spine 0 has 10 pages, spine 1 has 5 pages, spine 2 has 8 pages
        let layoutKey = LayoutKey(fontScale: 1.0, marginSize: 32, viewportWidth: 800, viewportHeight: 600)
        let pageCounts = BookPageCounts(
            bookId: "test-book",
            layoutKey: layoutKey,
            spinePageCounts: [10, 5, 8]
        )

        // Global page 1 -> spine 0, local page 0
        var result = pageCounts.localPosition(forGlobalPage: 1)
        XCTAssertEqual(result.spineIndex, 0)
        XCTAssertEqual(result.localPage, 0)

        // Global page 10 -> spine 0, local page 9
        result = pageCounts.localPosition(forGlobalPage: 10)
        XCTAssertEqual(result.spineIndex, 0)
        XCTAssertEqual(result.localPage, 9)

        // Global page 11 -> spine 1, local page 0
        result = pageCounts.localPosition(forGlobalPage: 11)
        XCTAssertEqual(result.spineIndex, 1)
        XCTAssertEqual(result.localPage, 0)

        // Global page 15 -> spine 1, local page 4
        result = pageCounts.localPosition(forGlobalPage: 15)
        XCTAssertEqual(result.spineIndex, 1)
        XCTAssertEqual(result.localPage, 4)

        // Global page 16 -> spine 2, local page 0
        result = pageCounts.localPosition(forGlobalPage: 16)
        XCTAssertEqual(result.spineIndex, 2)
        XCTAssertEqual(result.localPage, 0)

        // Global page 23 -> spine 2, local page 7
        result = pageCounts.localPosition(forGlobalPage: 23)
        XCTAssertEqual(result.spineIndex, 2)
        XCTAssertEqual(result.localPage, 7)
    }

    func testLocalPositionRoundTrip() {
        // Verify that globalPage and localPosition are inverses
        let layoutKey = LayoutKey(fontScale: 1.0, marginSize: 32, viewportWidth: 800, viewportHeight: 600)
        let pageCounts = BookPageCounts(
            bookId: "test-book",
            layoutKey: layoutKey,
            spinePageCounts: [10, 5, 8]
        )

        // For every global page, converting to local and back should give the same result
        for globalPage in 1 ... pageCounts.totalPages {
            let (spineIndex, localPage) = pageCounts.localPosition(forGlobalPage: globalPage)
            let roundTripped = pageCounts.globalPage(spineIndex: spineIndex, localPage: localPage)
            XCTAssertEqual(roundTripped, globalPage, "Round trip failed for global page \(globalPage)")
        }
    }

    func testLocalPositionEdgeCases() {
        let layoutKey = LayoutKey(fontScale: 1.0, marginSize: 32, viewportWidth: 800, viewportHeight: 600)
        let pageCounts = BookPageCounts(
            bookId: "test-book",
            layoutKey: layoutKey,
            spinePageCounts: [10, 5, 8]
        )

        // Global page 0 or negative should return (0, 0)
        var result = pageCounts.localPosition(forGlobalPage: 0)
        XCTAssertEqual(result.spineIndex, 0)
        XCTAssertEqual(result.localPage, 0)

        result = pageCounts.localPosition(forGlobalPage: -5)
        XCTAssertEqual(result.spineIndex, 0)
        XCTAssertEqual(result.localPage, 0)

        // Global page past the end should return last page of last spine
        result = pageCounts.localPosition(forGlobalPage: 100)
        XCTAssertEqual(result.spineIndex, 2)
        XCTAssertEqual(result.localPage, 7)
    }
}
