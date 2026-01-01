import Foundation
import OSLog
import UIKit
import ZIPFoundation

public final class EPUBLoader {
    private static let logger = Logger(subsystem: "com.example.reader", category: "epub")

    public enum LoaderError: Error, CustomStringConvertible {
        case invalidArchive
        case missingContainer
        case missingPackage
        case missingSpine
        case emptyContent

        public var description: String {
            switch self {
            case .invalidArchive:
                return "Invalid EPUB archive."
            case .missingContainer:
                return "Missing META-INF/container.xml."
            case .missingPackage:
                return "Missing package document."
            case .missingSpine:
                return "Missing spine content in package."
            case .emptyContent:
                return "No readable XHTML content."
            }
        }
    }

    public init() {}

    public func loadChapter(from url: URL, maxSections: Int = .max) throws -> Chapter {
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

        let title = package.title ?? url.deletingPathExtension().lastPathComponent
        let chapterId = url.lastPathComponent

        let combined = NSMutableAttributedString()
        var sectionCount = 0

        for item in spineItems {
            guard item.mediaType.contains("html") else { continue }
            if sectionCount >= maxSections { break }
            let resolvedPath = package.resolve(item.href)
            guard let htmlData = try data(for: resolvedPath, in: archive) else { continue }
            let section = attributedString(fromHTML: htmlData)
            if !containsReadableText(section) { continue }

            if combined.length > 0 {
                combined.append(NSAttributedString(string: "\n\n"))
            }
            combined.append(section)
            sectionCount += 1
        }

        if combined.length == 0 {
            throw LoaderError.emptyContent
        }

        applyDefaultFontIfNeeded(to: combined)
        applyDefaultColorIfNeeded(to: combined)
#if DEBUG
        Self.logger.debug(
            "Loaded EPUB \(url.lastPathComponent, privacy: .public) sections=\(sectionCount, privacy: .public) length=\(combined.length, privacy: .public)"
        )
#endif
        return Chapter(id: chapterId, attributedText: combined, title: title)
    }

    private func data(for path: String, in archive: Archive) throws -> Data? {
        guard let entry = archive[path] else { return nil }
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return data
    }

    private func attributedString(fromHTML data: Data) -> NSAttributedString {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed
        }

        let fallback = String(data: data, encoding: .utf8) ?? ""
        return NSAttributedString(string: fallback)
    }

    private func applyDefaultFontIfNeeded(to attributed: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        let baseFont = UIFont.systemFont(ofSize: 16)

        attributed.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            if value == nil {
                attributed.addAttribute(.font, value: baseFont, range: range)
            }
        }
    }

    private func applyDefaultColorIfNeeded(to attributed: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        let baseColor = UIColor.label

        attributed.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
            if value == nil {
                attributed.addAttribute(.foregroundColor, value: baseColor, range: range)
            }
        }
    }

    private func containsReadableText(_ attributed: NSAttributedString) -> Bool {
        let filtered = attributed.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !filtered.isEmpty
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
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
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
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "item":
            if let id = attributeDict["id"],
               let href = attributeDict["href"],
               let mediaType = attributeDict["media-type"] {
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

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if readingTitle {
            titleBuffer.append(string)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
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
