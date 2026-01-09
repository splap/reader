import Foundation

/// Parses HTML content into an array of Block objects
public final class BlockParser {

    /// Tags that represent block-level content
    private static let blockTags: Set<String> = [
        "p", "h1", "h2", "h3", "h4", "h5", "h6",
        "li", "blockquote", "pre"
    ]

    public init() {}

    /// Parses HTML string into blocks for a given spine item
    /// - Parameters:
    ///   - html: The HTML content to parse
    ///   - spineItemId: The identifier for the spine item (chapter/file)
    /// - Returns: Array of Block objects extracted from the HTML
    public func parse(html: String, spineItemId: String) -> [Block] {
        var blocks: [Block] = []
        var ordinal = 0

        // Use regex to find block-level elements
        // Pattern matches opening tag, content, and closing tag
        let pattern = #"<(p|h[1-6]|li|blockquote|pre)(\s[^>]*)?>(.+?)</\1>"#

        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return blocks
        }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        for match in matches {
            guard match.numberOfRanges >= 4 else { continue }

            let tagRange = match.range(at: 1)
            let contentRange = match.range(at: 3)
            let fullRange = match.range(at: 0)

            let tagName = nsHTML.substring(with: tagRange)
            let innerHTML = nsHTML.substring(with: contentRange)
            let fullHTML = nsHTML.substring(with: fullRange)

            // Extract plain text from inner HTML
            let textContent = stripHTML(innerHTML).trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty blocks
            guard !textContent.isEmpty else { continue }

            let blockType = BlockType.from(tagName: tagName)
            let block = Block(
                spineItemId: spineItemId,
                type: blockType,
                textContent: textContent,
                htmlContent: fullHTML,
                ordinal: ordinal
            )

            blocks.append(block)
            ordinal += 1
        }

        return blocks
    }

    /// Parses HTML and returns both blocks and HTML with data-block-id attributes injected
    /// - Parameters:
    ///   - html: The HTML content to parse
    ///   - spineItemId: The identifier for the spine item
    /// - Returns: Tuple of (blocks array, modified HTML with block IDs)
    public func parseWithAnnotatedHTML(html: String, spineItemId: String) -> (blocks: [Block], annotatedHTML: String) {
        var blocks: [Block] = []
        var annotatedHTML = html
        var ordinal = 0

        // Pattern matches block elements and captures tag name, attributes, and content
        let pattern = #"<(p|h[1-6]|li|blockquote|pre)(\s[^>]*)?>(.+?)</\1>"#

        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return (blocks, html)
        }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        // Process matches in reverse order to maintain string indices
        for match in matches.reversed() {
            guard match.numberOfRanges >= 4 else { continue }

            let tagRange = match.range(at: 1)
            let attrsRange = match.range(at: 2)
            let contentRange = match.range(at: 3)
            let fullRange = match.range(at: 0)

            let tagName = nsHTML.substring(with: tagRange)
            let innerHTML = nsHTML.substring(with: contentRange)
            let existingAttrs = attrsRange.location != NSNotFound ? nsHTML.substring(with: attrsRange) : ""

            // Extract plain text
            let textContent = stripHTML(innerHTML).trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty blocks
            guard !textContent.isEmpty else { continue }

            // We're processing in reverse, so ordinal will be assigned later
            // For now, use a placeholder
            ordinal += 1
        }

        // Reset and process forward to get correct ordinals
        ordinal = 0
        var replacements: [(range: NSRange, replacement: String, block: Block)] = []

        for match in matches {
            guard match.numberOfRanges >= 4 else { continue }

            let tagRange = match.range(at: 1)
            let attrsRange = match.range(at: 2)
            let contentRange = match.range(at: 3)
            let fullRange = match.range(at: 0)

            let tagName = nsHTML.substring(with: tagRange)
            let innerHTML = nsHTML.substring(with: contentRange)
            let existingAttrs = attrsRange.location != NSNotFound ? nsHTML.substring(with: attrsRange) : ""

            let textContent = stripHTML(innerHTML).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !textContent.isEmpty else { continue }

            let blockType = BlockType.from(tagName: tagName)

            // Create the block first to get its ID
            let block = Block(
                spineItemId: spineItemId,
                type: blockType,
                textContent: textContent,
                htmlContent: nsHTML.substring(with: fullRange),
                ordinal: ordinal
            )

            blocks.append(block)

            // Build new tag with data-block-id attribute
            let newAttrs: String
            if existingAttrs.isEmpty {
                newAttrs = " data-block-id=\"\(block.id)\""
            } else {
                newAttrs = "\(existingAttrs) data-block-id=\"\(block.id)\""
            }

            let replacement = "<\(tagName)\(newAttrs)>\(innerHTML)</\(tagName)>"
            replacements.append((fullRange, replacement, block))

            ordinal += 1
        }

        // Apply replacements in reverse order
        for (range, replacement, _) in replacements.reversed() {
            annotatedHTML = (annotatedHTML as NSString).replacingCharacters(in: range, with: replacement)
        }

        return (blocks, annotatedHTML)
    }

    /// Strips HTML tags from a string, leaving only text content
    private func stripHTML(_ html: String) -> String {
        // Remove HTML tags
        var text = html.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode common HTML entities
        text = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")

        // Collapse whitespace
        text = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        return text
    }
}
