import Foundation

/// Manages CSS for the reader
/// Philosophy: Trust publisher CSS by default, only override for pagination and safety
public final class CSSManager {

    // MARK: - House CSS

    /// Generates minimal house CSS for pagination and basic safety
    /// - Parameter fontScale: The font size multiplier
    /// - Returns: CSS string for house styles
    public static func houseCSS(fontScale: CGFloat) -> String {
        let baseFontSize = Int(16 * fontScale)

        return """
        /* House CSS - Minimal overrides for pagination */

        html {
            height: 100%;
        }

        body {
            height: 100%;
            font-size: \(baseFontSize)px;

            /* Pagination container - we own the outer margins */
            margin: 0;
            padding: 0 24px; /* Horizontal padding for readable margins */
            box-sizing: border-box;

            /* CSS columns for pagination */
            column-width: calc(100vw - 48px); /* Account for padding */
            column-gap: 48px; /* Match total padding for page transitions */
            column-fill: auto;
        }

        /* Dark mode support */
        @media (prefers-color-scheme: dark) {
            body {
                color: #FFFFFF;
                background-color: #000000;
            }
        }

        /* Safety: prevent images from breaking layout */
        img {
            max-width: 100%;
            max-height: 100vh;
            height: auto;
            object-fit: contain;
        }
        """
    }

    // MARK: - Complete CSS Generation

    /// Generates complete CSS for the reader (house CSS + publisher CSS)
    /// Publisher CSS is included as-is - we trust it by default
    /// - Parameters:
    ///   - fontScale: The font size multiplier
    ///   - publisherCSS: Optional publisher CSS to include
    /// - Returns: Complete CSS string
    public static func generateCompleteCSS(fontScale: CGFloat, publisherCSS: String? = nil) -> String {
        var css = ""

        // Publisher CSS comes first so house CSS can override if needed
        if let publisherCSS = publisherCSS, !publisherCSS.isEmpty {
            css += "/* Publisher CSS */\n"
            css += publisherCSS
            css += "\n\n"
        }

        css += houseCSS(fontScale: fontScale)

        return css
    }
}
