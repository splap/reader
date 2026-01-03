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

    private static let logger = Logger(subsystem: "com.example.reader", category: "page-view")
    private let htmlSections: [HTMLSection]
    private let bookTitle: String?
    private let bookAuthor: String?
    private let chapterTitle: String?
    private let onSendToLLM: (SelectionPayload) -> Void
    private let onPageChanged: (Int, Int) -> Void  // (currentPage, totalPages)
    private var webView: SelectableWebView!
    private var currentPage: Int = 0
    private var totalPages: Int = 0
    private var contentSizeObserver: NSKeyValueObservation?

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
        onSendToLLM: @escaping (SelectionPayload) -> Void,
        onPageChanged: @escaping (Int, Int) -> Void  // (currentPage, totalPages)
    ) {
        self.htmlSections = htmlSections
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.chapterTitle = chapterTitle
        self.fontScale = fontScale
        self.onSendToLLM = onSendToLLM
        self.onPageChanged = onPageChanged
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
        webView.scrollView.isPagingEnabled = true
        webView.scrollView.bounces = true
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = false
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
                scrollView.isPagingEnabled = true
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
        // Combine all HTML sections
        var combinedHTML = ""
        for section in htmlSections {
            let processedHTML = processHTMLWithImages(section.html, basePath: section.basePath, imageCache: section.imageCache)
            combinedHTML += processedHTML + "\n"
        }

        // Wrap HTML with CSS columns for pagination
        let wrappedHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
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
                    /* Remove viewport units to avoid Safari mobile issues */
                    height: 100%;
                    padding: 48px 0;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    font-size: \(Int(16 * fontScale))px;
                    line-height: 1.6;
                    text-align: justify;

                    /* Light mode colors */
                    color: #000000;

                    /* CSS columns for pagination - each column = viewport width */
                    column-width: 100vw;
                    column-gap: 0;
                    column-fill: auto;
                }

                /* Apply horizontal padding to content elements */
                p, h1, h2, h3, h4, h5, h6, ul, ol, blockquote, pre, div {
                    padding-left: 48px;
                    padding-right: 48px;
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
                img {
                    max-width: 100%;
                    height: auto;
                    display: block;
                    margin: 1em auto;
                    break-inside: avoid;
                }
                p {
                    margin-bottom: 1em;
                    text-align: justify;
                }
                h1, h2, h3, h4, h5, h6 {
                    margin-top: 1em;
                    margin-bottom: 0.5em;
                    break-after: avoid;
                }
            </style>
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

    private func updateCurrentPage() {
        let scrollView = webView.scrollView
        let pageWidth = scrollView.bounds.width
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
        let pageWidth = scrollView.bounds.width
        let nextOffset = min(scrollView.contentOffset.x + pageWidth, scrollView.contentSize.width - pageWidth)
        scrollView.setContentOffset(CGPoint(x: nextOffset, y: 0), animated: true)
    }

    func navigateToPreviousPage() {
        let scrollView = webView.scrollView
        let pageWidth = scrollView.bounds.width
        let prevOffset = max(scrollView.contentOffset.x - pageWidth, 0)
        scrollView.setContentOffset(CGPoint(x: prevOffset, y: 0), animated: true)
    }
}

// MARK: - UIScrollViewDelegate
extension WebPageViewController: UIScrollViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateCurrentPage()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateCurrentPage()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            updateCurrentPage()
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
                sv.isPagingEnabled = true
                Self.logger.info("Set isScrollEnabled=true, actual value=\(sv.isScrollEnabled)")
                self.updateCurrentPage()
            }
        }
    }
}

