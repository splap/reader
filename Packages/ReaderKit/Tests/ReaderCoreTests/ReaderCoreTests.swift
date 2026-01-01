import XCTest
import UIKit
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

    func testSelectionExtractorClampsRangeAndBuildsContext() {
        let text = "ABCDEFGHIJ"
        let attributed = NSAttributedString(string: text)
        let payload = SelectionExtractor.payload(
            in: attributed,
            range: NSRange(location: 8, length: 10),
            contextLength: 2
        )

        XCTAssertEqual(payload.selectedText, "IJ")
        XCTAssertEqual(payload.contextText, "GHIJ")
        XCTAssertEqual(payload.range, NSRange(location: 8, length: 2))
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

    private func makeChapter() -> Chapter {
        let text = String(repeating: "Lorem ipsum dolor sit amet. ", count: 400)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14)
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        return Chapter(id: "sample", attributedText: attributedText, title: "Sample")
    }
}
