import Foundation
import ReaderCore

/// Shared HTML generation for section rendering
/// Used by both WebPageViewController (for display) and BackgroundPageCounter (for page counting)
/// This ensures identical rendering behavior between the two contexts.
public enum SectionHTMLRenderer {
    /// Generates the complete HTML for a section with explicit layout dimensions.
    /// This variant is used by BackgroundPageCounter for accurate page counting.
    /// - Parameters:
    ///   - section: The HTMLSection to render
    ///   - layoutKey: Layout configuration including viewport size, font scale, and margins
    /// - Returns: Complete HTML string ready to load into a WebView
    public static func generateSectionHTML(
        section: HTMLSection,
        layoutKey: LayoutKey
    ) -> String {
        // Extract and process body content
        let bodyContent = extractBodyContent(from: section.annotatedHTML)
        let processedHTML = processHTMLWithImages(bodyContent, basePath: section.basePath, imageCache: section.imageCache)

        // Get publisher CSS
        var publisherCSS = ""
        if let css = section.cssContent, !css.isEmpty {
            publisherCSS = css
        }

        // Generate CSS using same parameters
        let css = CSSManager.generateCompleteCSS(
            fontScale: CGFloat(layoutKey.fontScale),
            marginSize: CGFloat(layoutKey.marginSize),
            publisherCSS: publisherCSS.isEmpty ? nil : publisherCSS
        )

        let margin = layoutKey.marginSize
        let columnWidth = max(0, layoutKey.viewportWidth - (margin * 2))
        let columnGap = max(0, margin * 2)

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=\(layoutKey.viewportWidth), height=\(layoutKey.viewportHeight), initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no">
            <style>
                \(css)
                * { -webkit-tap-highlight-color: transparent; }
                body {
                    width: \(layoutKey.viewportWidth)px !important;
                    height: \(layoutKey.viewportHeight)px !important;
                    margin: 0 !important;
                    padding: \(margin)px !important;
                    overflow-y: hidden !important;
                    overflow-x: visible !important;
                    box-sizing: border-box !important;
                    column-fill: auto !important;
                    column-width: \(columnWidth)px !important;
                    column-gap: \(columnGap)px !important;
                }
                html {
                    width: \(layoutKey.viewportWidth)px !important;
                    height: \(layoutKey.viewportHeight)px !important;
                }
            </style>
        </head>
        <body>
            \(processedHTML)
        </body>
        </html>
        """
    }

    // MARK: - HTML Processing

    /// Extracts just the body content from an HTML document, stripping out
    /// <html>, <head>, and <body> wrapper tags.
    public static func extractBodyContent(from html: String) -> String {
        let bodyPattern = #"<body[^>]*>([\s\S]*?)</body>"#
        if let regex = try? NSRegularExpression(pattern: bodyPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: html.utf16.count)),
           match.numberOfRanges >= 2
        {
            let contentRange = Range(match.range(at: 1), in: html)!
            let bodyContent = String(html[contentRange])
            return fixXHTMLSelfClosingTags(bodyContent)
        }
        return fixXHTMLSelfClosingTags(html)
    }

    /// Convert XHTML self-closing non-void elements to properly closed HTML tags.
    public static func fixXHTMLSelfClosingTags(_ html: String) -> String {
        let voidElements = Set([
            "area", "base", "br", "col", "command", "embed", "hr", "img",
            "input", "keygen", "link", "meta", "param", "source", "track", "wbr",
        ])

        let pattern = #"<([a-zA-Z][a-zA-Z0-9]*)\b([^>]*?)\s*/>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return html
        }

        var result = html
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let tagNameRange = Range(match.range(at: 1), in: result) else { continue }

            let tagName = String(result[tagNameRange]).lowercased()
            if voidElements.contains(tagName) { continue }

            let attributes = if match.numberOfRanges > 2, let attrRange = Range(match.range(at: 2), in: result) {
                String(result[attrRange])
            } else {
                ""
            }

            let replacement = "<\(tagName)\(attributes)></\(tagName)>"
            result.replaceSubrange(fullRange, with: replacement)
        }

        return result
    }

    /// Process HTML to replace image src attributes with EPUB URL scheme.
    public static func processHTMLWithImages(_ html: String, basePath: String, imageCache: [String: Data]) -> String {
        var processedHTML = html

        let imgPattern = #"<img([^>]*)src\s*=\s*["\']([^"\']+)["\']([^>]*)>"#
        guard let regex = try? NSRegularExpression(pattern: imgPattern, options: [.caseInsensitive]) else {
            return html
        }

        let nsString = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            let fullMatchRange = match.range(at: 0)
            let srcRange = match.range(at: 2)
            let beforeAttrs = nsString.substring(with: match.range(at: 1))
            let afterAttrs = match.numberOfRanges > 3 ? nsString.substring(with: match.range(at: 3)) : ""

            let srcPath = nsString.substring(with: srcRange)

            let resolvedPath: String
            if srcPath.hasPrefix("../") {
                let pathComponents = srcPath.components(separatedBy: "/")
                let baseComponents = basePath.components(separatedBy: "/").filter { !$0.isEmpty }
                var finalComponents = baseComponents

                for component in pathComponents {
                    if component == ".." {
                        if !finalComponents.isEmpty {
                            finalComponents.removeLast()
                        }
                    } else if component != ".", !component.isEmpty {
                        finalComponents.append(component)
                    }
                }
                resolvedPath = finalComponents.joined(separator: "/")
            } else {
                resolvedPath = basePath.isEmpty ? srcPath : "\(basePath)/\(srcPath)"
            }

            if imageCache[resolvedPath] != nil || imageCache[(resolvedPath as NSString).lastPathComponent] != nil {
                let schemeURL = "\(EPUBURLSchemeHandler.scheme)://image/\(resolvedPath)"
                let newTag = "<img\(beforeAttrs)src=\"\(schemeURL)\"\(afterAttrs)>"
                processedHTML = (processedHTML as NSString).replacingCharacters(in: fullMatchRange, with: newTag)
            }
        }

        return processedHTML
    }
}
