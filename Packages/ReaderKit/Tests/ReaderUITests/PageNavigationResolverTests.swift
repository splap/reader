@testable import ReaderUI
import XCTest

final class PageNavigationResolverTests: XCTestCase {
    // MARK: - Forward from mid-spine

    func testForwardFromMidSpine_snapsToNextPage() {
        let input = NavigationInput(startPage: 2, currentPage: 2, totalPages: 10, velocity: 1.0, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(3))
    }

    func testForwardFromSecondToLastPage_snapsToLastPage() {
        let input = NavigationInput(startPage: 8, currentPage: 8, totalPages: 10, velocity: 1.0, spineIndex: 5, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(9))
    }

    // MARK: - Backward from mid-spine

    func testBackwardFromMidSpine_snapsToPreviousPage() {
        let input = NavigationInput(startPage: 5, currentPage: 5, totalPages: 10, velocity: -1.0, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(4))
    }

    func testBackwardFromSecondPage_snapsToFirstPage() {
        let input = NavigationInput(startPage: 1, currentPage: 1, totalPages: 10, velocity: -1.0, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(0))
    }

    // MARK: - Spine transitions

    func testForwardFromLastPage_transitionsForward() {
        let input = NavigationInput(startPage: 9, currentPage: 9, totalPages: 10, velocity: 1.0, spineIndex: 5, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .transitionForward)
    }

    func testBackwardFromFirstPage_transitionsBackward() {
        let input = NavigationInput(startPage: 0, currentPage: 0, totalPages: 10, velocity: -1.0, spineIndex: 5, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .transitionBackward)
    }

    // MARK: - Bounce at book edges

    func testForwardFromLastPageOfLastSpine_bounces() {
        let input = NavigationInput(startPage: 9, currentPage: 9, totalPages: 10, velocity: 1.0, spineIndex: 19, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .bounce)
    }

    func testBackwardFromFirstPageOfFirstSpine_bounces() {
        let input = NavigationInput(startPage: 0, currentPage: 0, totalPages: 10, velocity: -1.0, spineIndex: 0, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .bounce)
    }

    // MARK: - Single-page chapters

    func testSinglePageChapter_forwardTransitions() {
        // Single page chapter: page 0 is both first and last
        let input = NavigationInput(startPage: 0, currentPage: 0, totalPages: 1, velocity: 1.0, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .transitionForward)
    }

    func testSinglePageChapter_backwardTransitions() {
        let input = NavigationInput(startPage: 0, currentPage: 0, totalPages: 1, velocity: -1.0, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .transitionBackward)
    }

    func testSinglePageChapter_firstSpine_backwardBounces() {
        let input = NavigationInput(startPage: 0, currentPage: 0, totalPages: 1, velocity: -1.0, spineIndex: 0, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .bounce)
    }

    func testSinglePageChapter_lastSpine_forwardBounces() {
        let input = NavigationInput(startPage: 0, currentPage: 0, totalPages: 1, velocity: 1.0, spineIndex: 19, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .bounce)
    }

    // MARK: - Velocity threshold

    func testVelocityBelowThreshold_snapsToCurrentPage() {
        let input = NavigationInput(startPage: 5, currentPage: 5, totalPages: 10, velocity: 0.3, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(5))
    }

    func testNegativeVelocityBelowThreshold_snapsToCurrentPage() {
        let input = NavigationInput(startPage: 5, currentPage: 5, totalPages: 10, velocity: -0.3, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(5))
    }

    func testZeroVelocity_snapsToCurrentPage() {
        let input = NavigationInput(startPage: 5, currentPage: 5, totalPages: 10, velocity: 0.0, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(5))
    }

    func testVelocityExactlyAtThreshold_snapsToCurrentPage() {
        // Must exceed, not equal the threshold
        let input = NavigationInput(startPage: 5, currentPage: 5, totalPages: 10, velocity: 0.5, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(5))
    }

    func testNegativeVelocityExactlyAtThreshold_snapsToCurrentPage() {
        let input = NavigationInput(startPage: 5, currentPage: 5, totalPages: 10, velocity: -0.5, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(5))
    }

    // Even at a spine boundary, velocity at threshold shouldn't trigger transition
    func testVelocityAtThresholdAtLastPage_snapsToCurrentPage() {
        let input = NavigationInput(startPage: 9, currentPage: 9, totalPages: 10, velocity: 0.5, spineIndex: 5, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(9))
    }

    // MARK: - Two-page spine

    func testTwoPageSpine_forwardFromFirstPage() {
        let input = NavigationInput(startPage: 0, currentPage: 0, totalPages: 2, velocity: 1.0, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(1))
    }

    func testTwoPageSpine_forwardFromLastPage() {
        let input = NavigationInput(startPage: 1, currentPage: 1, totalPages: 2, velocity: 1.0, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .transitionForward)
    }

    func testTwoPageSpine_backwardFromLastPage() {
        let input = NavigationInput(startPage: 1, currentPage: 1, totalPages: 2, velocity: -1.0, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(0))
    }

    func testTwoPageSpine_backwardFromFirstPage() {
        let input = NavigationInput(startPage: 0, currentPage: 0, totalPages: 2, velocity: -1.0, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .transitionBackward)
    }

    // MARK: - Single-spine book

    func testSingleSpineBook_forwardFromLastPage_bounces() {
        let input = NavigationInput(startPage: 9, currentPage: 9, totalPages: 10, velocity: 1.0, spineIndex: 0, totalSpines: 1)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .bounce)
    }

    func testSingleSpineBook_backwardFromFirstPage_bounces() {
        let input = NavigationInput(startPage: 0, currentPage: 0, totalPages: 10, velocity: -1.0, spineIndex: 0, totalSpines: 1)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .bounce)
    }

    func testSingleSpineBook_forwardFromMid_snaps() {
        let input = NavigationInput(startPage: 3, currentPage: 3, totalPages: 10, velocity: 1.0, spineIndex: 0, totalSpines: 1)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(4))
    }

    // MARK: - Edge cases

    func testStartPageBeyondTotalPages_treatsAsLastPage() {
        // startPage = 15 but totalPages = 10 (max page = 9)
        let input = NavigationInput(startPage: 15, currentPage: 9, totalPages: 10, velocity: 1.0, spineIndex: 3, totalSpines: 20)
        // isOnLastPage should be true (15 >= 9), so forward transition
        XCTAssertEqual(PageNavigationResolver.resolve(input), .transitionForward)
    }

    func testVelocityBelowThresholdAtBoundary_snapsToClampedPage() {
        // At a boundary but no velocity — should clamp and stay
        let input = NavigationInput(startPage: 15, currentPage: 9, totalPages: 10, velocity: 0.0, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(9))
    }

    // MARK: - Snapback (low velocity, currentPage differs from startPage)

    func testSnapback_dragForwardPastHalfway_snapsToNextPage() {
        // Started on page 5, dragged forward past halfway to page 6.
        // Low velocity — should snap to page 6 (nearest to finger).
        let input = NavigationInput(startPage: 5, currentPage: 6, totalPages: 10, velocity: 0.3, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(6))
    }

    func testSnapback_dragForwardSlightly_snapsBackToStartPage() {
        // Started on page 5, dragged forward slightly (still closest to page 5).
        // Low velocity — should snap back to page 5 (nearest to finger).
        let input = NavigationInput(startPage: 5, currentPage: 5, totalPages: 10, velocity: 0.3, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(5))
    }

    func testSnapback_dragBackwardPastHalfway_snapsToPreviousPage() {
        // Started on page 5, dragged backward past halfway to page 4.
        // Low velocity — should snap to page 4 (nearest to finger).
        let input = NavigationInput(startPage: 5, currentPage: 4, totalPages: 10, velocity: -0.3, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(4))
    }

    func testSnapback_dragBackwardSlightly_snapsBackToStartPage() {
        // Started on page 5, dragged backward slightly (still closest to page 5).
        // Low velocity — should snap back to page 5 (nearest to finger).
        let input = NavigationInput(startPage: 5, currentPage: 5, totalPages: 10, velocity: -0.3, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(5))
    }

    func testSnapback_zeroVelocityDraggedToNextPage_snapsToNextPage() {
        // Started on page 3, released exactly on page 4 with zero velocity.
        let input = NavigationInput(startPage: 3, currentPage: 4, totalPages: 10, velocity: 0.0, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(4))
    }

    func testSnapback_currentPageClamped_doesNotExceedMax() {
        // currentPage beyond bounds should be clamped to last page
        let input = NavigationInput(startPage: 8, currentPage: 15, totalPages: 10, velocity: 0.0, spineIndex: 3, totalSpines: 20)
        XCTAssertEqual(PageNavigationResolver.resolve(input), .snapToPage(9))
    }
}
