import Combine
import Foundation
import OSLog
import ReaderCore
import UIKit
import WebKit

/// Background page counter that renders spine items off-screen to count total pages
/// Uses a single hidden WebView to sequentially process each spine item
@MainActor
public final class BackgroundPageCounter {
    private static let logger = Log.logger(category: "page-counter")

    /// Status of the background counting operation
    public enum Status: Equatable {
        case idle
        case counting(completed: Int, total: Int)
        case complete(BookPageCounts)
        case failed(String)

        public static func == (lhs: Status, rhs: Status) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle):
                true
            case let (.counting(c1, t1), .counting(c2, t2)):
                c1 == c2 && t1 == t2
            case let (.complete(p1), .complete(p2)):
                p1 == p2
            case let (.failed(e1), .failed(e2)):
                e1 == e2
            default:
                false
            }
        }
    }

    /// Current status of the counter
    @Published public private(set) var status: Status = .idle

    /// Convenience computed property for current page counts (if complete)
    public var pageCounts: BookPageCounts? {
        if case let .complete(counts) = status {
            return counts
        }
        return nil
    }

    /// Convenience computed property to check if counting is complete
    public var isComplete: Bool {
        if case .complete = status {
            return true
        }
        return false
    }

    private var countingTask: Task<Void, Never>?
    private var hiddenWebView: WKWebView?
    private var urlSchemeHandler: EPUBURLSchemeHandler?
    private var currentContinuation: CheckedContinuation<Int, Error>?

    public init() {}

    /// Start counting pages for all spine items
    /// - Parameters:
    ///   - htmlSections: The HTML sections (spine items) to count
    ///   - bookId: Book identifier for caching
    ///   - layoutKey: Current layout configuration
    public func startCounting(
        htmlSections: [HTMLSection],
        bookId: String,
        layoutKey: LayoutKey
    ) {
        // Cancel any existing counting task
        cancel()

        guard !htmlSections.isEmpty else {
            Self.logger.warning("No HTML sections to count")
            status = .complete(BookPageCounts(bookId: bookId, layoutKey: layoutKey, spinePageCounts: []))
            return
        }

        // Check cache first
        Task {
            if let cached = await BookPageCountsCache.shared.get(bookId: bookId, layoutKey: layoutKey) {
                Self.logger.info("Using cached page counts for book \(bookId)")
                status = .complete(cached)
                return
            }

            // Start counting in background
            countingTask = Task { [weak self] in
                await self?.performCounting(
                    htmlSections: htmlSections,
                    bookId: bookId,
                    layoutKey: layoutKey
                )
            }
        }
    }

    /// Cancel any in-progress counting
    public func cancel() {
        countingTask?.cancel()
        countingTask = nil
        hiddenWebView?.stopLoading()
        hiddenWebView = nil
        urlSchemeHandler = nil
        currentContinuation?.resume(throwing: CancellationError())
        currentContinuation = nil
        status = .idle
    }

    // MARK: - Private Implementation

    private func performCounting(
        htmlSections: [HTMLSection],
        bookId: String,
        layoutKey: LayoutKey
    ) async {
        let totalSpines = htmlSections.count
        status = .counting(completed: 0, total: totalSpines)

        Self.logger.info("Starting page count for \(totalSpines) spine items, layout: \(layoutKey.hashString)")

        // Create hidden WebView with same configuration as main renderer
        let webView = createHiddenWebView(htmlSections: htmlSections, layoutKey: layoutKey)
        hiddenWebView = webView

        var spinePageCounts: [Int] = []

        for (index, section) in htmlSections.enumerated() {
            if Task.isCancelled {
                Self.logger.info("Page counting cancelled at spine \(index)")
                return
            }

            do {
                let pageCount = try await countPages(
                    for: section,
                    webView: webView,
                    layoutKey: layoutKey
                )
                spinePageCounts.append(pageCount)

                Self.logger.debug("Spine \(index): \(pageCount) pages")
                status = .counting(completed: index + 1, total: totalSpines)
            } catch {
                if error is CancellationError {
                    return
                }
                Self.logger.error("Failed to count pages for spine \(index): \(error.localizedDescription)")
                // Use 1 as fallback for failed spine
                spinePageCounts.append(1)
                status = .counting(completed: index + 1, total: totalSpines)
            }
        }

        // Create and cache the result
        let pageCounts = BookPageCounts(
            bookId: bookId,
            layoutKey: layoutKey,
            spinePageCounts: spinePageCounts
        )

        await BookPageCountsCache.shared.set(pageCounts)

        Self.logger.info("Page counting complete: \(pageCounts.totalPages) total pages across \(totalSpines) spines")

        status = .complete(pageCounts)

        // Cleanup
        hiddenWebView = nil
    }

    private func createHiddenWebView(htmlSections: [HTMLSection], layoutKey: LayoutKey) -> WKWebView {
        // Combine all image caches from sections
        var combinedImageCache: [String: Data] = [:]
        for section in htmlSections {
            combinedImageCache.merge(section.imageCache) { _, new in new }
        }

        // Create URL scheme handler for serving images
        let schemeHandler = EPUBURLSchemeHandler(imageCache: combinedImageCache)
        urlSchemeHandler = schemeHandler

        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        configuration.dataDetectorTypes = []
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: EPUBURLSchemeHandler.scheme)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isHidden = true
        webView.isUserInteractionEnabled = false

        // Use the same frame dimensions as the layoutKey
        webView.frame = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(layoutKey.viewportWidth),
            height: CGFloat(layoutKey.viewportHeight)
        )

        return webView
    }

    private func countPages(
        for section: HTMLSection,
        webView: WKWebView,
        layoutKey: LayoutKey
    ) async throws -> Int {
        // Build HTML with same structure as WebPageViewController
        let bodyContent = extractBodyContent(from: section.annotatedHTML)
        let processedHTML = processHTMLWithImages(bodyContent, basePath: section.basePath, imageCache: section.imageCache)

        // Get publisher CSS
        var publisherCSS = ""
        if let css = section.cssContent, !css.isEmpty {
            publisherCSS = css
        }

        // Generate CSS using same parameters
        let css = CSSManager.generateCompleteCSS(
            fontScale: layoutKey.fontScale,
            marginSize: CGFloat(layoutKey.marginSize),
            publisherCSS: publisherCSS.isEmpty ? nil : publisherCSS
        )

        let margin = layoutKey.marginSize
        let columnWidth = max(0, layoutKey.viewportWidth - (margin * 2))
        let columnGap = max(0, margin * 2)

        let wrappedHTML = """
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

        // Load and wait for content
        return try await withCheckedThrowingContinuation { continuation in
            currentContinuation = continuation

            webView.loadHTMLString(wrappedHTML, baseURL: nil)

            // Set up navigation delegate to detect load completion
            let delegate = PageCountDelegate { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.queryPageCount(webView: webView, layoutKey: layoutKey) { pageCount in
                    self.currentContinuation = nil
                    continuation.resume(returning: pageCount)
                }
            }
            webView.navigationDelegate = delegate
            // Keep delegate alive
            objc_setAssociatedObject(webView, &AssociatedKeys.delegate, delegate, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private func queryPageCount(webView: WKWebView, layoutKey: LayoutKey, completion: @escaping (Int) -> Void) {
        let js = """
        (function() {
            var body = document.body;
            if (!body) return 1;

            var style = window.getComputedStyle(body);
            var columnWidth = parseFloat(style.columnWidth) || \(layoutKey.viewportWidth - layoutKey.marginSize * 2);
            var columnGap = parseFloat(style.columnGap) || \(layoutKey.marginSize * 2);
            var pageWidth = columnWidth + columnGap;

            var contentWidth = document.documentElement.scrollWidth;
            var totalPages = Math.max(1, Math.ceil(contentWidth / pageWidth));

            return totalPages;
        })();
        """

        webView.evaluateJavaScript(js) { result, error in
            if let error {
                Self.logger.error("Failed to query page count: \(error.localizedDescription)")
                completion(1)
                return
            }

            if let pageCount = result as? Int, pageCount > 0 {
                completion(pageCount)
            } else if let pageCount = result as? Double, pageCount > 0 {
                completion(Int(pageCount))
            } else {
                completion(1)
            }
        }
    }

    // MARK: - HTML Processing (same as WebPageViewController)

    private func extractBodyContent(from html: String) -> String {
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

    private func fixXHTMLSelfClosingTags(_ html: String) -> String {
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

    private func processHTMLWithImages(_ html: String, basePath: String, imageCache: [String: Data]) -> String {
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

// MARK: - Helper Types

private enum AssociatedKeys {
    static var delegate = "PageCountDelegate"
}

private class PageCountDelegate: NSObject, WKNavigationDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        // Small delay to ensure layout is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.onFinish()
        }
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError _: Error) {
        onFinish()
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
        onFinish()
    }
}
