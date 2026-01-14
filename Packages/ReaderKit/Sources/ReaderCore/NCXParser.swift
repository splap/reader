import Foundation

/// Represents a navigation point from an NCX file
public struct NCXNavigationPoint {
    public let label: String
    public let contentSrc: String  // e.g., "xhtml/Chapter01.xhtml" or "Chapter01.xhtml#ch1"

    /// Extract just the file path without fragment identifier
    public var filePath: String {
        if let hashIndex = contentSrc.firstIndex(of: "#") {
            return String(contentSrc[..<hashIndex])
        }
        return contentSrc
    }
}

/// Parses EPUB NCX (Navigation Control file for XML) to extract chapter labels
public final class NCXParser: NSObject, XMLParserDelegate {
    private var navigationPoints: [NCXNavigationPoint] = []
    private var currentLabel: String?
    private var currentContentSrc: String?
    private var currentElementContent = ""
    private var isInNavLabel = false
    private var isInText = false

    public func parse(data: Data) -> [NCXNavigationPoint] {
        navigationPoints = []
        currentLabel = nil
        currentContentSrc = nil
        currentElementContent = ""
        isInNavLabel = false
        isInText = false

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        return navigationPoints
    }

    // MARK: - XMLParserDelegate

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "navLabel":
            isInNavLabel = true
            currentElementContent = ""

        case "text":
            if isInNavLabel {
                isInText = true
                currentElementContent = ""
            }

        case "content":
            if let src = attributeDict["src"] {
                currentContentSrc = src
            }

        case "navPoint":
            // Starting a new navigation point
            currentLabel = nil
            currentContentSrc = nil

        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInText {
            currentElementContent += string
        }
    }

    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "text":
            if isInText && isInNavLabel {
                currentLabel = currentElementContent.trimmingCharacters(in: .whitespacesAndNewlines)
                isInText = false
            }

        case "navLabel":
            isInNavLabel = false

        case "navPoint":
            // End of navigation point - save it if we have both label and content
            if let label = currentLabel, let src = currentContentSrc, !label.isEmpty {
                navigationPoints.append(NCXNavigationPoint(label: label, contentSrc: src))
            }
            currentLabel = nil
            currentContentSrc = nil

        default:
            break
        }
    }
}
