import Foundation

/// Manages CSS for the reader, implementing house CSS rules and publisher CSS sanitization
public final class CSSManager {

    // MARK: - Configuration

    /// Maximum allowed text-indent or padding-left in relative units
    private static let maxIndentRem: Double = 3.0

    /// Maximum allowed margin/padding in pixels (absolute values get capped)
    private static let maxAbsolutePixels: Double = 100.0

    // MARK: - House CSS

    /// Generates the house CSS that controls page layout and typography
    /// - Parameter fontScale: The font size multiplier
    /// - Returns: CSS string for house styles
    public static func houseCSS(fontScale: CGFloat) -> String {
        let baseFontSize = Int(16 * fontScale)

        return """
        /* House CSS - We own page margins and typography */
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        html {
            width: 100%;
            height: 100%;
            overflow: hidden;
        }

        body {
            /* Height and pagination */
            height: 100%;

            /* House margins - we control these */
            padding: 48px 0;

            /* House typography */
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            font-size: \(baseFontSize)px;
            line-height: 1.35;
            text-align: justify;

            /* Light mode colors */
            color: #000000;

            /* CSS columns for pagination - each column = viewport width */
            column-width: 100vw;
            column-gap: 0;
            column-fill: auto;
        }

        /* Apply horizontal padding and enforce text alignment on content elements */
        p, h1, h2, h3, h4, h5, h6, ul, ol, blockquote, pre, div {
            padding-left: 48px !important;
            padding-right: 48px !important;
            text-align: justify !important;
        }

        /* Dark mode support */
        @media (prefers-color-scheme: dark) {
            body {
                color: #FFFFFF;
            }

            a {
                color: #4A9EFF;
            }
        }

        /* Basic element styling */
        img {
            max-width: calc(100% - 96px);
            max-height: calc(100vh - 96px - 4em);
            width: auto;
            height: auto;
            display: block;
            margin: 0 auto;
            break-inside: avoid;
            object-fit: contain;
        }

        p, blockquote {
            margin-bottom: 0 !important;
        }

        h1, h2, h3, h4, h5, h6 {
            margin-top: 2em;
            margin-bottom: 1em;
            break-after: avoid;
        }

        /* Section headers (often marked as bold paragraphs in EPUBs) */
        p.calibre5, p > .bold, p > span > .bold {
            text-align: center !important;
            font-size: 1.2em;
            font-weight: bold;
            margin-top: 0;
            margin-bottom: 2em;
            break-before: column;
            padding-top: 48px;
        }
        """
    }

    // MARK: - Publisher CSS Sanitization

    /// Sanitizes publisher CSS to prevent pathological layouts
    /// This is the initial pass - "walk before run"
    /// - Parameter publisherCSS: Raw CSS from the EPUB
    /// - Returns: Sanitized CSS string
    public static func sanitizePublisherCSS(_ publisherCSS: String) -> String {
        var sanitized = publisherCSS

        // 1. Cap root-level margins and padding
        // Remove or limit body/html margins and padding that could conflict with house CSS
        sanitized = capRootMargins(sanitized)

        // 2. Cap indentation on blocks
        // Limit text-indent and padding-left to prevent extreme indentation on small viewports
        sanitized = capIndentation(sanitized)

        // 3. Cap absolute pixel values
        // Large absolute values break on different screen sizes
        sanitized = capAbsoluteValues(sanitized)

        // 4. Remove text-align center/right
        // House CSS enforces left alignment for readability
        sanitized = removeTextAlignCenter(sanitized)

        return sanitized
    }

    /// Caps or removes margins/padding on root elements (body, html)
    private static func capRootMargins(_ css: String) -> String {
        var result = css

        // Pattern to match body or html selectors with margin/padding
        // This is a simple approach - regex for CSS is imperfect but sufficient for now
        let rootSelectors = ["body", "html"]

        for selector in rootSelectors {
            // Remove margin and padding from root selectors
            // Replace patterns like "body { margin: 20px; padding: 10px; }"
            let patterns = [
                "\\b\(selector)\\s*\\{[^}]*margin[^;}]*;",
                "\\b\(selector)\\s*\\{[^}]*padding[^;}]*;"
            ]

            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    let range = NSRange(result.startIndex..., in: result)
                    let matches = regex.matches(in: result, range: range)

                    // Process in reverse to maintain indices
                    for match in matches.reversed() {
                        if let range = Range(match.range, in: result) {
                            // Remove the margin/padding declaration
                            var declaration = String(result[range])
                            declaration = declaration.replacingOccurrences(
                                of: "margin[^;]*;",
                                with: "",
                                options: .regularExpression
                            )
                            declaration = declaration.replacingOccurrences(
                                of: "padding[^;]*;",
                                with: "",
                                options: .regularExpression
                            )
                            result.replaceSubrange(range, with: declaration)
                        }
                    }
                }
            }
        }

        return result
    }

    /// Caps text-indent and padding-left to reasonable values
    private static func capIndentation(_ css: String) -> String {
        var result = css

        // Cap text-indent and padding-left
        let indentProperties = ["text-indent", "padding-left"]

        for property in indentProperties {
            // Match patterns like "text-indent: 50px;" or "padding-left: 5em;"
            let pattern = "(\(property)\\s*:\\s*)([^;]+)(;)"

            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                let matches = regex.matches(in: result, range: range)

                // Process in reverse to maintain indices
                for match in matches.reversed() {
                    guard match.numberOfRanges >= 4 else { continue }

                    let fullRange = match.range(at: 0)
                    let valueRange = match.range(at: 2)

                    if let fullSwiftRange = Range(fullRange, in: result),
                       let valueSwiftRange = Range(valueRange, in: result) {
                        let value = String(result[valueSwiftRange]).trimmingCharacters(in: .whitespaces)
                        let capped = capIndentValue(value)
                        let replacement = "\(property): \(capped);"
                        result.replaceSubrange(fullSwiftRange, with: replacement)
                    }
                }
            }
        }

        return result
    }

    /// Caps a single indent value (e.g., "5em" -> "3rem", "200px" -> "3rem")
    private static func capIndentValue(_ value: String) -> String {
        // Extract number and unit
        let pattern = "([0-9.]+)\\s*(px|em|rem|%|pt|)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges >= 3 else {
            return "\(maxIndentRem)rem"
        }

        let numberRange = match.range(at: 1)
        let unitRange = match.range(at: 2)

        guard let numberSwiftRange = Range(numberRange, in: value),
              let unitSwiftRange = Range(unitRange, in: value) else {
            return "\(maxIndentRem)rem"
        }

        let numberStr = String(value[numberSwiftRange])
        let unit = String(value[unitSwiftRange])

        guard let number = Double(numberStr) else {
            return "\(maxIndentRem)rem"
        }

        // Convert to rem and cap
        let remValue: Double
        switch unit.lowercased() {
        case "px":
            // Convert px to rem (assuming 16px base)
            remValue = number / 16.0
        case "em", "rem":
            remValue = number
        case "pt":
            // 1pt ≈ 1.33px
            remValue = (number * 1.33) / 16.0
        case "%":
            // % relative to parent - cap at 50% -> ~3rem equivalent
            remValue = min(number / 100.0 * 3.0, maxIndentRem)
        default:
            remValue = number / 16.0
        }

        let capped = min(remValue, maxIndentRem)
        return "\(capped)rem"
    }

    /// Caps large absolute pixel values in all properties
    private static func capAbsoluteValues(_ css: String) -> String {
        var result = css

        // Match property: value pairs with px units
        let pattern = "([a-z-]+)\\s*:\\s*([0-9.]+)px"

        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: range)

            // Process in reverse to maintain indices
            for match in matches.reversed() {
                guard match.numberOfRanges >= 3 else { continue }

                let fullRange = match.range(at: 0)
                let propertyRange = match.range(at: 1)
                let valueRange = match.range(at: 2)

                if let fullSwiftRange = Range(fullRange, in: result),
                   let propertySwiftRange = Range(propertyRange, in: result),
                   let valueSwiftRange = Range(valueRange, in: result) {

                    let property = String(result[propertySwiftRange])
                    let valueStr = String(result[valueSwiftRange])

                    if let value = Double(valueStr), value > maxAbsolutePixels {
                        // Cap to max and convert to rem for better scaling
                        let remValue = maxAbsolutePixels / 16.0
                        let replacement = "\(property): \(remValue)rem"
                        result.replaceSubrange(fullSwiftRange, with: replacement)
                    }
                }
            }
        }

        return result
    }

    /// Removes text-align: center and text-align: right declarations
    /// House CSS enforces left alignment for consistent readability
    private static func removeTextAlignCenter(_ css: String) -> String {
        var result = css

        // Match text-align properties with center or right values
        let pattern = "text-align\\s*:\\s*(center|right)\\s*;?"

        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: range)

            // Process in reverse to maintain indices
            for match in matches.reversed() {
                if let swiftRange = Range(match.range, in: result) {
                    // Remove the entire text-align declaration
                    result.replaceSubrange(swiftRange, with: "")
                }
            }
        }

        return result
    }

    // MARK: - Complete CSS Generation

    /// Generates complete CSS for the reader (house CSS + sanitized publisher CSS)
    /// - Parameters:
    ///   - fontScale: The font size multiplier
    ///   - publisherCSS: Optional publisher CSS to include
    /// - Returns: Complete CSS string
    public static func generateCompleteCSS(fontScale: CGFloat, publisherCSS: String? = nil) -> String {
        var css = houseCSS(fontScale: fontScale)

        if let publisherCSS = publisherCSS, !publisherCSS.isEmpty {
            let sanitized = sanitizePublisherCSS(publisherCSS)
            css += "\n\n/* Publisher CSS (sanitized) */\n"
            css += sanitized
        }

        return css
    }
}
