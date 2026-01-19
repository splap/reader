import Foundation
import UIKit

// MARK: - Custom Attributed String Keys

extension NSAttributedString.Key {
    /// Block ID for position tracking
    public static let blockId = NSAttributedString.Key("com.splap.reader.blockId")
    /// Spine item ID for chapter identification
    public static let spineItemId = NSAttributedString.Key("com.splap.reader.spineItemId")
}

// MARK: - Conversion Result

/// Result of converting HTML sections to attributed string
public struct AttributedContent {
    /// The combined attributed string with all text content
    public let attributedString: NSAttributedString

    /// Maps block IDs to character ranges in the attributed string
    public let blockRanges: [String: NSRange]

    /// Ordered list of block IDs as they appear in the content
    public let blockOrder: [String]

    /// Full-page images extracted (imagePath, blockId, insertionIndex in block order)
    public let fullPageImages: [(imagePath: String, blockId: String, insertIndex: Int)]

    public init(
        attributedString: NSAttributedString,
        blockRanges: [String: NSRange],
        blockOrder: [String],
        fullPageImages: [(imagePath: String, blockId: String, insertIndex: Int)]
    ) {
        self.attributedString = attributedString
        self.blockRanges = blockRanges
        self.blockOrder = blockOrder
        self.fullPageImages = fullPageImages
    }
}

// MARK: - Converter

/// Converts HTML sections to attributed strings while preserving block metadata
public final class HTMLToAttributedStringConverter {

    /// Size threshold for decorative images (skip if both dimensions below this)
    public static let decorativeThreshold: CGFloat = 100

    private let imageCache: [String: Data]
    private let fontScale: CGFloat

    public init(imageCache: [String: Data], fontScale: CGFloat) {
        self.imageCache = imageCache
        self.fontScale = fontScale
    }

    /// Convert HTML sections to attributed string with block metadata
    public func convert(sections: [HTMLSection]) -> AttributedContent {
        let combined = NSMutableAttributedString()
        var blockRanges: [String: NSRange] = [:]
        var blockOrder: [String] = []
        var fullPageImages: [(String, String, Int)] = []

        for section in sections {
            for block in section.blocks {
                // Check if block is an image
                if block.type == .image {
                    if let imageInfo = processImageBlock(block) {
                        if imageInfo.isFullPage {
                            fullPageImages.append((imageInfo.path, block.id, blockOrder.count))
                        }
                        // Skip decorative and full-page images from text flow
                        continue
                    }
                }

                // Convert block HTML to attributed string
                let blockAttributed = convertBlockToAttributed(block)

                // Add paragraph spacing between blocks
                if combined.length > 0 {
                    combined.append(NSAttributedString(string: "\n\n"))
                }

                let startLocation = combined.length

                // Create mutable copy to add custom attributes
                let mutable = NSMutableAttributedString(attributedString: blockAttributed)
                let fullRange = NSRange(location: 0, length: mutable.length)
                mutable.addAttribute(.blockId, value: block.id, range: fullRange)
                mutable.addAttribute(.spineItemId, value: section.spineItemId, range: fullRange)

                combined.append(mutable)

                // Record the range for this block
                let blockRange = NSRange(location: startLocation, length: mutable.length)
                blockRanges[block.id] = blockRange
                blockOrder.append(block.id)
            }
        }

        // Apply font scaling to the entire content
        applyFontScaling(to: combined)

        // Apply default paragraph style
        applyParagraphStyle(to: combined)

        return AttributedContent(
            attributedString: combined,
            blockRanges: blockRanges,
            blockOrder: blockOrder,
            fullPageImages: fullPageImages
        )
    }

    // MARK: - Private Methods

    private func convertBlockToAttributed(_ block: Block) -> NSAttributedString {
        // Parse HTML content with inline formatting support
        return parseBlockHTML(block)
    }

    /// Parses block HTML content and returns an attributed string with inline formatting preserved
    private func parseBlockHTML(_ block: Block) -> NSAttributedString {
        let baseAttributes = attributesForBlockType(block.type)
        let result = NSMutableAttributedString()

        // Extract inner HTML content (content between opening and closing tags)
        let innerContent = extractInnerHTML(from: block.htmlContent)

        // Parse inline content with formatting
        parseInlineContent(innerContent, into: result, baseAttributes: baseAttributes)

        // If parsing produced nothing, fall back to plain text
        if result.length == 0 {
            return NSAttributedString(string: block.textContent, attributes: baseAttributes)
        }

        return result
    }

    /// Returns base attributes for a given block type
    private func attributesForBlockType(_ type: BlockType) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.label
        ]

        switch type {
        case .heading1:
            attributes[.font] = UIFont.systemFont(ofSize: 28, weight: .bold)
        case .heading2:
            attributes[.font] = UIFont.systemFont(ofSize: 24, weight: .bold)
        case .heading3:
            attributes[.font] = UIFont.systemFont(ofSize: 20, weight: .semibold)
        case .heading4:
            attributes[.font] = UIFont.systemFont(ofSize: 18, weight: .semibold)
        case .heading5:
            attributes[.font] = UIFont.systemFont(ofSize: 16, weight: .semibold)
        case .heading6:
            attributes[.font] = UIFont.systemFont(ofSize: 14, weight: .semibold)
        case .blockquote:
            attributes[.font] = UIFont.italicSystemFont(ofSize: 16)
            attributes[.foregroundColor] = UIColor.secondaryLabel
        case .preformatted:
            attributes[.font] = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            attributes[.backgroundColor] = UIColor.secondarySystemBackground
        default:
            break
        }

        return attributes
    }

    /// Extracts content between the outer HTML tags
    private func extractInnerHTML(from html: String) -> String {
        // Pattern to extract inner content of block-level elements
        let pattern = #"<(?:p|h[1-6]|li|blockquote|pre|div|figure)[^>]*>([\s\S]*)</(?:p|h[1-6]|li|blockquote|pre|div|figure)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            // If no match, return original (might be already inner content)
            return html
        }
        return String(html[range])
    }

    /// Parses inline HTML content and appends to the result with appropriate formatting
    private func parseInlineContent(
        _ html: String,
        into result: NSMutableAttributedString,
        baseAttributes: [NSAttributedString.Key: Any]
    ) {
        var currentPosition = html.startIndex
        let nsHTML = html as NSString

        // Find all inline formatting tags AND inline images
        let tagPattern = #"<(b|strong|i|em|a|span|code|u|s|sub|sup)([^>]*)>([\s\S]*?)</\1>"#
        let imgPattern = #"<img[^>]*/?>"#

        // Combine both patterns to find all elements in order
        let combinedPattern = "(\(tagPattern))|(\(imgPattern))"
        guard let regex = try? NSRegularExpression(pattern: combinedPattern, options: [.caseInsensitive]) else {
            // Fallback: just strip tags and return plain text
            let plainText = stripHTMLTags(html)
            result.append(NSAttributedString(string: plainText, attributes: baseAttributes))
            return
        }

        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        for match in matches {
            // Append any text before this tag
            let matchStart = html.index(html.startIndex, offsetBy: match.range.location)
            if matchStart > currentPosition {
                let textBefore = String(html[currentPosition..<matchStart])
                let plainText = stripHTMLTags(decodeHTMLEntities(textBefore))
                if !plainText.isEmpty {
                    result.append(NSAttributedString(string: plainText, attributes: baseAttributes))
                }
            }

            let fullMatch = nsHTML.substring(with: match.range)

            // Check if this is an img tag (self-closing, no content group)
            if fullMatch.lowercased().hasPrefix("<img") {
                // Handle inline image
                if let imageAttachment = createInlineImageAttachment(from: fullMatch, baseAttributes: baseAttributes) {
                    result.append(imageAttachment)
                }
            } else {
                // It's a formatting tag - extract tag name, attributes, and content
                // The format is: (<tagPattern>)|(<imgPattern>) so formatting match is in groups 2,3,4
                guard match.numberOfRanges >= 5 else {
                    currentPosition = html.index(html.startIndex, offsetBy: match.range.location + match.range.length)
                    continue
                }

                let tagNameRange = match.range(at: 2)
                let attrsRange = match.range(at: 3)
                let contentRange = match.range(at: 4)

                guard tagNameRange.location != NSNotFound else {
                    currentPosition = html.index(html.startIndex, offsetBy: match.range.location + match.range.length)
                    continue
                }

                let tagName = nsHTML.substring(with: tagNameRange).lowercased()
                let attributes = attrsRange.location != NSNotFound ?
                    nsHTML.substring(with: attrsRange) : ""
                let innerContent = contentRange.location != NSNotFound ?
                    nsHTML.substring(with: contentRange) : ""

                // Build attributes for this tag
                var tagAttributes = baseAttributes
                applyInlineTagAttributes(tagName: tagName, tagAttrs: attributes, to: &tagAttributes)

                // Recursively parse inner content (for nested tags like <b><i>text</i></b>)
                let innerResult = NSMutableAttributedString()
                parseInlineContent(innerContent, into: innerResult, baseAttributes: tagAttributes)

                if innerResult.length > 0 {
                    result.append(innerResult)
                } else {
                    // No nested tags, just use the inner content as plain text
                    let plainText = stripHTMLTags(decodeHTMLEntities(innerContent))
                    result.append(NSAttributedString(string: plainText, attributes: tagAttributes))
                }
            }

            // Update position
            currentPosition = html.index(html.startIndex, offsetBy: match.range.location + match.range.length)
        }

        // Append any remaining text after the last tag
        if currentPosition < html.endIndex {
            let textAfter = String(html[currentPosition...])
            let plainText = stripHTMLTags(decodeHTMLEntities(textAfter))
            if !plainText.isEmpty {
                result.append(NSAttributedString(string: plainText, attributes: baseAttributes))
            }
        }
    }

    /// Creates an NSTextAttachment for an inline image
    private func createInlineImageAttachment(
        from imgTag: String,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString? {
        guard let path = extractImagePath(from: imgTag),
              let imageData = imageCache[path],
              let image = UIImage(data: imageData) else {
            return nil
        }

        // Skip decorative images (very small)
        if image.size.width < Self.decorativeThreshold && image.size.height < Self.decorativeThreshold {
            return nil
        }

        let attachment = NSTextAttachment()
        attachment.image = image

        // Scale to fit inline - max width based on reasonable text column
        let maxInlineWidth: CGFloat = 300
        let scale = min(1.0, maxInlineWidth / image.size.width)
        attachment.bounds = CGRect(
            x: 0,
            y: 0,
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        return NSAttributedString(attachment: attachment)
    }

    /// Applies formatting attributes based on HTML tag type
    private func applyInlineTagAttributes(
        tagName: String,
        tagAttrs: String,
        to attributes: inout [NSAttributedString.Key: Any]
    ) {
        guard let baseFont = attributes[.font] as? UIFont else { return }

        switch tagName {
        case "b", "strong":
            // Add bold trait
            attributes[.font] = addBoldTrait(to: baseFont)

        case "i", "em":
            // Add italic trait
            attributes[.font] = addItalicTrait(to: baseFont)

        case "a":
            // Extract href and add link
            if let url = extractHref(from: tagAttrs) {
                attributes[.link] = url
                attributes[.foregroundColor] = UIColor.systemBlue
            }

        case "code":
            // Use monospace font
            attributes[.font] = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
            attributes[.backgroundColor] = UIColor.secondarySystemBackground

        case "u":
            // Underline
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue

        case "s":
            // Strikethrough
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue

        case "sub":
            // Subscript (smaller, lowered)
            attributes[.font] = baseFont.withSize(baseFont.pointSize * 0.75)
            attributes[.baselineOffset] = -baseFont.pointSize * 0.2

        case "sup":
            // Superscript (smaller, raised)
            attributes[.font] = baseFont.withSize(baseFont.pointSize * 0.75)
            attributes[.baselineOffset] = baseFont.pointSize * 0.3

        default:
            break
        }
    }

    /// Adds bold trait to a font
    private func addBoldTrait(to font: UIFont) -> UIFont {
        let descriptor = font.fontDescriptor
        let traits = descriptor.symbolicTraits.union(.traitBold)
        if let boldDescriptor = descriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: boldDescriptor, size: font.pointSize)
        }
        // Fallback: use bold system font
        return UIFont.boldSystemFont(ofSize: font.pointSize)
    }

    /// Adds italic trait to a font
    private func addItalicTrait(to font: UIFont) -> UIFont {
        let descriptor = font.fontDescriptor
        let traits = descriptor.symbolicTraits.union(.traitItalic)
        if let italicDescriptor = descriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: italicDescriptor, size: font.pointSize)
        }
        // Fallback: use italic system font
        return UIFont.italicSystemFont(ofSize: font.pointSize)
    }

    /// Extracts href URL from tag attributes
    private func extractHref(from attributes: String) -> URL? {
        let pattern = #"href\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)),
              let range = Range(match.range(at: 1), in: attributes) else {
            return nil
        }
        let urlString = String(attributes[range])
        return URL(string: urlString)
    }

    /// Strips HTML tags from a string, preserving line breaks
    private func stripHTMLTags(_ html: String) -> String {
        var result = html
        // Convert <br>, <br/>, <br /> to newlines BEFORE stripping tags
        result = result.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        // Remove all other HTML tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return result
    }

    /// Decodes common HTML entities
    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&#160;", with: " ")
        // Collapse multiple spaces (but NOT newlines) into single space
        result = result.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        // Trim leading/trailing whitespace from each line
        result = result.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        // Remove trailing newlines (these come from <br><br> at end of paragraphs)
        // The paragraph spacing between blocks handles this
        result = result.replacingOccurrences(of: "\\n+$", with: "", options: .regularExpression)
        // Also remove leading newlines
        result = result.replacingOccurrences(of: "^\\n+", with: "", options: .regularExpression)
        return result
    }

    private func processImageBlock(_ block: Block) -> (path: String, isFullPage: Bool)? {
        guard let path = extractImagePath(from: block.htmlContent) else {
            return nil
        }

        // Try to find image in cache with various path formats
        if let (resolvedPath, imageData) = resolveImagePath(path),
           let image = UIImage(data: imageData) {
            let size = image.size
            let isDecorative = size.width < Self.decorativeThreshold && size.height < Self.decorativeThreshold
            return (resolvedPath, !isDecorative)
        }

        // If not in cache, assume it might be full-page
        // Return the original path - the renderer will need to resolve it too
        return (path, true)
    }

    /// Resolves an image path to a cache key, trying various formats
    private func resolveImagePath(_ path: String) -> (String, Data)? {
        // Try exact path first
        if let data = imageCache[path] {
            return (path, data)
        }

        // Try just the filename
        let filename = (path as NSString).lastPathComponent
        if let data = imageCache[filename] {
            return (filename, data)
        }

        // Try without leading ../ or ./
        let cleanPath = path
            .replacingOccurrences(of: "^\\.\\.?/", with: "", options: .regularExpression)
        if let data = imageCache[cleanPath] {
            return (cleanPath, data)
        }

        // Try with common extension variations (.jpg <-> .jpeg)
        let extensions = [".jpg", ".jpeg", ".png", ".gif"]
        let baseName = (filename as NSString).deletingPathExtension

        for ext in extensions {
            let altFilename = baseName + ext
            if let data = imageCache[altFilename] {
                return (altFilename, data)
            }
        }

        return nil
    }

    private func extractImagePath(from html: String) -> String? {
        // Standard img src
        let srcPattern = #"<img[^>]*src\s*=\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: srcPattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }

        // SVG xlink:href (legacy namespace syntax)
        let xlinkPattern = #"xlink:href\s*=\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: xlinkPattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }

        // SVG href (modern syntax without xlink prefix)
        let hrefPattern = #"<image[^>]*href\s*=\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: hrefPattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }

        return nil
    }

    private func applyFontScaling(to attributed: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            guard let font = value as? UIFont else { return }
            let scaledFont = font.withSize(font.pointSize * fontScale)
            attributed.addAttribute(.font, value: scaledFont, range: range)
        }
    }

    private func applyParagraphStyle(to attributed: NSMutableAttributedString) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        // Don't use paragraphSpacing - it applies to every \n including <br> line breaks
        // The \n\n between blocks provides visual separation

        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
    }

}
