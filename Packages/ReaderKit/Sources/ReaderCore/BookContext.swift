import Foundation

// MARK: - Section Info

/// Lightweight info about a book section
public struct SectionInfo {
    public let spineItemId: String
    public let title: String? // Title extracted from first heading in content
    public let ncxLabel: String? // Label from NCX/nav file (preferred)
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

    /// Search for text in the current chapter
    func searchChapter(query: String) async -> [SearchResult]

    /// Search for text in the entire book
    func searchBook(query: String) async -> [SearchResult]

    /// Get blocks around a specific block ID
    func blocksAround(blockId: String, count: Int) -> [Block]

    /// Get the block count for a section (loads section if needed)
    func blockCount(forSpineItemId spineItemId: String) -> Int
}

// MARK: - Reader Book Context Implementation

/// Concrete implementation of BookContext that loads directly from EPUB
public final class ReaderBookContext: BookContext {
    private let epubURL: URL
    private let spineMetadata: SpineMetadata
    private let loader = EPUBLoader()

    // Cache for loaded sections
    private var loadedSections: [String: HTMLSection] = [:]

    private let _bookId: String
    private let _bookTitle: String
    private let _bookAuthor: String?
    private let _currentSpineItemId: String
    private let _currentBlockId: String?

    public var bookId: String { _bookId }
    public var bookTitle: String { _bookTitle }
    public var bookAuthor: String? { _bookAuthor }
    public var currentSpineItemId: String { _currentSpineItemId }
    public var currentBlockId: String? { _currentBlockId }

    public init(
        epubURL: URL,
        bookId: String,
        bookTitle: String,
        bookAuthor: String? = nil,
        currentSpineIndex: Int = 0,
        currentBlockId: String? = nil
    ) throws {
        self.epubURL = epubURL
        self._bookId = bookId
        self._bookTitle = bookTitle
        self._bookAuthor = bookAuthor

        // Load spine metadata (fast - no content parsing)
        self.spineMetadata = try loader.loadSpineMetadata(from: epubURL)

        // Set current spine item ID from index
        if currentSpineIndex < spineMetadata.spineItems.count {
            self._currentSpineItemId = spineMetadata.spineItems[currentSpineIndex].id
        } else {
            self._currentSpineItemId = spineMetadata.spineItems.first?.id ?? ""
        }
        self._currentBlockId = currentBlockId
    }

    // MARK: - Sections

    public var sections: [SectionInfo] {
        spineMetadata.spineItems.map { spineItem in
            SectionInfo(
                spineItemId: spineItem.id,
                title: nil, // Would need to load content to extract
                ncxLabel: spineMetadata.ncxLabels[spineItem.id],
                blockCount: 0 // Unknown without loading
            )
        }
    }

    // MARK: - Section Loading

    private func loadSection(spineItemId: String) -> HTMLSection? {
        // Check cache
        if let cached = loadedSections[spineItemId] {
            return cached
        }

        // Find index for this spine item ID
        guard let index = spineMetadata.spineItems.firstIndex(where: { $0.id == spineItemId }) else {
            return nil
        }

        // Load from EPUB
        guard let section = try? loader.loadSection(at: index, from: spineMetadata) else {
            return nil
        }

        // Cache and return
        loadedSections[spineItemId] = section
        return section
    }

    // MARK: - Chapter Text

    public func chapterText(spineItemId: String) -> String? {
        guard let section = loadSection(spineItemId: spineItemId) else {
            return nil
        }

        let text = section.blocks
            .map(\.textContent)
            .joined(separator: "\n\n")

        return text.isEmpty ? nil : text
    }

    // MARK: - Search

    public func searchChapter(query: String) async -> [SearchResult] {
        guard let section = loadSection(spineItemId: currentSpineItemId) else {
            return []
        }
        return searchBlocks(in: [section], query: query)
    }

    public func searchBook(query: String) async -> [SearchResult] {
        // Load all sections for full book search
        var allSections: [HTMLSection] = []
        for spineItem in spineMetadata.spineItems {
            if let section = loadSection(spineItemId: spineItem.id) {
                allSections.append(section)
            }
        }
        return searchBlocks(in: allSections, query: query)
    }

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
        // First check loaded sections
        for section in loadedSections.values {
            if let centerIndex = section.blocks.firstIndex(where: { $0.id == blockId }) {
                let startIndex = max(0, centerIndex - count)
                let endIndex = min(section.blocks.count - 1, centerIndex + count)
                return Array(section.blocks[startIndex ... endIndex])
            }
        }

        // Block not in cache - try loading the current section (most likely location)
        if let section = loadSection(spineItemId: currentSpineItemId) {
            if let centerIndex = section.blocks.firstIndex(where: { $0.id == blockId }) {
                let startIndex = max(0, centerIndex - count)
                let endIndex = min(section.blocks.count - 1, centerIndex + count)
                return Array(section.blocks[startIndex ... endIndex])
            }
        }

        // Still not found - search all sections (expensive but thorough)
        for spineItem in spineMetadata.spineItems {
            if loadedSections[spineItem.id] != nil { continue } // Already checked
            if let section = loadSection(spineItemId: spineItem.id) {
                if let centerIndex = section.blocks.firstIndex(where: { $0.id == blockId }) {
                    let startIndex = max(0, centerIndex - count)
                    let endIndex = min(section.blocks.count - 1, centerIndex + count)
                    return Array(section.blocks[startIndex ... endIndex])
                }
            }
        }

        return []
    }

    // MARK: - Block Count for Section

    /// Get block count for a section (loads section if needed)
    public func blockCount(forSpineItemId spineItemId: String) -> Int {
        if let section = loadSection(spineItemId: spineItemId) {
            return section.blocks.count
        }
        return 0
    }
}
