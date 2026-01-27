import XCTest
@testable import ReaderCore

final class ChapterResolverTests: XCTestCase {
    func testResolveChapterIdMatchesLabelsAndIndex() {
        let sections = [
            SectionInfo(spineItemId: "s1", title: "Chapter I", ncxLabel: "I", blockCount: 10),
            SectionInfo(spineItemId: "s2", title: "Chapter II", ncxLabel: "II", blockCount: 12)
        ]
        let context = TestHelpers.StubBookContext(currentSpineItemId: "s1", sections: sections)

        XCTAssertEqual(ToolExecutor.resolveChapterId("current", in: context), "s1")
        XCTAssertEqual(ToolExecutor.resolveChapterId("s2", in: context), "s2")
        XCTAssertNil(ToolExecutor.resolveChapterId("II", in: context))
        XCTAssertNil(ToolExecutor.resolveChapterId("chapter ii", in: context))
        XCTAssertNil(ToolExecutor.resolveChapterId("2", in: context))
    }
}
