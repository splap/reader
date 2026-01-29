import Foundation

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
    /// Lazily computed attributed text - only used by native renderer
    /// For WebView rendering, this is never accessed, saving significant time
    public var attributedText: NSAttributedString {
        if let cached = _attributedText {
            return cached
        }
        // Return empty attributed string if not provided
        // The native renderer will generate its own from htmlSections
        return NSAttributedString()
    }

    private let _attributedText: NSAttributedString?
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

    /// Standard initializer with attributed text
    public init(id: String, attributedText: NSAttributedString, htmlSections: [HTMLSection] = [], title: String? = nil, ncxLabels: [String: String] = [:], hrefToSpineItemId: [String: String] = [:]) {
        self.id = id
        _attributedText = attributedText
        self.htmlSections = htmlSections
        self.title = title
        self.ncxLabels = ncxLabels
        self.hrefToSpineItemId = hrefToSpineItemId
    }

    /// Fast initializer that skips attributed text conversion (for WebView rendering)
    public init(id: String, htmlSections: [HTMLSection], title: String? = nil, ncxLabels: [String: String] = [:], hrefToSpineItemId: [String: String] = [:]) {
        self.id = id
        _attributedText = nil
        self.htmlSections = htmlSections
        self.title = title
        self.ncxLabels = ncxLabels
        self.hrefToSpineItemId = hrefToSpineItemId
    }
}
