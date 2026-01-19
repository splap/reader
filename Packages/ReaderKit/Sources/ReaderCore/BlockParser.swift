import Foundation

/// Parses HTML content into an array of Block objects
public final class BlockParser {

    /// Tags that represent block-level content
    private static let blockTags: Set<String> = [
        "p", "h1", "h2", "h3", "h4", "h5", "h6",
        "li", "blockquote", "pre", "div"
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
        var blocks: [Block] = []
        var ordinal = 0
        var textBlockRanges: [NSRange] = []

        // Use regex to find block-level elements
        // Pattern matches opening tag, content, and closing tag
        // Include div for TOC entries and other block-level content
        let pattern = #"<(p|h[1-6]|li|blockquote|pre|div)(\s[^>]*)?>(.+?)</\1>"#

        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            // Still try to find image blocks even if text pattern fails
            let imageBlocks = findImageBlocks(in: html, spineItemId: spineItemId, existingRanges: [], startingOrdinal: 0)
            return imageBlocks
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
            textBlockRanges.append(fullRange)
            ordinal += 1
        }

        // Find image blocks that aren't inside text blocks
        let imageBlocks = findImageBlocks(
            in: html,
            spineItemId: spineItemId,
            existingRanges: textBlockRanges,
            startingOrdinal: ordinal
        )
        blocks.append(contentsOf: imageBlocks)

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
        var textBlockRanges: [NSRange] = []

        // Pattern matches block elements and captures tag name, attributes, and content
        // Include div for TOC entries and other block-level content
        let pattern = #"<(p|h[1-6]|li|blockquote|pre|div)(\s[^>]*)?>(.+?)</\1>"#

        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            // Still try to find image blocks even if text pattern fails
            let imageBlocks = findImageBlocks(in: html, spineItemId: spineItemId, existingRanges: [], startingOrdinal: 0)
            return (imageBlocks, html)
        }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

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
            textBlockRanges.append(fullRange)

            // Build new tag with data-block-id and data-spine-item-id attributes
            let newAttrs: String
            let blockAttrs = " data-block-id=\"\(block.id)\" data-spine-item-id=\"\(spineItemId)\""
            if existingAttrs.isEmpty {
                newAttrs = blockAttrs
            } else {
                newAttrs = "\(existingAttrs)\(blockAttrs)"
            }

            let replacement = "<\(tagName)\(newAttrs)>\(innerHTML)</\(tagName)>"
            replacements.append((fullRange, replacement, block))

            ordinal += 1
        }

        // Apply replacements in reverse order
        for (range, replacement, _) in replacements.reversed() {
            annotatedHTML = (annotatedHTML as NSString).replacingCharacters(in: range, with: replacement)
        }

        // Find image blocks that aren't inside text blocks
        let imageBlocks = findImageBlocks(
            in: html,
            spineItemId: spineItemId,
            existingRanges: textBlockRanges,
            startingOrdinal: ordinal
        )
        blocks.append(contentsOf: imageBlocks)

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

    // MARK: - Image Block Detection

    /// Finds image blocks in HTML content (standalone images, SVGs, divs containing images)
    /// - Parameters:
    ///   - html: The HTML content to search
    ///   - spineItemId: The spine item identifier
    ///   - existingRanges: Ranges already covered by text blocks (to avoid duplicates)
    ///   - startingOrdinal: The ordinal to start from
    /// - Returns: Array of image blocks found
    private func findImageBlocks(
        in html: String,
        spineItemId: String,
        existingRanges: [NSRange],
        startingOrdinal: Int
    ) -> [Block] {
        var blocks: [Block] = []
        var ordinal = startingOrdinal
        var matchedRanges = existingRanges // Track all matched ranges to avoid duplicates
        let nsHTML = html as NSString

        // Pattern for <div> containing only image content (img or svg) - most specific
        let divImagePattern = #"<div[^>]*>\s*(?:<img[^>]*>|<svg[^>]*>[\s\S]*?</svg>)\s*</div>"#

        // Pattern for <figure> elements
        let figurePattern = #"<figure[^>]*>[\s\S]*?</figure>"#

        // Pattern for <svg>...</svg> containing <image> elements
        let svgPattern = #"<svg[^>]*>[\s\S]*?<image[^>]*(?:xlink:)?href\s*=\s*["']([^"']+)["'][^>]*>[\s\S]*?</svg>"#

        // Pattern for standalone <img> tags - least specific, check last
        let imgPattern = #"<img[^>]*src\s*=\s*["']([^"']+)["'][^>]*/?\s*>"#

        // Process patterns in order of specificity (most specific first)
        // This ensures div/figure patterns match before their inner img/svg
        let patterns = [
            divImagePattern,
            figurePattern,
            svgPattern,
            imgPattern
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else { continue }

            let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

            for match in matches {
                let matchRange = match.range(at: 0)

                // Skip if this range overlaps with any already-matched range
                let overlaps = matchedRanges.contains { existingRange in
                    NSIntersectionRange(existingRange, matchRange).length > 0
                }
                if overlaps { continue }

                let matchedHTML = nsHTML.substring(with: matchRange)

                // Extract image path for textContent (used for block ID generation)
                let imagePath = extractImagePathForBlock(from: matchedHTML) ?? "image-\(ordinal)"

                let block = Block(
                    spineItemId: spineItemId,
                    type: .image,
                    textContent: imagePath,
                    htmlContent: matchedHTML,
                    ordinal: ordinal
                )

                blocks.append(block)
                matchedRanges.append(matchRange) // Track this range to prevent duplicates
                ordinal += 1
            }
        }

        return blocks
    }

    /// Extracts image path from HTML for use in block identification
    private func extractImagePathForBlock(from html: String) -> String? {
        // Standard img src
        let srcPattern = #"<img[^>]*src\s*=\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: srcPattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }

        // SVG xlink:href
        let xlinkPattern = #"xlink:href\s*=\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: xlinkPattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }

        // SVG href (modern syntax)
        let hrefPattern = #"<image[^>]*href\s*=\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: hrefPattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }

        return nil
    }
}
