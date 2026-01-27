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

        // Hide specific actions to make room for our action in the primary menu
        if actionName.contains("translate") ||
           actionName.contains("define") ||
           actionName.contains("_lookup") ||
           actionName.contains("searchWeb") ||
           actionName.contains("_share") {
            return false
        }

        return super.canPerformAction(action, withSender: sender)
    }

    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)

        let sendToLLMAction = UIAction(title: "Send to LLM", image: UIImage(systemName: "bubble.left.and.text.bubble.right")) { [weak self] _ in
            self?.onSendToLLM?()
        }

        let menu = UIMenu(title: "", options: .displayInline, children: [sendToLLMAction])
        builder.insertChild(menu, atStartOfMenu: .standardEdit)
    }
}

public final class WebPageViewController: UIViewController, PageRenderer {

    private static let logger = Log.logger(category: "page-view")
    private let htmlSections: [HTMLSection]
    private let bookTitle: String?
    private let bookAuthor: String?
    private let chapterTitle: String?
    private var webView: SelectableWebView!
    private var currentPage: Int = 0
    private var totalPages: Int = 0
    private var cssColumnWidth: CGFloat = 0  // Exact column width from CSS - source of truth for alignment
    private var hasRestoredPosition = false  // Track if we've restored position
    private var urlSchemeHandler: EPUBURLSchemeHandler?  // Handler for serving images
    private let hrefToSpineItemId: [String: String]  // Map from file href to spineItemId for link resolution
    private var isWaitingForInitialRestore = false  // Hide content until restore completes
    private let spineItemIdToSectionIndex: [String: Int]
    private var currentSectionIndex: Int?

    // Spine-scoped rendering state (one spine item at a time)
    private var currentSpineIndex: Int = 0  // Currently loaded spine item index
    private var initialCFI: String?  // CFI to restore after loading

    // Edge scroll tracking for spine transitions
    private var dragStartOffset: CGFloat = 0
    private var wasAtEndWhenDragStarted = false
    private var wasAtStartWhenDragStarted = false

    // MARK: - PageRenderer Protocol Properties

    public var viewController: UIViewController { self }

    public var fontScale: CGFloat = 2.0 {
        didSet {
            guard fontScale != oldValue else { return }
            reloadWithNewFontScale()
        }
    }

    public var onPageChanged: ((Int, Int) -> Void)?
    public var onSpineChanged: ((Int, Int) -> Void)?
    public var onSendToLLM: ((SelectionPayload) -> Void)?
    public var onRenderReady: (() -> Void)?
    /// Called when a section is loaded. Parameters: (loadedCount, totalCount)
    public var onLoadingProgress: ((Int, Int) -> Void)?

    public init(
        htmlSections: [HTMLSection],
        bookTitle: String? = nil,
        bookAuthor: String? = nil,
        chapterTitle: String? = nil,
        fontScale: CGFloat = 2.0,
        initialCFI: String? = nil,
        hrefToSpineItemId: [String: String] = [:]
    ) {
        self.htmlSections = htmlSections
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.chapterTitle = chapterTitle
        self.fontScale = fontScale
        self.initialCFI = initialCFI
        self.hrefToSpineItemId = hrefToSpineItemId
        var sectionIndexMap: [String: Int] = [:]
        for (index, section) in htmlSections.enumerated() where !section.spineItemId.isEmpty {
            sectionIndexMap[section.spineItemId] = index
        }
        self.spineItemIdToSectionIndex = sectionIndexMap
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        Self.logger.debug("WebPageViewController viewDidLoad")

        // Combine all image caches from sections
        var combinedImageCache: [String: Data] = [:]
        for section in htmlSections {
            combinedImageCache.merge(section.imageCache) { _, new in new }
        }

        // Create URL scheme handler for serving images
        let schemeHandler = EPUBURLSchemeHandler(imageCache: combinedImageCache)
        self.urlSchemeHandler = schemeHandler

        // Create WKWebView configuration with custom URL scheme
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        configuration.dataDetectorTypes = []
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: EPUBURLSchemeHandler.scheme)

        webView = SelectableWebView(frame: .zero, configuration: configuration)
        webView.onSendToLLM = { [weak self] in
            self?.extractAndSendSelection()
        }
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.isPagingEnabled = false  // Use custom snapping for precise alignment
        webView.scrollView.decelerationRate = .fast
        webView.scrollView.bounces = true
        webView.scrollView.alwaysBounceHorizontal = true  // Allow horizontal bounce even for single-page content
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.isDirectionalLockEnabled = true
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.contentInsetAdjustmentBehavior = .never  // Prevent automatic inset changes
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

        // Observe margin size changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(marginSizeDidChange),
            name: ReaderPreferences.marginSizeDidChangeNotification,
            object: nil
        )

        loadContent()
    }

    @objc private func marginSizeDidChange() {
        reloadWithNewFontScale()  // Reuse the same reload logic
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }

    private func extractAndSendSelection() {
        // JavaScript to get selected text, surrounding context, and block/spine IDs
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
            let contextText = selectedText;
            let location = 0;

            if (selectionStart !== -1) {
                location = selectionStart;
                // Extract context (500 chars before and after)
                const contextLength = 500;
                const contextStart = Math.max(0, selectionStart - contextLength);
                const contextEnd = Math.min(fullText.length, selectionStart + selectedText.length + contextLength);
                contextText = fullText.substring(contextStart, contextEnd);
            }

            // Walk up DOM tree from selection to find element with data-block-id
            let blockId = null;
            let spineItemId = null;
            let node = selection.anchorNode;
            while (node && node !== document.body) {
                if (node.nodeType === 1) {  // Element node
                    const el = node;
                    if (el.dataset && el.dataset.blockId) {
                        blockId = el.dataset.blockId;
                        spineItemId = el.dataset.spineItemId || null;
                        break;
                    }
                }
                node = node.parentNode;
            }

            return {
                selectedText: selectedText,
                contextText: contextText,
                location: location,
                length: selectedText.length,
                blockId: blockId,
                spineItemId: spineItemId
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

            // Extract optional block and spine IDs
            let blockId = dict["blockId"] as? String
            let spineItemId = dict["spineItemId"] as? String

            let payload = SelectionPayload(
                selectedText: selectedText,
                contextText: contextText,
                range: NSRange(location: location, length: length),
                bookTitle: self.bookTitle,
                bookAuthor: self.bookAuthor,
                chapterTitle: self.chapterTitle,
                blockId: blockId,
                spineItemId: spineItemId
            )

            self.onSendToLLM?(payload)
        }
    }

    private func loadContent() {
        let spineIndex = findInitialSpineIndex()

        // Parse initialCFI to get DOM path for position restoration within the chapter
        var restoreCFI: (domPath: [Int], charOffset: Int?)?
        if let cfi = initialCFI, let parsed = CFIParser.parseFullCFI(cfi), !parsed.domPath.isEmpty {
            restoreCFI = (domPath: parsed.domPath, charOffset: parsed.charOffset)
            Self.logger.debug("SPINE: Will restore to CFI path \(parsed.domPath) offset \(parsed.charOffset ?? -1)")
        }

        loadSpineItem(at: spineIndex, restoreCFI: restoreCFI)
    }

    /// Load a specific spine item into the WebView
    /// - Parameters:
    ///   - index: The spine item index to load
    ///   - restoreCFI: Optional CFI to scroll to after loading (domPath and charOffset)
    ///   - atEnd: If true, scroll to the last page instead of the first
    public func loadSpineItem(at index: Int, restoreCFI: (domPath: [Int], charOffset: Int?)? = nil, atEnd: Bool = false) {
        let loadStart = CFAbsoluteTimeGetCurrent()

        guard index >= 0 && index < htmlSections.count else {
            Self.logger.error("SPINE: Invalid spine index \(index), max is \(htmlSections.count - 1)")
            return
        }

        prepareForPositionRestore()

        // Reset CSS column width - will be re-queried after new content loads
        // This prevents using stale width values from the previous spine
        cssColumnWidth = 0

        // Reset edge scroll tracking state
        wasAtEndWhenDragStarted = false
        wasAtStartWhenDragStarted = false
        dragStartOffset = 0

        currentSpineIndex = index
        currentSectionIndex = index

        Self.logger.info("SPINE: Loading spine item \(index) of \(htmlSections.count)")

        // Build HTML for just this spine item
        let section = htmlSections[index]
        let bodyContent = extractBodyContent(from: section.annotatedHTML)
        let processedHTML = processHTMLWithImages(bodyContent, basePath: section.basePath, imageCache: section.imageCache)

        // Collect publisher CSS from this section
        var publisherCSS = ""
        if let css = section.cssContent, !css.isEmpty {
            publisherCSS = css
        }

        Self.logger.debug("SPINE: Section HTML: \(processedHTML.count) chars, CSS: \(publisherCSS.count) chars")

        // Generate CSS using CSSManager (house CSS + publisher CSS)
        let marginSize = ReaderPreferences.shared.marginSize
        let css = CSSManager.generateCompleteCSS(fontScale: fontScale, marginSize: marginSize, publisherCSS: publisherCSS.isEmpty ? nil : publisherCSS)

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

                // CFI (Canonical Fragment Identifier) functions for position tracking

                // Build DOM path from an element to the body
                window.buildDOMPath = function(element) {
                    var path = [];
                    var current = element;
                    while (current && current !== document.body && current.parentElement) {
                        var parent = current.parentElement;
                        var children = Array.from(parent.children);
                        var index = children.indexOf(current);
                        if (index >= 0) {
                            path.unshift(index);
                        }
                        current = parent;
                    }
                    return path;
                };

                // Convert DOM path array to CFI path string (using EPUB even-number convention)
                window.domPathToCFI = function(path) {
                    return path.map(function(idx) {
                        return '/' + ((idx + 1) * 2);
                    }).join('');
                };

                // Generate CFI for the first visible text position
                // Accepts optional page number from Swift (more reliable than calculating from scrollX)
                window.generateCFIForCurrentPosition = function(pageFromSwift) {
                    var currentPage = pageFromSwift || 0;

                    // Find the first content container (pagination-container or body)
                    var container = document.body.querySelector('#pagination-container') || document.body;

                    // For the test chapter and most EPUBs, each page is a direct child of the container
                    // The domPath should be [containerIndex, pageIndex]
                    var containerPath = window.buildDOMPath(container);

                    // Find the child element at the current page position
                    // This assumes one element per CSS column page
                    var pageElements = container.children;
                    var pageIndex = Math.min(currentPage, pageElements.length - 1);

                    // Build full path: container path + page index
                    var path = containerPath.concat([pageIndex]);
                    var charOffset = 0;

                    // Get the actual page element for spine item lookup
                    var pageElement = pageElements[pageIndex];

                    // Get spine item ID if available
                    var spineItemEl = pageElement ? pageElement.closest('[data-spine-item-id]') : null;
                    var spineItemId = spineItemEl ? spineItemEl.dataset.spineItemId : null;

                    return {
                        domPath: path,
                        charOffset: charOffset,
                        spineItemId: spineItemId
                    };
                };

                // Navigate an element from DOM path
                window.getElementFromPath = function(path) {
                    var current = document.body;
                    for (var i = 0; i < path.length; i++) {
                        var children = current.children;
                        if (path[i] >= children.length) {
                            return null;
                        }
                        current = children[path[i]];
                    }
                    return current;
                };

                // Resolve a CFI and scroll to that position
                // Input: { domPath: [int], charOffset: int }
                window.resolveCFI = function(cfiData) {
                    if (!cfiData || !cfiData.domPath) return false;

                    var element = window.getElementFromPath(cfiData.domPath);
                    if (!element) return false;

                    var rect = element.getBoundingClientRect();
                    var scrollLeft = window.scrollX || document.documentElement.scrollLeft;
                    var viewportWidth = window.innerWidth;
                    var elementLeft = rect.left + scrollLeft;
                    var targetPage = Math.floor(elementLeft / viewportWidth);
                    var targetX = targetPage * viewportWidth;

                    window.scrollTo(targetX, 0);
                    return true;
                };

                // Scroll to end of document (last page)
                window.scrollToEnd = function() {
                    var contentWidth = document.documentElement.scrollWidth;
                    var viewportWidth = window.innerWidth;
                    var lastPageX = Math.max(0, contentWidth - viewportWidth);
                    // Align to page boundary
                    var targetPage = Math.floor(lastPageX / viewportWidth);
                    window.scrollTo(targetPage * viewportWidth, 0);
                    return true;
                };

                // Get current page info for boundary detection
                window.getPageInfo = function() {
                    var viewportWidth = window.innerWidth;
                    var contentWidth = document.documentElement.scrollWidth;
                    var scrollX = window.scrollX || document.documentElement.scrollLeft;
                    var currentPage = Math.round(scrollX / viewportWidth);
                    var totalPages = Math.ceil(contentWidth / viewportWidth);
                    return {
                        currentPage: currentPage,
                        totalPages: totalPages,
                        isFirstPage: currentPage === 0,
                        isLastPage: currentPage >= totalPages - 1
                    };
                };
            </script>
        </head>
        <body>
            \(processedHTML)
        </body>
        </html>
        """

        // Store restore parameters for use after content loads
        self.pendingCFIRestore = restoreCFI
        self.pendingScrollToEnd = atEnd

        let prepTime = CFAbsoluteTimeGetCurrent() - loadStart
        Self.logger.debug("SPINE: Prepared HTML in \(String(format: "%.3f", prepTime))s, \(wrappedHTML.count) chars")

        webViewLoadStartTime = CFAbsoluteTimeGetCurrent()
        webView.loadHTMLString(wrappedHTML, baseURL: nil)

        // Report loading progress (spine-scoped: always 1/total until locations list is built)
        onLoadingProgress?(index + 1, htmlSections.count)

        // Report spine change
        onSpineChanged?(index, htmlSections.count)
    }

    // Pending restore state (used after WebView finishes loading)
    private var pendingCFIRestore: (domPath: [Int], charOffset: Int?)?
    private var pendingScrollToEnd: Bool = false

    private var webViewLoadStartTime: CFAbsoluteTime = 0

    /// Find the spine index to load initially (based on saved CFI, block ID, or first section)
    private func findInitialSpineIndex() -> Int {
        // Use CFI to find spine index
        if let cfi = initialCFI, let parsed = CFIParser.parseFullCFI(cfi) {
            Self.logger.debug("SPINE: Initial CFI points to spine \(parsed.spineIndex)")
            return min(parsed.spineIndex, htmlSections.count - 1)
        }

        // No saved position - start at beginning
        return 0
    }

    // MARK: - Spine Navigation

    /// Navigate to the next spine item
    /// - Returns: true if navigation occurred, false if already at end
    @discardableResult
    public func navigateToNextSpineItem() -> Bool {
        guard currentSpineIndex < htmlSections.count - 1 else {
            Self.logger.debug("SPINE: Already at last spine item (\(currentSpineIndex))")
            return false
        }

        Self.logger.info("SPINE: Navigating to next spine item (\(currentSpineIndex) -> \(currentSpineIndex + 1))")
        loadSpineItem(at: currentSpineIndex + 1)
        return true
    }

    /// Navigate to the previous spine item
    /// - Returns: true if navigation occurred, false if already at beginning
    @discardableResult
    public func navigateToPreviousSpineItem() -> Bool {
        guard currentSpineIndex > 0 else {
            Self.logger.debug("SPINE: Already at first spine item (0)")
            return false
        }

        Self.logger.info("SPINE: Navigating to previous spine item (\(currentSpineIndex) -> \(currentSpineIndex - 1))")
        loadSpineItem(at: currentSpineIndex - 1, atEnd: true)
        return true
    }


    /// Check if we're at a page boundary and should transition to adjacent spine
    private func checkPageBoundaryAndTransition(goingForward: Bool) {
        let js = "window.getPageInfo();"

        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                Self.logger.error("Failed to get page info: \(error.localizedDescription)")
                return
            }

            guard let info = result as? [String: Any],
                  let isFirstPage = info["isFirstPage"] as? Bool,
                  let isLastPage = info["isLastPage"] as? Bool else {
                return
            }

            if goingForward && isLastPage {
                // At last page going forward -> next spine item
                self.navigateToNextSpineItem()
            } else if !goingForward && isFirstPage {
                // At first page going backward -> previous spine item
                self.navigateToPreviousSpineItem()
            }
        }
    }

    private func processHTMLWithImages(_ html: String, basePath: String, imageCache: [String: Data]) -> String {
        var processedHTML = html

        // Find all img tags and replace src with custom URL scheme
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

            // Check if image exists in cache, then use custom URL scheme
            if imageCache[resolvedPath] != nil || imageCache[(resolvedPath as NSString).lastPathComponent] != nil {
                // Use custom URL scheme - images served via EPUBURLSchemeHandler
                let schemeURL = "\(EPUBURLSchemeHandler.scheme)://image/\(resolvedPath)"
                let newTag = "<img\(beforeAttrs)src=\"\(schemeURL)\"\(afterAttrs)>"

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
        // Query current CFI before reloading
        queryCurrentCFI { [weak self] _, domPath, charOffset, _ in
            guard let self = self else { return }

            // Store position for restore after reload
            let restoreCFI: (domPath: [Int], charOffset: Int?)? = domPath.map { ($0, charOffset) }

            // Reset state for fresh load
            self.hasRestoredPosition = false

            Self.logger.debug("SPINE: Font scale changed, reloading spine \(self.currentSpineIndex) with CFI restore")

            // Reload current spine item with CFI restore
            self.loadSpineItem(at: self.currentSpineIndex, restoreCFI: restoreCFI)
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
            onPageChanged?(currentPage, totalPages)

            // Save CFI position when page changes
            updateCFIPosition()
        }
    }

    public func navigateToNextPage() {
        let scrollView = webView.scrollView
        let pageWidth = currentPageWidth()
        guard pageWidth > 0 else { return }

        let currentOffset = scrollView.contentOffset.x
        let contentWidth = scrollView.contentSize.width
        let boundsWidth = scrollView.bounds.width

        // Calculate the target offset
        let nextOffset = currentOffset + pageWidth
        let maxOffset = max(0, contentWidth - boundsWidth)

        Self.logger.info("NAV: next - current=\(currentOffset), next=\(nextOffset), max=\(maxOffset), pageWidth=\(pageWidth), contentWidth=\(contentWidth)")

        // If we're already at max and trying to go further, transition to next spine
        if currentOffset >= maxOffset - 1 && nextOffset > maxOffset + 1 {
            Self.logger.debug("NAV: at last page, trying next spine")
            if navigateToNextSpineItem() {
                return
            }
            return
        }

        // Normal navigation - clamp to max
        let clampedOffset = min(nextOffset, maxOffset)
        scrollView.setContentOffset(CGPoint(x: clampedOffset, y: 0), animated: true)
    }

    public func navigateToPreviousPage() {
        let scrollView = webView.scrollView
        let pageWidth = currentPageWidth()
        guard pageWidth > 0 else { return }

        let currentOffset = scrollView.contentOffset.x

        Self.logger.debug("NAV: prev - current=\(currentOffset), pageWidth=\(pageWidth)")

        // If at first page and trying to go back, transition to previous spine
        if currentOffset <= 1 {
            Self.logger.debug("NAV: at first page, trying previous spine")
            if navigateToPreviousSpineItem() {
                return
            }
            return
        }

        // Normal navigation
        let prevOffset = max(currentOffset - pageWidth, 0)
        scrollView.setContentOffset(CGPoint(x: prevOffset, y: 0), animated: true)
    }

    // Navigate to a specific page (0-indexed)
    public func navigateToPage(_ pageIndex: Int, animated: Bool = true) {
        let scrollView = webView.scrollView
        let pageWidth = currentPageWidth()
        guard pageWidth > 0 else { return }

        let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let totalPages = Int(ceil(scrollView.contentSize.width / pageWidth))
        let targetX = CGFloat(max(0, pageIndex)) * pageWidth
        let clampedX = min(targetX, maxX)

        Self.logger.info("SLIDER: jumping to page \(pageIndex)/\(totalPages-1) on spine \(self.currentSpineIndex)")

        scrollView.setContentOffset(CGPoint(x: clampedX, y: 0), animated: animated)

        // For non-animated navigation (e.g., scrubber), manually update position
        // since scroll delegate callbacks won't fire
        if !animated {
            DispatchQueue.main.async { [weak self] in
                self?.updateCurrentPage()
                self?.logCurrentPosition("slider")
            }
        }
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
    public func queryFirstVisibleBlock(completion: @escaping (String?, String?) -> Void) {
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
    public func navigateToBlock(_ blockId: String, animated: Bool = false) {
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

    /// Navigate to the first page of a specific spine item (chapter)
    /// With spine-scoped rendering, this loads the spine item as the current document
    /// - Parameters:
    ///   - spineItemId: The spine item ID to navigate to
    ///   - animated: Whether to animate (ignored with spine-scoped rendering)
    public func navigateToSpineItem(_ spineItemId: String, animated: Bool = false) {
        // Find the spine index for this spine item
        guard let spineIndex = htmlSections.firstIndex(where: { $0.spineItemId == spineItemId }) else {
            Self.logger.warning("Spine item \(spineItemId) not found in htmlSections")
            return
        }

        // If already on this spine item, just scroll to start
        if spineIndex == currentSpineIndex {
            Self.logger.debug("SPINE: Already on spine item \(spineItemId), scrolling to start")
            webView.scrollView.setContentOffset(.zero, animated: animated)
            updateCurrentPage()
            return
        }

        // Load the new spine item
        Self.logger.info("SPINE: Loading spine item \(spineItemId) (index \(spineIndex))")
        loadSpineItem(at: spineIndex)
    }

    // MARK: - CFI Position Tracking

    /// Callback when CFI position changes (cfi string, spineIndex)
    /// Used to save reading position for persistence
    public var onCFIPositionChanged: ((_ cfi: String, _ spineIndex: Int) -> Void)?

    /// Query the current CFI position from the WebView
    /// Returns: (spineItemId, domPath, charOffset, spineItemId) via callback
    public func queryCurrentCFI(completion: @escaping (String?, [Int]?, Int?, String?) -> Void) {
        // Pass current page from Swift since it's already calculated from scroll position
        let js = "window.generateCFIForCurrentPosition(\(currentPage));"

        webView.evaluateJavaScript(js) { result, error in
            if let error = error {
                Self.logger.error("Failed to query CFI position: \(error.localizedDescription)")
                completion(nil, nil, nil, nil)
                return
            }

            guard let dict = result as? [String: Any],
                  let domPath = dict["domPath"] as? [Int] else {
                completion(nil, nil, nil, nil)
                return
            }

            let charOffset = dict["charOffset"] as? Int
            let spineItemId = dict["spineItemId"] as? String

            completion(spineItemId, domPath, charOffset, spineItemId)
        }
    }

    /// Navigate to a CFI position within the current document
    /// - Parameters:
    ///   - domPath: Array of 0-based element indices
    ///   - charOffset: Optional character offset within text node
    ///   - animated: Whether to animate the scroll
    public func navigateToCFI(domPath: [Int], charOffset: Int?, animated: Bool = false) {
        var cfiData: [String: Any] = ["domPath": domPath]
        if let offset = charOffset {
            cfiData["charOffset"] = offset
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: cfiData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            Self.logger.error("Failed to serialize CFI data")
            return
        }

        let js = "window.resolveCFI(\(jsonString));"

        webView.evaluateJavaScript(js) { [weak self] result, error in
            if let error = error {
                Self.logger.error("Failed to navigate to CFI: \(error.localizedDescription)")
                return
            }

            if let success = result as? Bool, success {
                Self.logger.info("Navigated to CFI path: \(domPath)")
                // Update page and block position after navigation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.updateCurrentPage()
                    }
            } else {
                Self.logger.warning("CFI navigation failed - element not found")
            }
        }
    }

    /// Update CFI position and notify callback if changed
    private func updateCFIPosition() {
        guard onCFIPositionChanged != nil else { return }

        queryCurrentCFI { [weak self] _, domPath, charOffset, spineItemId in
            guard let self = self, let domPath = domPath else { return }

            // Generate full CFI string from components
            let spineItemIdref = spineItemId ?? self.htmlSections[self.currentSpineIndex].spineItemId
            let cfi = CFIParser.generateFullCFI(
                spineIndex: self.currentSpineIndex,
                idref: spineItemIdref,
                domPath: domPath,
                charOffset: charOffset
            )

            Self.logger.debug("CFI: Generated \(cfi) at spine \(self.currentSpineIndex)")
            self.onCFIPositionChanged?(cfi, self.currentSpineIndex)
        }
    }

    private func prepareForPositionRestore() {
        let shouldHide = PositionRestorePolicy.shouldHideUntilRestore(initialCFI: initialCFI)
        isWaitingForInitialRestore = shouldHide
        webView.isHidden = shouldHide
    }

    private func finishPositionRestoreIfNeeded() {
        guard isWaitingForInitialRestore else { return }
        isWaitingForInitialRestore = false
        webView.isHidden = false
    }
}

// MARK: - UIScrollViewDelegate
extension WebPageViewController: UIScrollViewDelegate {
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // Record initial state for edge detection
        let currentOffset = scrollView.contentOffset.x
        let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)

        dragStartOffset = currentOffset

        // For single-page chapters (maxOffset near 0), both start and end are true
        // This allows spine transitions in either direction
        let isSinglePage = maxOffset < 10

        wasAtEndWhenDragStarted = isSinglePage || currentOffset >= maxOffset - 2
        wasAtStartWhenDragStarted = isSinglePage || currentOffset <= 2

        Self.logger.debug("DRAG START: offset=\(Int(currentOffset)), max=\(Int(maxOffset)), singlePage=\(isSinglePage), atEnd=\(wasAtEndWhenDragStarted), atStart=\(wasAtStartWhenDragStarted)")
    }

    public func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        // Custom page snapping using exact CSS column width
        let pageWidth = currentPageWidth()
        guard pageWidth > 0 else { return }

        let currentOffset = scrollView.contentOffset.x
        let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let maxPage = max(0, round(maxOffset / pageWidth))

        Self.logger.debug("DRAG END: offset=\(Int(currentOffset)), max=\(Int(maxOffset)), velocity=\(velocity.x), atEnd=\(wasAtEndWhenDragStarted), atStart=\(wasAtStartWhenDragStarted)")

        // Check for edge-based spine transitions:
        // If we started at an edge and tried to scroll beyond it, trigger transition
        if wasAtEndWhenDragStarted && velocity.x > 0.05 {
            Self.logger.info("EDGE: Was at end, swiped forward -> transition to next spine")
            if navigateToNextSpineItem() {
                targetContentOffset.pointee = CGPoint(x: currentOffset, y: 0)
                wasAtEndWhenDragStarted = false
                wasAtStartWhenDragStarted = false
                return
            }
        }

        if wasAtStartWhenDragStarted && velocity.x < -0.05 {
            Self.logger.info("EDGE: Was at start, swiped backward -> transition to prev spine")
            if navigateToPreviousSpineItem() {
                targetContentOffset.pointee = CGPoint(x: currentOffset, y: 0)
                wasAtEndWhenDragStarted = false
                wasAtStartWhenDragStarted = false
                return
            }
        }

        // Use floor to get the page we're currently ON (not transitioning to)
        let currentPage = max(0, floor(currentOffset / pageWidth))
        let targetPage: CGFloat

        if velocity.x > 0.2 {
            // Swiping forward
            let nextPage = currentPage + 1
            if nextPage > maxPage {
                // Trying to go past last page - transition to next spine
                Self.logger.info("SWIPE: page \(Int(currentPage))/\(Int(maxPage)), forward past end -> next spine")
                if navigateToNextSpineItem() {
                    // Stop scroll deceleration by setting target to current position
                    // The new spine will load and handle its own positioning
                    targetContentOffset.pointee = CGPoint(x: currentOffset, y: 0)
                    return
                }
                targetPage = maxPage
            } else {
                targetPage = nextPage
            }
        } else if velocity.x < -0.2 {
            // Swiping backward
            let prevPage = currentPage - 1
            if prevPage < 0 {
                // Trying to go before first page - transition to previous spine
                Self.logger.info("SWIPE: page \(Int(currentPage))/\(Int(maxPage)), back past start -> prev spine")
                if navigateToPreviousSpineItem() {
                    // Stop scroll deceleration by setting target to current position
                    // The new spine will load and handle its own positioning
                    targetContentOffset.pointee = CGPoint(x: currentOffset, y: 0)
                    return
                }
                targetPage = 0
            } else {
                targetPage = prevPage
            }
        } else {
            // No significant velocity, snap to nearest
            targetPage = min(maxPage, max(0, round(currentOffset / pageWidth)))
        }

        Self.logger.info("SWIPE: page \(Int(currentPage))/\(Int(maxPage)) -> \(Int(targetPage))")
        targetContentOffset.pointee = CGPoint(x: targetPage * pageWidth, y: 0)
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let pageWidth = currentPageWidth()

        // Check if we landed at an edge and might need to transition
        if pageWidth > 0 {
            let currentOffset = scrollView.contentOffset.x
            let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)

            Self.logger.info("DECEL: offset=\(Int(currentOffset)), max=\(Int(maxOffset)), pageWidth=\(Int(pageWidth))")

            // At the very end - check if we should transition forward
            if currentOffset >= maxOffset - 2 && maxOffset > 0 {
                let currentPage = Int(round(currentOffset / pageWidth))
                let totalPages = Int(ceil(scrollView.contentSize.width / pageWidth))
                Self.logger.info("DECEL: At end (page \(currentPage)/\(totalPages-1)), may need forward transition")
            }

            // At the very beginning - check if we should transition backward
            if currentOffset <= 2 {
                Self.logger.info("DECEL: At start, may need backward transition")
            }
        }

        snapToNearestPage()
        updateCurrentPage()
        logCurrentPosition("decelerate")
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateCurrentPage()
        logCurrentPosition("scroll-anim")
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            // Check if we're at an edge and should transition to another spine
            let pageWidth = currentPageWidth()
            guard pageWidth > 0 else {
                snapToNearestPage()
                updateCurrentPage()
                logCurrentPosition("drag-end")
                return
            }

            let currentOffset = scrollView.contentOffset.x
            let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)

            // If user is at/past the end and trying to go forward (offset > max)
            if currentOffset >= maxOffset - 1 {
                Self.logger.info("EDGE: At end of spine, checking for forward transition")
                if navigateToNextSpineItem() {
                    return
                }
            }

            // If user is at/before the start and trying to go backward (offset < 0)
            if currentOffset <= 1 {
                Self.logger.info("EDGE: At start of spine, checking for backward transition")
                if navigateToPreviousSpineItem() {
                    return
                }
            }

            snapToNearestPage()
            updateCurrentPage()
            logCurrentPosition("drag-end")
        }
    }

    private func logCurrentPosition(_ source: String) {
        let pageWidth = currentPageWidth()
        guard pageWidth > 0 else { return }
        let scrollView = webView.scrollView
        let currentOffset = scrollView.contentOffset.x
        let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let currentPage = Int(round(currentOffset / pageWidth))
        let totalPages = Int(ceil(scrollView.contentSize.width / pageWidth))
        Self.logger.info("PAGE[\(source)]: spine=\(self.currentSpineIndex)/\(self.htmlSections.count-1), page=\(currentPage)/\(totalPages-1), offset=\(Int(currentOffset))/\(Int(maxOffset))")
    }
}

// MARK: - WKNavigationDelegate
extension WebPageViewController: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Allow the initial page load
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        Self.logger.info("Link tapped: \(url.absoluteString)")

        // Handle internal EPUB links
        let urlString = url.absoluteString

        // Extract the file path and optional fragment (anchor) from the URL
        // Links look like: file:///path/to/7972579585791322943_84-h-6.htm.html#chap01
        // Or relative: 7972579585791322943_84-h-6.htm.html#chap01
        let path = url.path
        let filename = (path as NSString).lastPathComponent
        let fragment = url.fragment  // The anchor part after #

        Self.logger.debug("Link filename: \(filename), fragment: \(fragment ?? "none")")

        // Try to find the spine item ID for this file
        if let spineItemId = hrefToSpineItemId[filename] ?? hrefToSpineItemId[path] {
            Self.logger.info("Navigating to spine item: \(spineItemId) (fragment: \(fragment ?? "none"))")

            // If there's a fragment (anchor), try to navigate to that specific element
            if let anchor = fragment {
                navigateToAnchor(anchor, inSpineItem: spineItemId)
            } else {
                navigateToSpineItem(spineItemId, animated: false)
            }

            decisionHandler(.cancel)
            return
        }

        // If we couldn't resolve the link, check if it's an external URL
        if url.scheme == "http" || url.scheme == "https" {
            // Open external links in Safari
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        // Unknown link type - allow default handling
        Self.logger.warning("Could not resolve internal link: \(urlString)")
        decisionHandler(.cancel)
    }

    /// Navigate to a specific anchor within a spine item
    private func navigateToAnchor(_ anchor: String, inSpineItem spineItemId: String) {
        // First navigate to the spine item
        let js = """
        (function() {
            // Find element with this ID
            var element = document.getElementById('\(anchor)');
            if (!element) {
                // Try finding by name attribute
                element = document.querySelector('[name="\(anchor)"]');
            }
            if (!element) {
                // Try finding within the spine item section
                var section = document.querySelector('[data-spine-item-id="\(spineItemId)"]');
                if (section) {
                    element = section.querySelector('#\(anchor)') || section.querySelector('[name="\(anchor)"]');
                }
            }
            if (!element) return null;

            var rect = element.getBoundingClientRect();
            var scrollLeft = window.scrollX || document.documentElement.scrollLeft;
            var viewportWidth = window.innerWidth;
            var elementLeft = rect.left + scrollLeft;
            var targetPage = Math.floor(elementLeft / viewportWidth);

            return targetPage * viewportWidth;
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                Self.logger.error("Failed to navigate to anchor: \(error.localizedDescription)")
                // Fall back to navigating to spine item start
                self.navigateToSpineItem(spineItemId, animated: false)
                return
            }

            if let targetX = result as? Double {
                Self.logger.info("Navigating to anchor \(anchor) at x=\(targetX)")
                self.webView.scrollView.setContentOffset(
                    CGPoint(x: CGFloat(targetX), y: 0),
                    animated: false
                )
                // Update page and block position after navigation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.updateCurrentPage()
                    }
            } else {
                Self.logger.warning("Anchor \(anchor) not found, navigating to spine item start")
                self.navigateToSpineItem(spineItemId, animated: false)
            }
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let navTime = webViewLoadStartTime > 0 ? CFAbsoluteTimeGetCurrent() - webViewLoadStartTime : 0
        Self.logger.info("PERF: WebView didFinish navigation in \(String(format: "%.3f", navTime))s")

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

            // Wait for CSS columns to finish laying out
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }

                // Query exact CSS column width for precise alignment
                self.queryCSSColumnWidth {
                    // Ensure scroll view y-offset is 0 to prevent vertical drift
                    // This must happen synchronously before any async navigation
                    let scrollView = self.webView.scrollView
                    if scrollView.contentOffset.y != 0 {
                        scrollView.setContentOffset(
                            CGPoint(x: scrollView.contentOffset.x, y: 0),
                            animated: false
                        )
                    }

                    // Restore position BEFORE reporting current page/block
                    // This prevents overwriting saved position with initial values
                    if !self.hasRestoredPosition {
                        self.hasRestoredPosition = true
                        let totalLoadTime = self.webViewLoadStartTime > 0 ? CFAbsoluteTimeGetCurrent() - self.webViewLoadStartTime : 0
                        Self.logger.info("PERF: Content ready in \(String(format: "%.3f", totalLoadTime))s total")

                        // Priority 1: CFI-based restoration (most precise)
                        if let cfiRestore = self.pendingCFIRestore {
                            Self.logger.info("SPINE: Restoring position via CFI path")
                            self.pendingCFIRestore = nil
                            self.navigateToCFI(domPath: cfiRestore.domPath, charOffset: cfiRestore.charOffset, animated: false)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                                self?.updateCurrentPage()
                                                self?.finishPositionRestoreIfNeeded()
                                self?.onRenderReady?()
                            }
                        }
                        // Scroll to end (for navigating backward through spine)
                        else if self.pendingScrollToEnd {
                            self.pendingScrollToEnd = false
                            // Use scrollView directly - JS scrollTo doesn't work with WKWebView
                            let scrollView = self.webView.scrollView
                            let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)
                            Self.logger.info("SPINE: Scrolling to end (first load), maxOffset=\(Int(maxOffset))")
                            scrollView.setContentOffset(CGPoint(x: maxOffset, y: 0), animated: false)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                                self?.updateCurrentPage()
                                self?.logCurrentPosition("scroll-to-end")
                                self?.finishPositionRestoreIfNeeded()
                                self?.onRenderReady?()
                            }
                        }
                        // Default: Start at beginning
                        else {
                            self.updateCurrentPage()
                            self.finishPositionRestoreIfNeeded()
                            self.onRenderReady?()
                        }
                    } else {
                        // Handle scrollToEnd for subsequent spine navigations (not first load)
                        if self.pendingScrollToEnd {
                            self.pendingScrollToEnd = false
                            // Use scrollView directly - JS scrollTo doesn't work with WKWebView
                            let scrollView = self.webView.scrollView
                            let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)
                            Self.logger.info("SPINE: Scrolling to end, maxOffset=\(Int(maxOffset))")
                            scrollView.setContentOffset(CGPoint(x: maxOffset, y: 0), animated: false)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                                self?.updateCurrentPage()
                                self?.logCurrentPosition("scroll-to-end")
                                self?.finishPositionRestoreIfNeeded()
                            }
                        } else {
                            self.updateCurrentPage()
                            self.finishPositionRestoreIfNeeded()
                        }
                    }
                }
            }
        }
    }
}
