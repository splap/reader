import Foundation
import OSLog
import UIKit
import ZIPFoundation

public final class EPUBLoader {
    private static let logger = Log.logger(category: "epub")

    public enum LoaderError: Error, CustomStringConvertible {
        case invalidArchive
        case missingContainer
        case missingPackage
        case missingSpine
        case emptyContent

        public var description: String {
            switch self {
            case .invalidArchive:
                "Invalid EPUB archive."
            case .missingContainer:
                "Missing META-INF/container.xml."
            case .missingPackage:
                "Missing package document."
            case .missingSpine:
                "Missing spine content in package."
            case .emptyContent:
                "No readable XHTML content."
            }
        }
    }

    private var imageCache: [String: Data] = [:]
    private var cssCache: [String: String] = [:]
    private let blockParser = BlockParser()

    public init() {}

    public func loadChapter(from url: URL, maxSections: Int = .max) throws -> Chapter {
        let totalStart = CFAbsoluteTimeGetCurrent()
        let archive = try Archive(url: url, accessMode: .read)

        guard let containerData = try data(for: "META-INF/container.xml", in: archive) else {
            throw LoaderError.missingContainer
        }

        let containerParser = EPUBContainerParser()
        containerParser.parse(containerData)
        guard let packagePath = containerParser.rootfilePath else {
            throw LoaderError.missingPackage
        }

        guard let packageData = try data(for: packagePath, in: archive) else {
            throw LoaderError.missingPackage
        }

        let package = EPUBPackageParser(packagePath: packagePath)
        package.parse(packageData)

        let spineItems = package.spine.compactMap { package.manifest[$0] }
        guard !spineItems.isEmpty else {
            throw LoaderError.missingSpine
        }

        // Parse NCX file to get chapter labels
        var ncxLabels: [String: String] = [:]
        if let ncxItem = package.manifest.values.first(where: { $0.mediaType.contains("ncx") }) {
            let ncxPath = package.resolve(ncxItem.href)
            if let ncxData = try data(for: ncxPath, in: archive) {
                let parser = NCXParser()
                let navPoints = parser.parse(data: ncxData)

                // Build map from spine item ID to NCX label
                // NCX content src is like "xhtml/Chapter01.xhtml", need to match with spine item hrefs
                for navPoint in navPoints {
                    // Find spine item that matches this nav point
                    if let matchingItem = spineItems.first(where: { item in
                        let itemPath = package.resolve(item.href)
                        // Compare file paths, ignoring fragment identifiers
                        return itemPath.hasSuffix(navPoint.filePath) || navPoint.filePath.hasSuffix(item.href)
                    }) {
                        ncxLabels[matchingItem.id] = navPoint.label
                    }
                }
                Self.logger.info("Parsed NCX: \(ncxLabels.count) labels mapped")
            }
        }

        // Extract and cache images and CSS FIRST
        let extractStart = CFAbsoluteTimeGetCurrent()
        extractImages(from: archive, package: package)
        extractCSS(from: archive, package: package)
        Self.logger.info("PERF: Image/CSS extraction took \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - extractStart))s")

        let title = package.title ?? url.deletingPathExtension().lastPathComponent
        let chapterId = url.lastPathComponent

        var htmlSections: [HTMLSection] = []
        var sectionCount = 0

        // Build mapping from file href to spine item ID for link resolution
        var hrefToSpineItemId: [String: String] = [:]
        for item in spineItems {
            // Store both the raw href and the filename for flexible matching
            hrefToSpineItemId[item.href] = item.id
            hrefToSpineItemId[(item.href as NSString).lastPathComponent] = item.id
        }

        let spineStart = CFAbsoluteTimeGetCurrent()
        var blockParseTime: Double = 0

        for item in spineItems {
            guard item.mediaType.contains("html") else { continue }
            if sectionCount >= maxSections { break }
            let resolvedPath = package.resolve(item.href)
            guard let htmlData = try data(for: resolvedPath, in: archive) else { continue }

            // Keep raw HTML for WKWebView rendering
            if let htmlString = String(data: htmlData, encoding: .utf8) {
                let basePath = (resolvedPath as NSString).deletingLastPathComponent
                // Find and include CSS content referenced by this HTML
                let cssContent = extractCSSForHTML(htmlString, basePath: basePath)

                // Use spine item ID for block identification
                let spineItemId = item.id

                // Parse HTML into blocks and generate annotated HTML with data-block-id attributes
                let blockStart = CFAbsoluteTimeGetCurrent()
                let (blocks, annotatedHTML) = blockParser.parseWithAnnotatedHTML(
                    html: htmlString,
                    spineItemId: spineItemId
                )
                blockParseTime += CFAbsoluteTimeGetCurrent() - blockStart

                htmlSections.append(HTMLSection(
                    html: htmlString,
                    annotatedHTML: annotatedHTML,
                    basePath: basePath,
                    imageCache: imageCache,
                    cssContent: cssContent,
                    blocks: blocks,
                    spineItemId: spineItemId
                ))
                sectionCount += 1
            }
        }

        let spineTime = CFAbsoluteTimeGetCurrent() - spineStart
        Self.logger.info("PERF: Spine processing took \(String(format: "%.3f", spineTime))s (blockParse: \(String(format: "%.3f", blockParseTime))s)")

        if htmlSections.isEmpty {
            throw LoaderError.emptyContent
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - totalStart
        Self.logger.info("PERF: Total EPUB load took \(String(format: "%.3f", totalTime))s for \(sectionCount) sections, \(htmlSections.count) htmlSections")

        // Use fast initializer - skip NSAttributedString conversion (saves ~1s for large books)
        return Chapter(id: chapterId, htmlSections: htmlSections, title: title, ncxLabels: ncxLabels, hrefToSpineItemId: hrefToSpineItemId)
    }

    private func data(for path: String, in archive: Archive) throws -> Data? {
        guard let entry = archive[path] else { return nil }
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return data
    }

    private func extractImages(from archive: Archive, package: EPUBPackageParser) {
        for (_, item) in package.manifest {
            guard item.mediaType.hasPrefix("image/") else { continue }
            let imagePath = package.resolve(item.href)
            if let imageData = try? data(for: imagePath, in: archive) {
                imageCache[imagePath] = imageData
                // Also cache without leading path components for relative references
                let filename = (imagePath as NSString).lastPathComponent
                imageCache[filename] = imageData
            }
        }
        Self.logger.debug("Cached \(imageCache.count) images from EPUB")
    }

    private func extractCSS(from archive: Archive, package: EPUBPackageParser) {
        for (_, item) in package.manifest {
            guard item.mediaType == "text/css" else { continue }
            let cssPath = package.resolve(item.href)
            if let cssData = try? data(for: cssPath, in: archive),
               let cssString = String(data: cssData, encoding: .utf8)
            {
                cssCache[cssPath] = cssString
                // Also cache by filename for relative references
                let filename = (cssPath as NSString).lastPathComponent
                cssCache[filename] = cssString
            }
        }
        Self.logger.debug("Cached \(cssCache.count) CSS files from EPUB")
    }

    private func extractCSSForHTML(_ html: String, basePath: String) -> String? {
        // Find CSS link tags in HTML: <link href="epub.css" rel="stylesheet" ...>
        let pattern = #"<link[^>]+href\s*=\s*["\']([^"\']+\.css)["\'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let nsHtml = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length))

        var combinedCSS = ""
        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let hrefRange = match.range(at: 1)
            let href = nsHtml.substring(with: hrefRange)

            // Try to find CSS in cache
            let resolvedPath = basePath.isEmpty ? href : (basePath as NSString).appendingPathComponent(href)
            if let css = cssCache[resolvedPath] ?? cssCache[href] ?? cssCache[(href as NSString).lastPathComponent] {
                combinedCSS += css + "\n"
            }
        }

        return combinedCSS.isEmpty ? nil : combinedCSS
    }
}

private final class EPUBContainerParser: NSObject, XMLParserDelegate {
    private(set) var rootfilePath: String?

    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        guard elementName == "rootfile" || qName == "rootfile" else { return }
        if let path = attributeDict["full-path"] {
            rootfilePath = path
        }
    }
}

private final class EPUBPackageParser: NSObject, XMLParserDelegate {
    private(set) var title: String?
    private(set) var manifest: [String: EPUBManifestItem] = [:]
    private(set) var spine: [String] = []

    private let packagePath: String
    private var readingTitle = false
    private var titleBuffer = ""

    init(packagePath: String) {
        self.packagePath = packagePath
    }

    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        let trimmedTitle = titleBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            title = trimmedTitle
        }
    }

    func resolve(_ href: String) -> String {
        let base = (packagePath as NSString).deletingLastPathComponent
        if base.isEmpty {
            return href
        }
        return (base as NSString).appendingPathComponent(href)
    }

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "item":
            if let id = attributeDict["id"],
               let href = attributeDict["href"],
               let mediaType = attributeDict["media-type"]
            {
                manifest[id] = EPUBManifestItem(id: id, href: href, mediaType: mediaType)
            }
        case "itemref":
            if let idref = attributeDict["idref"] {
                spine.append(idref)
            }
        default:
            if elementName.hasSuffix("title") || qName?.hasSuffix("title") == true {
                readingTitle = true
                titleBuffer = ""
            }
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        if readingTitle {
            titleBuffer.append(string)
        }
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName qName: String?
    ) {
        if elementName.hasSuffix("title") || qName?.hasSuffix("title") == true {
            readingTitle = false
        }
    }
}

private struct EPUBManifestItem {
    let id: String
    let href: String
    let mediaType: String
}
