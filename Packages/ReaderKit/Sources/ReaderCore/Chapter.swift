import Foundation
import OSLog

public struct HTMLSection {
    /// Original HTML from EPUB
    public let html: String

    /// HTML with data-block-id attributes injected for position tracking
    public let annotatedHTML: String

    /// Base path for resolving relative URLs
    public let basePath: String

    /// Cached image data keyed by path
    public let imageCache: [String: Data]

    /// Publisher CSS content extracted from EPUB
    public let cssContent: String?

    /// Parsed blocks from this section
    public let blocks: [Block]

    /// Spine item identifier (for block positioning)
    public let spineItemId: String

    public init(
        html: String,
        annotatedHTML: String? = nil,
        basePath: String,
        imageCache: [String: Data] = [:],
        cssContent: String? = nil,
        blocks: [Block] = [],
        spineItemId: String = ""
    ) {
        self.html = html
        self.annotatedHTML = annotatedHTML ?? html
        self.basePath = basePath
        self.imageCache = imageCache
        self.cssContent = cssContent
        self.blocks = blocks
        self.spineItemId = spineItemId
    }
}

public struct Chapter {
    public let id: String
    public let htmlSections: [HTMLSection]
    public let title: String?
    public let ncxLabels: [String: String] // Map from spineItemId to NCX label
    public let hrefToSpineItemId: [String: String] // Map from file href to spineItemId for link resolution

    /// All blocks across all sections, flattened for easy lookup
    public var allBlocks: [Block] {
        htmlSections.flatMap(\.blocks)
    }

    /// Lookup a block by ID
    public func block(withId blockId: String) -> Block? {
        allBlocks.first { $0.id == blockId }
    }

    /// Find the section index containing a block
    public func sectionIndex(forBlockId blockId: String) -> Int? {
        for (index, section) in htmlSections.enumerated() {
            if section.blocks.contains(where: { $0.id == blockId }) {
                return index
            }
        }
        return nil
    }

    /// Table of contents built from NCX labels, in spine order
    public var tableOfContents: [TOCItem] {
        var items: [TOCItem] = []
        for (index, section) in htmlSections.enumerated() {
            if let label = ncxLabels[section.spineItemId] {
                items.append(TOCItem(
                    id: section.spineItemId,
                    label: label,
                    sectionIndex: index
                ))
            }
        }
        return items
    }

    public init(id: String, htmlSections: [HTMLSection], title: String? = nil, ncxLabels: [String: String] = [:], hrefToSpineItemId: [String: String] = [:]) {
        self.id = id
        self.htmlSections = htmlSections
        self.title = title
        self.ncxLabels = ncxLabels
        self.hrefToSpineItemId = hrefToSpineItemId
    }
}

// MARK: - LazyChapter

/// A lazy-loading chapter that loads sections on-demand
/// This avoids the expensive upfront parsing of all spine items
public final class LazyChapter {
    private static let logger = Log.logger(category: "lazy-chapter")

    public let id: String
    public let title: String?
    public let spineMetadata: SpineMetadata

    /// Loaded sections cache (thread-safe access via loadQueue)
    private var loadedSections: [Int: HTMLSection] = [:]
    private let loadQueue = DispatchQueue(label: "com.splap.reader.lazyChapter", attributes: .concurrent)

    /// Loader instance for on-demand section parsing
    private let loader = EPUBLoader()

    /// Total number of spine items (sections/chapters)
    public var sectionCount: Int { spineMetadata.sectionCount }

    /// NCX labels for chapter titles
    public var ncxLabels: [String: String] { spineMetadata.ncxLabels }

    /// Map from file href to spineItemId for link resolution
    public var hrefToSpineItemId: [String: String] { spineMetadata.hrefToSpineItemId }

    public init(metadata: SpineMetadata) {
        id = metadata.epubURL.lastPathComponent
        title = metadata.title
        spineMetadata = metadata
    }

    /// Get section at index, loading on-demand if needed
    /// - Parameter index: The spine item index
    /// - Returns: The HTMLSection for this index
    /// - Throws: EPUBLoader.LoaderError if section cannot be loaded
    public func section(at index: Int) throws -> HTMLSection {
        // Check cache first (read-only, concurrent access is safe)
        if let cached = loadQueue.sync(execute: { loadedSections[index] }) {
            return cached
        }

        // Load the section (this is the expensive operation)
        let section = try loader.loadSection(at: index, from: spineMetadata)

        // Cache the loaded section (barrier for write)
        loadQueue.async(flags: .barrier) { [weak self] in
            self?.loadedSections[index] = section
        }

        return section
    }

    /// Check if section is already loaded (cached)
    /// - Parameter index: The spine item index
    /// - Returns: true if section is in cache
    public func isSectionLoaded(at index: Int) -> Bool {
        loadQueue.sync { loadedSections[index] != nil }
    }

    /// Preload sections in background
    /// - Parameters:
    ///   - startIndex: Starting spine index
    ///   - count: Number of sections to preload
    public func preloadSections(from startIndex: Int, count: Int) {
        let endIndex = min(startIndex + count, sectionCount)

        for index in startIndex ..< endIndex {
            // Skip already loaded sections
            if isSectionLoaded(at: index) { continue }

            // Load in background
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                do {
                    _ = try self.section(at: index)
                    Self.logger.debug("PRELOAD: Loaded section \(index)")
                } catch {
                    Self.logger.error("PRELOAD: Failed to load section \(index): \(error)")
                }
            }
        }
    }

    /// Table of contents built from NCX labels, in spine order
    public var tableOfContents: [TOCItem] {
        var items: [TOCItem] = []
        for (index, spineItem) in spineMetadata.spineItems.enumerated() {
            if let label = ncxLabels[spineItem.id] {
                items.append(TOCItem(
                    id: spineItem.id,
                    label: label,
                    sectionIndex: index
                ))
            }
        }
        return items
    }

    /// Get spine item ID for a given index
    public func spineItemId(at index: Int) -> String? {
        guard index >= 0, index < sectionCount else { return nil }
        return spineMetadata.spineItems[index].id
    }

    /// Find section index for a spine item ID
    public func sectionIndex(forSpineItemId spineItemId: String) -> Int? {
        spineMetadata.spineItems.firstIndex { $0.id == spineItemId }
    }
}
