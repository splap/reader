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
        // Use plain text with manual styling - HTML parsing is extremely slow
        // (NSAttributedString HTML parsing spins up WebKit internally)
        return createStyledText(for: block)
    }

    private func createStyledText(for block: Block) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.label
        ]

        // Style based on block type
        switch block.type {
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

        return NSAttributedString(string: block.textContent, attributes: attributes)
    }

    private func processImageBlock(_ block: Block) -> (path: String, isFullPage: Bool)? {
        guard let path = extractImagePath(from: block.htmlContent) else {
            return nil
        }

        // Check image size in cache
        if let imageData = imageCache[path],
           let image = UIImage(data: imageData) {
            let size = image.size
            let isDecorative = size.width < Self.decorativeThreshold && size.height < Self.decorativeThreshold
            return (path, !isDecorative)
        }

        // If not in cache, assume it might be full-page
        return (path, true)
    }

    private func extractImagePath(from html: String) -> String? {
        let pattern = #"src\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range])
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
        paragraphStyle.lineSpacing = 6
        paragraphStyle.paragraphSpacing = 12

        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
    }

}
