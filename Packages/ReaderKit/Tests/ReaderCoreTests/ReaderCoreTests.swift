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
}
