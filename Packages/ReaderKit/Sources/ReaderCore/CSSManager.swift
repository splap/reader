import Foundation

/// Manages CSS for the reader
/// Philosophy: Trust publisher CSS by default, only override for pagination and safety
public enum CSSManager {
    // MARK: - House CSS

    /// Generates minimal house CSS for pagination and basic safety
    /// - Parameters:
    ///   - fontScale: The font size multiplier
    ///   - marginSize: Horizontal margin in pixels (default 32)
    /// - Returns: CSS string for house styles
    public static func houseCSS(fontScale: CGFloat, marginSize: CGFloat = 32) -> String {
        let baseFontSize = 16 * fontScale
        let margin = Int(marginSize)

        return """
        /* House CSS - Minimal overrides for pagination */

        html {
            height: 100%;
            width: 100%;
        }

        :root {
            --reader-margin: \(margin)px;
        }

        body {
            height: 100%;
            font-size: \(String(format: "%.1f", baseFontSize))px;

            /* Pagination container - we own the outer margins */
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            overflow-y: hidden; /* Prevent vertical scroll during pagination */
            overflow-x: clip; /* Hard clip horizontal overflow (stronger than hidden) */
            max-width: inherit;

            /* JS sets column-width and column-gap explicitly in px */
            column-fill: auto;
            -webkit-line-box-contain: block glyphs replaced;
        }

        /* Dark mode support */
        @media (prefers-color-scheme: dark) {
            body {
                color: #FFFFFF !important;
                background-color: #000000 !important;
            }
            /* Override publisher hardcoded text colors (e.g. color:#000000)
               which would be invisible on a dark background */
            body * {
                color: inherit !important;
            }
            a[href] {
                color: #6db3f2 !important;
            }
        }

        /* Safety: prevent images from breaking layout */
        img {
            max-width: 100%;
            max-height: 100vh;
            height: auto;
            object-fit: contain;
        }

        /* Spine item boundaries - each starts on a new page */
        .spine-item-section {
            break-before: column;
        }
        .spine-item-section:first-child {
            break-before: auto;
        }

        /* Reset anchor styling for non-link anchors (bookmarks, endnote refs) */
        /* These have id but no href - they're not clickable links */
        a:not([href]) {
            color: inherit;
            text-decoration: none;
        }
        """
    }

    // MARK: - CSS Sanitization

    /// Sanitizes publisher CSS to remove rules that break CSS column pagination
    /// - Parameter css: Raw publisher CSS
    /// - Returns: Sanitized CSS safe for pagination
    public static func sanitizePublisherCSS(_ css: String) -> String {
        var result = css

        // NOTE: We intentionally do NOT sanitize percentage margins like "margin: 1.25em 45%"
        // These are commonly used for centered decorative elements (section dividers, ornaments)
        // and work correctly within CSS column layouts since the percentage is relative to the
        // column width, not the viewport.

        // Only sanitize margin-left/right when they're standalone declarations using percentages
        // that would push content to one side (e.g., margin-left: 56% would push content to the right edge)
        let sideMarginPattern = #"margin-(left|right)\s*:\s*(\d+)%\s*;"#
        if let regex = try? NSRegularExpression(pattern: sideMarginPattern, options: [.caseInsensitive]) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "/* [sanitized margin-$1] */")
        }

        // Remove percentage-based padding that could cause similar issues
        let percentPaddingPattern = #"padding(-left|-right)?\s*:\s*[^;]*\d+%[^;]*;"#
        if let regex = try? NSRegularExpression(pattern: percentPaddingPattern, options: [.caseInsensitive]) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "/* [sanitized padding] */")
        }

        // Remove explicit width declarations that could conflict with column layout
        let widthPattern = #"width\s*:\s*\d+%\s*;"#
        if let regex = try? NSRegularExpression(pattern: widthPattern, options: [.caseInsensitive]) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "/* [sanitized width] */")
        }

        return result
    }

    // MARK: - Complete CSS Generation

    /// Generates complete CSS for the reader (house CSS + publisher CSS)
    /// Publisher CSS is sanitized to remove rules that break pagination
    /// - Parameters:
    ///   - fontScale: The font size multiplier
    ///   - marginSize: Horizontal margin in pixels (default 32)
    ///   - publisherCSS: Optional publisher CSS to include
    /// - Returns: Complete CSS string
    public static func generateCompleteCSS(fontScale: CGFloat, marginSize: CGFloat = 32, publisherCSS: String? = nil) -> String {
        var css = ""

        // Publisher CSS comes first so house CSS can override if needed
        if let publisherCSS, !publisherCSS.isEmpty {
            css += "/* Publisher CSS (sanitized) */\n"
            css += sanitizePublisherCSS(publisherCSS)
            css += "\n\n"
        }

        css += houseCSS(fontScale: fontScale, marginSize: marginSize)

        return css
    }
}
