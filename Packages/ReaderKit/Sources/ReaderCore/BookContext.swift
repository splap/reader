import Foundation

// MARK: - Section Info

/// Lightweight info about a book section
public struct SectionInfo {
    public let spineItemId: String
    public let title: String?  // Title extracted from first heading in content
    public let ncxLabel: String?  // Label from NCX/nav file (preferred)
    public let blockCount: Int

    public init(spineItemId: String, title: String?, ncxLabel: String? = nil, blockCount: Int) {
        self.spineItemId = spineItemId
        self.title = title
        self.ncxLabel = ncxLabel
        self.blockCount = blockCount
    }

    /// The best available label for this section
    public var displayLabel: String {
        ncxLabel ?? title ?? "Untitled"
    }
}

// MARK: - Book Context Protocol

/// Protocol for accessing book content during agent tool execution
public protocol BookContext {
    /// The book's unique identifier (used for indexing)
    var bookId: String { get }

    /// The book's title
    var bookTitle: String { get }

    /// The book's author (if known)
    var bookAuthor: String? { get }

    /// The spine item ID of the current chapter/section
    var currentSpineItemId: String { get }

    /// The block ID at the current reading position (if known)
    var currentBlockId: String? { get }

    /// All sections in the book
    var sections: [SectionInfo] { get }

    /// Get the full text of a chapter/section by spine item ID
    func chapterText(spineItemId: String) -> String?

    /// Search for text in the current chapter (uses FTS index)
    func searchChapter(query: String) async -> [SearchResult]

    /// Search for text in the entire book (uses FTS index)
    func searchBook(query: String) async -> [SearchResult]

    /// Get blocks around a specific block ID
    func blocksAround(blockId: String, count: Int) -> [Block]
}

// MARK: - Reader Book Context Implementation

/// Concrete implementation of BookContext using loaded Chapter data
public final class ReaderBookContext: BookContext {
    private let chapter: Chapter
    private let _bookId: String
    private let title: String
    private let author: String?
    private var _currentSpineItemId: String
    private var _currentBlockId: String?

    public var bookId: String { _bookId }
    public var bookTitle: String { title }
    public var bookAuthor: String? { author }
    public var currentSpineItemId: String { _currentSpineItemId }
    public var currentBlockId: String? { _currentBlockId }

    public init(
        chapter: Chapter,
        bookId: String,
        bookTitle: String,
        bookAuthor: String? = nil,
        currentSpineItemId: String = "",
        currentBlockId: String? = nil
    ) {
        self.chapter = chapter
        self._bookId = bookId
        self.title = bookTitle
        self.author = bookAuthor
        self._currentSpineItemId = currentSpineItemId.isEmpty
            ? (chapter.htmlSections.first?.spineItemId ?? "")
            : currentSpineItemId
        self._currentBlockId = currentBlockId
    }

    /// Update the current reading position
    public func updatePosition(spineItemId: String, blockId: String?) {
        _currentSpineItemId = spineItemId
        _currentBlockId = blockId
    }

    // MARK: - Sections

    public var sections: [SectionInfo] {
        // Group by spine item ID to get unique sections
        var seen = Set<String>()
        var result: [SectionInfo] = []

        for section in chapter.htmlSections {
            if !seen.contains(section.spineItemId) {
                seen.insert(section.spineItemId)

                // Try to extract title from first heading block
                let sectionTitle = extractSectionTitle(from: section)

                // Count ALL blocks across all htmlSections with this spineItemId
                let totalBlockCount = chapter.htmlSections
                    .filter { $0.spineItemId == section.spineItemId }
                    .reduce(0) { $0 + $1.blocks.count }

                result.append(SectionInfo(
                    spineItemId: section.spineItemId,
                    title: sectionTitle,
                    ncxLabel: chapter.ncxLabels[section.spineItemId],
                    blockCount: totalBlockCount
                ))
            }
        }

        return result
    }

    private func extractSectionTitle(from section: HTMLSection) -> String? {
        // Look for a heading block
        for block in section.blocks {
            switch block.type {
            case .heading1, .heading2, .heading3:
                let text = block.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            default:
                continue
            }
        }
        return nil
    }

    // MARK: - Chapter Text

    public func chapterText(spineItemId: String) -> String? {
        let targetSections = chapter.htmlSections.filter { $0.spineItemId == spineItemId }

        if targetSections.isEmpty {
            return nil
        }

        let text = targetSections
            .flatMap { $0.blocks }
            .map { $0.textContent }
            .joined(separator: "\n\n")

        return text.isEmpty ? nil : text
    }

    // MARK: - Search (in-memory, instant)

    public func searchChapter(query: String) async -> [SearchResult] {
        searchBlocks(in: chapter.htmlSections.filter { $0.spineItemId == currentSpineItemId }, query: query)
    }

    public func searchBook(query: String) async -> [SearchResult] {
        searchBlocks(in: chapter.htmlSections, query: query)
    }

    /// In-memory search - fast enough for any book size
    private func searchBlocks(in sections: [HTMLSection], query: String) -> [SearchResult] {
        var results: [SearchResult] = []
        let lowercasedQuery = query.lowercased()

        for section in sections {
            for block in section.blocks {
                let lowercasedText = block.textContent.lowercased()
                if let range = lowercasedText.range(of: lowercasedQuery) {
                    results.append(SearchResult(
                        blockId: block.id,
                        spineItemId: block.spineItemId,
                        text: block.textContent,
                        matchRange: range
                    ))
                }
            }
        }

        return results
    }

    // MARK: - Context Around Block

    public func blocksAround(blockId: String, count: Int) -> [Block] {
        let allBlocks = chapter.allBlocks

        guard let centerIndex = allBlocks.firstIndex(where: { $0.id == blockId }) else {
            return []
        }

        let startIndex = max(0, centerIndex - count)
        let endIndex = min(allBlocks.count - 1, centerIndex + count)

        return Array(allBlocks[startIndex...endIndex])
    }
}
