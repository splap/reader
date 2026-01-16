import UIKit
import WebKit
import ReaderCore
import Foundation
import OSLog

// Custom WKWebView that adds "Send to LLM" to text selection menu
private class SelectableWebView: WKWebView {
    var onSendToLLM: (() -> Void)?

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        let actionName = NSStringFromSelector(action)

        // Log all actions to see what we're dealing with
        NSLog("WebView action: \(actionName)")

        // Show our custom action
        if action == #selector(sendToLLMAction) {
            return true
        }

        // Hide specific actions to make room for our action in the primary menu
        // Block translate, look up, search web, and share
        if actionName.contains("translate") ||
           actionName.contains("define") ||
           actionName.contains("_lookup") ||
           actionName.contains("searchWeb") ||
           actionName.contains("_share") {
            return false
        }

        return super.canPerformAction(action, withSender: sender)
    }

    @objc func sendToLLMAction() {
        onSendToLLM?()
    }
}

final class WebPageViewController: UIViewController {

    private static let logger = Log.logger(category: "page-view")
    private let htmlSections: [HTMLSection]
    private let bookTitle: String?
    private let bookAuthor: String?
    private let chapterTitle: String?
    private let onSendToLLM: (SelectionPayload) -> Void
    private let onPageChanged: (Int, Int) -> Void  // (currentPage, totalPages)
    private let onBlockPositionChanged: ((String, String?) -> Void)?  // (Block ID, Spine Item ID) of first visible block
    private var webView: SelectableWebView!
    private var currentPage: Int = 0
    private var totalPages: Int = 0
    private var contentSizeObserver: NSKeyValueObservation?
    private var cssColumnWidth: CGFloat = 0  // Exact column width from CSS - source of truth for alignment
    private var initialPageIndex: Int = 0  // Page to navigate to after content loads (legacy)
    private var initialBlockId: String?  // Block ID to navigate to after content loads (preferred)
    private var hasRestoredPosition = false  // Track if we've restored position
    private var currentBlockId: String?  // Currently visible block ID
    private var currentSpineItemId: String?  // Currently visible spine item ID

    var fontScale: CGFloat = 2.0 {
        didSet {
            guard fontScale != oldValue else { return }
            reloadWithNewFontScale()
        }
    }

    init(
        htmlSections: [HTMLSection],
        bookTitle: String? = nil,
        bookAuthor: String? = nil,
        chapterTitle: String? = nil,
        fontScale: CGFloat = 2.0,
        initialPageIndex: Int = 0,
        initialBlockId: String? = nil,
        onSendToLLM: @escaping (SelectionPayload) -> Void,
        onPageChanged: @escaping (Int, Int) -> Void,
        onBlockPositionChanged: ((String, String?) -> Void)? = nil
    ) {
        self.htmlSections = htmlSections
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.chapterTitle = chapterTitle
        self.fontScale = fontScale
        self.initialPageIndex = initialPageIndex
        self.initialBlockId = initialBlockId
        self.onSendToLLM = onSendToLLM
        self.onPageChanged = onPageChanged
        self.onBlockPositionChanged = onBlockPositionChanged
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        Self.logger.debug("WebPageViewController viewDidLoad")

        // Create WKWebView configuration
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        configuration.dataDetectorTypes = []

        webView = SelectableWebView(frame: .zero, configuration: configuration)
        webView.onSendToLLM = { [weak self] in
            self?.extractAndSendSelection()
        }
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.isPagingEnabled = false  // Use custom snapping for precise alignment
        webView.scrollView.decelerationRate = .fast
        webView.scrollView.bounces = true
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.delegate = self
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear

        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Observe contentSize to re-enable scrolling when content loads
        contentSizeObserver = webView.scrollView.observe(\.contentSize, options: [.new]) { scrollView, change in
            WebPageViewController.logger.debug("contentSize changed to \(scrollView.contentSize.width)x\(scrollView.contentSize.height), isScrollEnabled=\(scrollView.isScrollEnabled)")
            // WKWebView may disable scrolling when content loads - re-enable it
            if scrollView.contentSize.width > scrollView.bounds.width {
                scrollView.isScrollEnabled = true
                scrollView.isPagingEnabled = false  // Use custom snapping
                WebPageViewController.logger.info("Re-enabled scrolling via KVO")
            }
        }

        // Register custom menu item for text selection
        let menuItem = UIMenuItem(title: "Send to LLM", action: #selector(SelectableWebView.sendToLLMAction))
        UIMenuController.shared.menuItems = [menuItem]

        loadContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }

    private func extractAndSendSelection() {
        // JavaScript to get selected text and surrounding context
        let js = """
        (function() {
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0) {
                return null;
            }

            const selectedText = selection.toString();
            if (!selectedText) {
                return null;
            }

            // Get the full body text
            const fullText = document.body.innerText;

            // Find the position of selected text in full text
            const selectionStart = fullText.indexOf(selectedText);
            if (selectionStart === -1) {
                return {
                    selectedText: selectedText,
                    contextText: selectedText,
                    location: 0,
                    length: selectedText.length
                };
            }

            // Extract context (500 chars before and after)
            const contextLength = 500;
            const contextStart = Math.max(0, selectionStart - contextLength);
            const contextEnd = Math.min(fullText.length, selectionStart + selectedText.length + contextLength);
            const contextText = fullText.substring(contextStart, contextEnd);

            return {
                selectedText: selectedText,
                contextText: contextText,
                location: selectionStart,
                length: selectedText.length
            };
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                Self.logger.error("Failed to get selection: \(error.localizedDescription)")
                return
            }

            guard let dict = result as? [String: Any],
                  let selectedText = dict["selectedText"] as? String,
                  let contextText = dict["contextText"] as? String,
                  let location = dict["location"] as? Int,
                  let length = dict["length"] as? Int else {
                Self.logger.warning("No valid selection found")
                return
            }

            let payload = SelectionPayload(
                selectedText: selectedText,
                contextText: contextText,
                range: NSRange(location: location, length: length),
                bookTitle: self.bookTitle,
                bookAuthor: self.bookAuthor,
                chapterTitle: self.chapterTitle
            )

            self.onSendToLLM(payload)
        }
    }

    private func loadContent() {
        // Combine all HTML sections, using annotatedHTML which includes data-block-id attributes
        var combinedHTML = ""
        for section in htmlSections {
            // Use annotatedHTML for block-based position tracking
            // Extract just the body content, stripping out <html>, <head>, and <body> wrapper tags
            // This prevents publisher CSS from being loaded via <link> tags
            let bodyContent = extractBodyContent(from: section.annotatedHTML)
            let processedHTML = processHTMLWithImages(bodyContent, basePath: section.basePath, imageCache: section.imageCache)
            combinedHTML += processedHTML + "\n"
        }

        // Generate CSS using CSSManager (house CSS + sanitized publisher CSS)
        let css = CSSManager.generateCompleteCSS(fontScale: fontScale, publisherCSS: nil)

        // Wrap HTML with house CSS
        let wrappedHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no">
            <style>
                \(css)

                /* Prevent text selection highlight from causing layout shifts */
                * {
                    -webkit-tap-highlight-color: transparent;
                    -webkit-touch-callout: none;
                }
            </style>
            <script>
                // Prevent double-tap zoom by tracking taps and preventing default
                (function() {
                    var lastTap = 0;
                    document.addEventListener('touchend', function(e) {
                        var now = Date.now();
                        if (now - lastTap < 300) {
                            e.preventDefault();
                        }
                        lastTap = now;
                    }, { passive: false });

                    // Also prevent gesturestart which can trigger zoom
                    document.addEventListener('gesturestart', function(e) {
                        e.preventDefault();
                    }, { passive: false });
                })();
            </script>
        </head>
        <body>
            \(combinedHTML)
        </body>
        </html>
        """

        webView.loadHTMLString(wrappedHTML, baseURL: nil)
    }

    private func processHTMLWithImages(_ html: String, basePath: String, imageCache: [String: Data]) -> String {
        var processedHTML = html

        // Find all img tags and replace src with base64 data
        let imgPattern = #"<img([^>]*)src\s*=\s*["\']([^"\']+)["\']([^>]*)>"#
        guard let regex = try? NSRegularExpression(pattern: imgPattern, options: [.caseInsensitive]) else {
            return html
        }

        let nsString = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))

        // Process matches in reverse to maintain string indices
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            let fullMatchRange = match.range(at: 0)
            let srcRange = match.range(at: 2)
            let beforeAttrs = nsString.substring(with: match.range(at: 1))
            let afterAttrs = match.numberOfRanges > 3 ? nsString.substring(with: match.range(at: 3)) : ""

            let srcPath = nsString.substring(with: srcRange)

            // Resolve relative path
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
                    } else if component != "." && !component.isEmpty {
                        finalComponents.append(component)
                    }
                }
                resolvedPath = finalComponents.joined(separator: "/")
            } else {
                resolvedPath = basePath.isEmpty ? srcPath : "\(basePath)/\(srcPath)"
            }

            // Try to find image data
            if let imageData = imageCache[resolvedPath] ?? imageCache[(resolvedPath as NSString).lastPathComponent] {
                let base64 = imageData.base64EncodedString()
                let mimeType = mimeType(for: resolvedPath)
                let dataURL = "data:\(mimeType);base64,\(base64)"
                let newTag = "<img\(beforeAttrs)src=\"\(dataURL)\"\(afterAttrs)>"

                processedHTML = (processedHTML as NSString).replacingCharacters(in: fullMatchRange, with: newTag)
            }
        }

        return processedHTML
    }

    private func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        default: return "image/jpeg"
        }
    }

    /// Extracts just the body content from an HTML document, stripping out
    /// <html>, <head>, and <body> wrapper tags. This prevents publisher CSS
    /// from being loaded via <link> tags in the head.
    private func extractBodyContent(from html: String) -> String {
        // Try to find <body> tag and extract its content
        let bodyPattern = #"<body[^>]*>([\s\S]*?)</body>"#
        if let regex = try? NSRegularExpression(pattern: bodyPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: html.utf16.count)),
           match.numberOfRanges >= 2 {
            let contentRange = Range(match.range(at: 1), in: html)!
            return String(html[contentRange])
        }

        // If no body tag found, return original HTML
        // (might be a fragment without full document structure)
        return html
    }

    private func reloadWithNewFontScale() {
        // Save current scroll position as a percentage
        let scrollView = webView.scrollView
        let currentOffset = scrollView.contentOffset.x
        let contentWidth = scrollView.contentSize.width
        let scrollPercentage = contentWidth > 0 ? currentOffset / contentWidth : 0

        // Reload content
        loadContent()

        // Restore scroll position after content loads
        // We'll do this in the navigation delegate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            let scrollView = self.webView.scrollView
            let newContentWidth = scrollView.contentSize.width
            let newOffset = newContentWidth * scrollPercentage
            scrollView.setContentOffset(CGPoint(x: newOffset, y: 0), animated: false)
            self.updateCurrentPage()
        }
    }

    private func currentPageWidth() -> CGFloat {
        // Use CSS column width if available (precise), otherwise fall back to bounds
        return cssColumnWidth > 0 ? cssColumnWidth : webView.scrollView.bounds.width
    }

    private func updateCurrentPage() {
        let scrollView = webView.scrollView
        let pageWidth = currentPageWidth()
        guard pageWidth > 0 else { return }

        let contentWidth = scrollView.contentSize.width
        let newTotalPages = Int(ceil(contentWidth / pageWidth))
        let newCurrentPage = Int(round(scrollView.contentOffset.x / pageWidth))

        if newTotalPages != totalPages || newCurrentPage != currentPage {
            totalPages = newTotalPages
            currentPage = max(0, min(newCurrentPage, totalPages - 1))
            onPageChanged(currentPage, totalPages)
        }
    }

    func navigateToNextPage() {
        let scrollView = webView.scrollView
        let pageWidth = currentPageWidth()
        let nextOffset = min(scrollView.contentOffset.x + pageWidth, scrollView.contentSize.width - pageWidth)
        scrollView.setContentOffset(CGPoint(x: nextOffset, y: 0), animated: true)
    }

    func navigateToPreviousPage() {
        let scrollView = webView.scrollView
        let pageWidth = currentPageWidth()
        let prevOffset = max(scrollView.contentOffset.x - pageWidth, 0)
        scrollView.setContentOffset(CGPoint(x: prevOffset, y: 0), animated: true)
    }

    // Navigate to a specific page (0-indexed)
    func navigateToPage(_ pageIndex: Int, animated: Bool = true) {
        let scrollView = webView.scrollView
        let pageWidth = currentPageWidth()
        guard pageWidth > 0 else { return }

        let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let targetX = CGFloat(max(0, pageIndex)) * pageWidth
        let clampedX = min(targetX, maxX)

        scrollView.setContentOffset(CGPoint(x: clampedX, y: 0), animated: animated)
    }

    private func snapToNearestPage() {
        let scrollView = webView.scrollView
        let pageWidth = currentPageWidth()
        guard pageWidth > 0 else { return }

        let targetPage = round(scrollView.contentOffset.x / pageWidth)
        let targetX = targetPage * pageWidth
        let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let clampedX = min(max(0, targetX), maxX)

        if abs(scrollView.contentOffset.x - clampedX) > 0.5 {
            scrollView.setContentOffset(CGPoint(x: clampedX, y: 0), animated: true)
        }
    }

    private func queryCSSColumnWidth(completion: @escaping () -> Void) {
        // Query the exact CSS column width from the browser
        // This is the source of truth for pagination alignment
        let js = """
        (function() {
            const container = document.getElementById('pagination-container');
            if (container) {
                return container.clientWidth;
            }
            return document.documentElement.clientWidth;
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, error in
            if let width = result as? Double, width > 0 {
                self?.cssColumnWidth = CGFloat(width)
                Self.logger.info("CSS column width: \(width)")
            }
            completion()
        }
    }

    // MARK: - Block Position Tracking

    /// Query the first visible block ID and spine item ID from the WebView
    /// The block must have data-block-id and data-spine-item-id attributes to be detected
    func queryFirstVisibleBlock(completion: @escaping (String?, String?) -> Void) {
        let js = """
        (function() {
            // Get all elements with data-block-id attribute
            const blocks = document.querySelectorAll('[data-block-id]');
            if (blocks.length === 0) return null;

            const viewportLeft = window.scrollX || document.documentElement.scrollLeft;
            const viewportRight = viewportLeft + window.innerWidth;

            // Find the first block that is at least partially visible
            for (const block of blocks) {
                const rect = block.getBoundingClientRect();
                const absoluteLeft = rect.left + viewportLeft;
                const absoluteRight = rect.right + viewportLeft;

                // Check if block overlaps with visible viewport
                if (absoluteRight > viewportLeft && absoluteLeft < viewportRight) {
                    return {
                        blockId: block.getAttribute('data-block-id'),
                        spineItemId: block.getAttribute('data-spine-item-id')
                    };
                }
            }

            return null;
        })();
        """

        webView.evaluateJavaScript(js) { result, error in
            if let error = error {
                Self.logger.error("Failed to query block position: \(error.localizedDescription)")
                completion(nil, nil)
                return
            }
            if let dict = result as? [String: Any] {
                let blockId = dict["blockId"] as? String
                let spineItemId = dict["spineItemId"] as? String
                completion(blockId, spineItemId)
            } else {
                completion(nil, nil)
            }
        }
    }

    /// Navigate to a specific block by its ID
    /// - Parameters:
    ///   - blockId: The data-block-id value to scroll to
    ///   - animated: Whether to animate the scroll
    func navigateToBlock(_ blockId: String, animated: Bool = false) {
        let js = """
        (function() {
            const block = document.querySelector('[data-block-id="\(blockId)"]');
            if (!block) return null;

            const rect = block.getBoundingClientRect();
            const scrollLeft = window.scrollX || document.documentElement.scrollLeft;

            // Calculate the page that contains this block
            const viewportWidth = window.innerWidth;
            const blockLeft = rect.left + scrollLeft;
            const targetPage = Math.floor(blockLeft / viewportWidth);

            return targetPage * viewportWidth;
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                Self.logger.error("Failed to navigate to block: \(error.localizedDescription)")
                return
            }

            if let targetX = result as? Double {
                Self.logger.info("Navigating to block \(blockId) at x=\(targetX)")
                self.webView.scrollView.setContentOffset(
                    CGPoint(x: CGFloat(targetX), y: 0),
                    animated: animated
                )
            }
        }
    }

    /// Update block position and notify callback if changed
    private func updateBlockPosition() {
        guard onBlockPositionChanged != nil else { return }

        queryFirstVisibleBlock { [weak self] blockId, spineItemId in
            guard let self = self, let blockId = blockId else { return }

            // Notify if either block ID or spine item ID changed
            if blockId != self.currentBlockId || spineItemId != self.currentSpineItemId {
                self.currentBlockId = blockId
                self.currentSpineItemId = spineItemId
                self.onBlockPositionChanged?(blockId, spineItemId)
            }
        }
    }
}

// MARK: - UIScrollViewDelegate
extension WebPageViewController: UIScrollViewDelegate {
    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        // Custom page snapping using exact CSS column width
        let pageWidth = currentPageWidth()
        guard pageWidth > 0 else { return }

        let rawPage = scrollView.contentOffset.x / pageWidth
        let maxPage = max(0, floor((scrollView.contentSize.width - scrollView.bounds.width) / pageWidth))
        let targetPage: CGFloat

        if velocity.x > 0.2 {
            targetPage = min(maxPage, floor(rawPage) + 1)
        } else if velocity.x < -0.2 {
            targetPage = max(0, ceil(rawPage) - 1)
        } else {
            targetPage = min(maxPage, max(0, round(rawPage)))
        }

        targetContentOffset.pointee = CGPoint(x: targetPage * pageWidth, y: 0)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        snapToNearestPage()
        updateCurrentPage()
        updateBlockPosition()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateCurrentPage()
        updateBlockPosition()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            snapToNearestPage()
            updateCurrentPage()
            updateBlockPosition()
        }
    }
}

// MARK: - WKNavigationDelegate
extension WebPageViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Self.logger.debug("didFinish navigation")

        // Inject JavaScript to ensure content is scrollable and wait for layout
        let js = """
        document.documentElement.style.overflow = 'visible';
        document.body.style.overflow = 'visible';
        // Force layout calculation
        document.body.offsetHeight;
        """
        webView.evaluateJavaScript(js) { [weak self] _, error in
            guard let self = self else { return }
            if let error = error {
                Self.logger.error("JavaScript error: \(error.localizedDescription)")
            }

            // Wait a bit more for CSS columns to finish laying out
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                let sv = self.webView.scrollView
                Self.logger.info("After load: contentSize=\(sv.contentSize.width)x\(sv.contentSize.height) isScrollEnabled=\(sv.isScrollEnabled)")
                sv.isScrollEnabled = true
                sv.isPagingEnabled = false  // Custom snapping for precise alignment
                Self.logger.info("Set isScrollEnabled=true, actual value=\(sv.isScrollEnabled)")

                // Query exact CSS column width for precise alignment
                self.queryCSSColumnWidth {
                    // Restore position BEFORE reporting current page/block
                    // This prevents overwriting saved position with initial values
                    if !self.hasRestoredPosition {
                        self.hasRestoredPosition = true

                        // Prefer block-based restoration over page-based
                        if let blockId = self.initialBlockId {
                            Self.logger.info("Restoring position to block \(blockId)")
                            self.navigateToBlock(blockId, animated: false)
                            // Wait for scroll to complete before updating position
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                                self?.updateCurrentPage()
                                self?.updateBlockPosition()
                            }
                        } else if self.initialPageIndex > 0 {
                            // Fallback to legacy page-based restoration
                            Self.logger.info("Restoring position to page \(self.initialPageIndex)")
                            self.navigateToPage(self.initialPageIndex, animated: false)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                                self?.updateCurrentPage()
                                self?.updateBlockPosition()
                            }
                        } else {
                            self.updateCurrentPage()
                            self.updateBlockPosition()
                        }
                    } else {
                        self.updateCurrentPage()
                        self.updateBlockPosition()
                    }
                }
            }
        }
    }
}
