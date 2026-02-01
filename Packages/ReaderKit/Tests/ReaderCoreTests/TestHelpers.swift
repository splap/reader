@testable import ReaderCore
import UIKit
import XCTest
import ZIPFoundation

/// Shared test utilities for ReaderCore tests
enum TestHelpers {
    /// Creates a chapter with repeated Lorem ipsum text for testing
    static func makeChapter() -> Chapter {
        let text = String(repeating: "Lorem ipsum dolor sit amet. ", count: 400)
        let section = HTMLSection(
            html: "<p>\(text)</p>",
            basePath: "",
            spineItemId: "chapter1"
        )
        return Chapter(id: "sample", htmlSections: [section], title: "Sample")
    }

    /// Creates a minimal valid EPUB file for testing
    static func makeMinimalEPUB() throws -> URL {
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

    /// Adds a file entry to a ZIP archive
    static func addFile(to archive: Archive, path: String, contents: String) throws {
        let data = Data(contents.utf8)
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: UInt32(data.count),
            compressionMethod: .none
        ) { position, size in
            let start = Int(position)
            let end = min(start + Int(size), data.count)
            return data[start ..< end]
        }
    }

    /// Stub implementation of BookContext for testing
    struct StubBookContext: BookContext {
        var bookId: String = "book1"
        var bookTitle: String = "Test Book"
        var bookAuthor: String? = nil
        var currentSpineItemId: String
        var currentBlockId: String? = nil
        var sections: [SectionInfo]

        // Stubbed return values for testing
        var stubbedChapterText: String? = nil
        var stubbedBlocks: [Block] = []
        var stubbedSearchResults: [SearchResult] = []

        func chapterText(spineItemId _: String) -> String? {
            stubbedChapterText
        }

        func searchChapter(query _: String) async -> [SearchResult] {
            stubbedSearchResults
        }

        func searchBook(query _: String) async -> [SearchResult] {
            stubbedSearchResults
        }

        func blocksAround(blockId _: String, count _: Int) -> [Block] {
            stubbedBlocks
        }

        func blockCount(forSpineItemId _: String) -> Int {
            stubbedBlocks.count
        }
    }
}
