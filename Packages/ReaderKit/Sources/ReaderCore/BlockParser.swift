import Foundation

/// Parses HTML content into an array of Block objects
public final class BlockParser {
    /// Tags that represent block-level content
    /// NOTE: div is not included here because it often wraps other block elements
    private static let blockTags: Set<String> = [
        "p", "h1", "h2", "h3", "h4", "h5", "h6",
        "li", "blockquote", "pre",
    ]

    /// Tags that contain images
    private static let imageTags: Set<String> = ["img", "svg", "figure"]

    public init() {}

    /// Parses HTML string into blocks for a given spine item
    /// - Parameters:
    ///   - html: The HTML content to parse
    ///   - spineItemId: The identifier for the spine item (chapter/file)
    /// - Returns: Array of Block objects extracted from the HTML
    public func parse(html: String, spineItemId: String) -> [Block] {
        // Track blocks with their HTML range for proper DOM ordering
        var blockEntries: [(block: Block, range: NSRange)] = []
        var coveredRanges: [NSRange] = []

        let nsHTML = html as NSString

        // Use regex to find block-level elements
        // Pattern matches opening tag, content, and closing tag
        // NOTE: div is excluded because it often wraps other block elements (h1-h6, p, etc.)
        // and would incorrectly consume their content. Text-only divs are handled separately.
        let pattern = #"<(p|h[1-6]|li|blockquote|pre)(\s[^>]*)?>(.+?)</\1>"#

        if let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
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
                    ordinal: 0 // Will be assigned after sorting
                )

                blockEntries.append((block, fullRange))
                coveredRanges.append(fullRange)
            }
        }

        // Find text-only divs (divs with no nested block elements)
        let textDivEntries = findTextOnlyDivsWithRanges(
            in: html,
            spineItemId: spineItemId,
            existingRanges: coveredRanges
        )
        blockEntries.append(contentsOf: textDivEntries)
        for entry in textDivEntries {
            coveredRanges.append(entry.range)
        }

        // Find image blocks that aren't inside text blocks
        let imageEntries = findImageBlocksWithRanges(
            in: html,
            spineItemId: spineItemId,
            existingRanges: coveredRanges
        )
        blockEntries.append(contentsOf: imageEntries)

        // Sort by DOM position (range location) and assign ordinals
        blockEntries.sort { $0.range.location < $1.range.location }

        return blockEntries.enumerated().map { index, entry in
            Block(
                spineItemId: entry.block.spineItemId,
                type: entry.block.type,
                textContent: entry.block.textContent,
                htmlContent: entry.block.htmlContent,
                ordinal: index
            )
        }
    }

    /// Parses HTML and returns both blocks and HTML with data-block-id attributes injected
    /// - Parameters:
    ///   - html: The HTML content to parse
    ///   - spineItemId: The identifier for the spine item
    /// - Returns: Tuple of (blocks array, modified HTML with block IDs)
    public func parseWithAnnotatedHTML(html: String, spineItemId: String) -> (blocks: [Block], annotatedHTML: String) {
        var annotatedHTML = html
        var coveredRanges: [NSRange] = []

        // Track blocks with their ranges for proper DOM ordering
        var blockEntries: [(block: Block, range: NSRange)] = []

        // Also track replacements for annotated HTML (only for p/h/li/etc, not divs)
        var replacements: [(range: NSRange, replacement: String)] = []

        let nsHTML = html as NSString

        // Pattern matches block elements and captures tag name, attributes, and content
        let pattern = #"<(p|h[1-6]|li|blockquote|pre)(\s[^>]*)?>(.+?)</\1>"#

        if let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

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
                let block = Block(
                    spineItemId: spineItemId,
                    type: blockType,
                    textContent: textContent,
                    htmlContent: nsHTML.substring(with: fullRange),
                    ordinal: 0 // Will be assigned after sorting
                )

                blockEntries.append((block, fullRange))
                coveredRanges.append(fullRange)

                // Build replacement for annotated HTML
                let blockAttrs = " data-block-id=\"\(block.id)\" data-spine-item-id=\"\(spineItemId)\""
                let newAttrs = existingAttrs.isEmpty ? blockAttrs : "\(existingAttrs)\(blockAttrs)"
                let replacement = "<\(tagName)\(newAttrs)>\(innerHTML)</\(tagName)>"
                replacements.append((fullRange, replacement))
            }
        }

        // Apply replacements in reverse order for annotated HTML
        for (range, replacement) in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            annotatedHTML = (annotatedHTML as NSString).replacingCharacters(in: range, with: replacement)
        }

        // Find text-only divs
        let textDivEntries = findTextOnlyDivsWithRanges(
            in: html,
            spineItemId: spineItemId,
            existingRanges: coveredRanges
        )
        blockEntries.append(contentsOf: textDivEntries)
        for entry in textDivEntries {
            coveredRanges.append(entry.range)
        }

        // Find image blocks
        let imageEntries = findImageBlocksWithRanges(
            in: html,
            spineItemId: spineItemId,
            existingRanges: coveredRanges
        )
        blockEntries.append(contentsOf: imageEntries)

        // Sort by DOM position (range location) and assign ordinals
        blockEntries.sort { $0.range.location < $1.range.location }

        let sortedBlocks = blockEntries.enumerated().map { index, entry in
            Block(
                spineItemId: entry.block.spineItemId,
                type: entry.block.type,
                textContent: entry.block.textContent,
                htmlContent: entry.block.htmlContent,
                ordinal: index
            )
        }

        return (sortedBlocks, annotatedHTML)
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

    // MARK: - Image Block Detection

    /// Legacy wrapper for backward compatibility with parseWithAnnotatedHTML
    private func findImageBlocks(
        in html: String,
        spineItemId: String,
        existingRanges: [NSRange],
        startingOrdinal: Int
    ) -> [Block] {
        let entries = findImageBlocksWithRanges(in: html, spineItemId: spineItemId, existingRanges: existingRanges)
        return entries.enumerated().map { index, entry in
            Block(
                spineItemId: entry.block.spineItemId,
                type: entry.block.type,
                textContent: entry.block.textContent,
                htmlContent: entry.block.htmlContent,
                ordinal: startingOrdinal + index
            )
        }
    }

    /// Finds image blocks with their ranges for proper DOM ordering
    private func findImageBlocksWithRanges(
        in html: String,
        spineItemId: String,
        existingRanges: [NSRange]
    ) -> [(block: Block, range: NSRange)] {
        var entries: [(Block, NSRange)] = []
        var matchedRanges = existingRanges
        let nsHTML = html as NSString

        // Pattern for <div> containing only image content (img or svg) - most specific
        let divImagePattern = #"<div[^>]*>\s*(?:<img[^>]*>|<svg[^>]*>[\s\S]*?</svg>)\s*</div>"#

        // Pattern for <figure> elements
        let figurePattern = #"<figure[^>]*>[\s\S]*?</figure>"#

        // Pattern for <svg>...</svg> containing <image> elements
        let svgPattern = #"<svg[^>]*>[\s\S]*?<image[^>]*(?:xlink:)?href\s*=\s*["']([^"']+)["'][^>]*>[\s\S]*?</svg>"#

        // Pattern for standalone <img> tags - least specific, check last
        let imgPattern = #"<img[^>]*src\s*=\s*["']([^"']+)["'][^>]*/?\s*>"#

        let patterns = [divImagePattern, figurePattern, svgPattern, imgPattern]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else { continue }

            let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

            for match in matches {
                let matchRange = match.range(at: 0)

                let overlaps = matchedRanges.contains { existingRange in
                    NSIntersectionRange(existingRange, matchRange).length > 0
                }
                if overlaps { continue }

                let matchedHTML = nsHTML.substring(with: matchRange)
                let imagePath = extractImagePathForBlock(from: matchedHTML) ?? "image"

                let block = Block(
                    spineItemId: spineItemId,
                    type: .image,
                    textContent: imagePath,
                    htmlContent: matchedHTML,
                    ordinal: 0
                )

                entries.append((block, matchRange))
                matchedRanges.append(matchRange)
            }
        }

        return entries
    }

    /// Extracts image path from HTML for use in block identification
    private func extractImagePathForBlock(from html: String) -> String? {
        // Standard img src
        let srcPattern = #"<img[^>]*src\s*=\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: srcPattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html)
        {
            return String(html[range])
        }

        // SVG xlink:href
        let xlinkPattern = #"xlink:href\s*=\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: xlinkPattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html)
        {
            return String(html[range])
        }

        // SVG href (modern syntax)
        let hrefPattern = #"<image[^>]*href\s*=\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: hrefPattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html)
        {
            return String(html[range])
        }

        return nil
    }

    // MARK: - Text-Only Div Detection

    /// Legacy wrapper for backward compatibility with parseWithAnnotatedHTML
    private func findTextOnlyDivs(
        in html: String,
        spineItemId: String,
        existingRanges: [NSRange],
        startingOrdinal: Int
    ) -> [Block] {
        let entries = findTextOnlyDivsWithRanges(in: html, spineItemId: spineItemId, existingRanges: existingRanges)
        return entries.enumerated().map { index, entry in
            Block(
                spineItemId: entry.block.spineItemId,
                type: entry.block.type,
                textContent: entry.block.textContent,
                htmlContent: entry.block.htmlContent,
                ordinal: startingOrdinal + index
            )
        }
    }

    /// Finds div elements with their ranges for proper DOM ordering
    private func findTextOnlyDivsWithRanges(
        in html: String,
        spineItemId: String,
        existingRanges: [NSRange]
    ) -> [(block: Block, range: NSRange)] {
        var entries: [(Block, NSRange)] = []
        let nsHTML = html as NSString

        // Pattern matches div elements that don't contain nested divs.
        // Uses negative lookahead (?!<div) to avoid matching outer divs that
        // contain inner divs (which would incorrectly consume the inner div's closing tag).
        let divPattern = #"<div(\s[^>]*)?>((?:(?!<div).)+?)</div>"#

        guard let regex = try? NSRegularExpression(
            pattern: divPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return entries }

        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        // Block tags that indicate this div contains nested structure
        let nestedBlockPattern = #"<(p|h[1-6]|li|blockquote|pre|div|table|ul|ol)\s*[^>]*>"#
        let nestedBlockRegex = try? NSRegularExpression(pattern: nestedBlockPattern, options: .caseInsensitive)

        for match in matches {
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 2)

            // Skip if this range overlaps with existing blocks
            let overlaps = existingRanges.contains { existing in
                NSIntersectionRange(existing, fullRange).length > 0
            }
            if overlaps { continue }

            let innerHTML = nsHTML.substring(with: contentRange)

            // Skip if div contains nested block elements
            if let nestedBlockRegex,
               nestedBlockRegex.firstMatch(in: innerHTML, range: NSRange(location: 0, length: (innerHTML as NSString).length)) != nil
            {
                continue
            }

            // Extract text content
            let textContent = stripHTML(innerHTML).trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty divs
            guard !textContent.isEmpty else { continue }

            let fullHTML = nsHTML.substring(with: fullRange)
            let block = Block(
                spineItemId: spineItemId,
                type: .paragraph, // Text-only divs are treated as paragraphs
                textContent: textContent,
                htmlContent: fullHTML,
                ordinal: 0
            )

            entries.append((block, fullRange))
        }

        return entries
    }
}
