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
    private var initialPageIndex: Int = 0  // Page to navigate to after content loads (legacy)
    private var initialBlockId: String?  // Block ID to navigate to after content loads (preferred)
    private var hasRestoredPosition = false  // Track if we've restored position
    private var currentBlockId: String?  // Currently visible block ID
    private var currentSpineItemId: String?  // Currently visible spine item ID
    private var urlSchemeHandler: EPUBURLSchemeHandler?  // Handler for serving images
    private let hrefToSpineItemId: [String: String]  // Map from file href to spineItemId for link resolution

    // Progressive loading state
    private var loadedSectionIndices: Set<Int> = []
    private var isLoadingSection = false
    private var backgroundLoadingTask: Task<Void, Never>?

    // MARK: - PageRenderer Protocol Properties

    public var viewController: UIViewController { self }

    public var fontScale: CGFloat = 2.0 {
        didSet {
            guard fontScale != oldValue else { return }
            reloadWithNewFontScale()
        }
    }

    public var onPageChanged: ((Int, Int) -> Void)?
    public var onBlockPositionChanged: ((String, String?) -> Void)?
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
        initialPageIndex: Int = 0,
        initialBlockId: String? = nil,
        hrefToSpineItemId: [String: String] = [:]
    ) {
        self.htmlSections = htmlSections
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.chapterTitle = chapterTitle
        self.fontScale = fontScale
        self.initialPageIndex = initialPageIndex
        self.initialBlockId = initialBlockId
        self.hrefToSpineItemId = hrefToSpineItemId
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
        webView.scrollView.alwaysBounceHorizontal = false
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
        let loadStart = CFAbsoluteTimeGetCurrent()

        // Find the initial section to load (just ONE section for fast startup)
        let initialSectionIndex = findInitialSectionIndex()
        loadedSectionIndices = [initialSectionIndex]

        Self.logger.debug("SECTION-LOAD: Starting with section \(initialSectionIndex) of \(htmlSections.count) total")

        // Build HTML for just the initial section
        let section = htmlSections[initialSectionIndex]
        let bodyContent = extractBodyContent(from: section.annotatedHTML)
        let processedHTML = processHTMLWithImages(bodyContent, basePath: section.basePath, imageCache: section.imageCache)
        let sectionHTML = "<div class=\"spine-item-section\" data-section-index=\"\(initialSectionIndex)\">\(processedHTML)</div>"

        // Collect publisher CSS from the initial section
        var publisherCSS = ""
        if let css = section.cssContent, !css.isEmpty {
            publisherCSS = css
        }

        Self.logger.debug("SECTION-LOAD: Initial section HTML: \(sectionHTML.count) chars, CSS: \(publisherCSS.count) chars")

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

                // Function to inject a new section at the correct position
                window.injectSection = function(html, sectionIndex) {
                    var newDiv = document.createElement('div');
                    newDiv.innerHTML = html;
                    var newSection = newDiv.firstElementChild;

                    var body = document.body;
                    var sections = body.querySelectorAll('.spine-item-section');

                    // Find the right position to insert
                    var inserted = false;
                    for (var i = 0; i < sections.length; i++) {
                        var existingIndex = parseInt(sections[i].getAttribute('data-section-index'));
                        if (sectionIndex < existingIndex) {
                            body.insertBefore(newSection, sections[i]);
                            inserted = true;
                            break;
                        }
                    }
                    if (!inserted) {
                        body.appendChild(newSection);
                    }

                    // Force layout recalculation
                    body.offsetHeight;

                    // Return new content width for page count update
                    return document.documentElement.scrollWidth;
                };
            </script>
        </head>
        <body>
            \(sectionHTML)
        </body>
        </html>
        """

        let prepTime = CFAbsoluteTimeGetCurrent() - loadStart
        Self.logger.debug("SECTION-LOAD: Prepared initial HTML in \(String(format: "%.3f", prepTime))s, \(wrappedHTML.count) chars")

        webViewLoadStartTime = CFAbsoluteTimeGetCurrent()
        webView.loadHTMLString(wrappedHTML, baseURL: nil)

        // Report initial loading progress
        onLoadingProgress?(1, htmlSections.count)
    }

    private var webViewLoadStartTime: CFAbsoluteTime = 0

    /// Find the section index to load initially (based on saved position or first section)
    private func findInitialSectionIndex() -> Int {
        // If we have a saved block ID, find its section
        if let blockId = initialBlockId {
            for (index, section) in htmlSections.enumerated() {
                if section.blocks.contains(where: { $0.id == blockId }) {
                    Self.logger.debug("SECTION-LOAD: Found initial block \(blockId) in section \(index)")
                    return index
                }
            }
        }
        // Default to first section
        return 0
    }

    /// Start loading remaining sections in the background
    public func startBackgroundLoading() {
        // Cancel any existing background loading
        backgroundLoadingTask?.cancel()

        let totalSections = htmlSections.count
        guard totalSections > 1 else {
            Self.logger.debug("SECTION-LOAD: Only 1 section, no background loading needed")
            return
        }

        Self.logger.debug("SECTION-LOAD: Starting background load of \(totalSections - loadedSectionIndices.count) remaining sections")

        backgroundLoadingTask = Task { [weak self] in
            guard let self = self else { return }

            // Load sections in order, skipping already loaded ones
            for sectionIndex in 0..<totalSections {
                if Task.isCancelled { break }

                // Skip already loaded sections
                if self.loadedSectionIndices.contains(sectionIndex) {
                    continue
                }

                // Small delay between sections to avoid overwhelming the device
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

                if Task.isCancelled { break }

                await self.loadSectionInBackground(sectionIndex)
            }

            Self.logger.debug("SECTION-LOAD: Background loading complete - \(self.loadedSectionIndices.count) sections loaded")
        }
    }

    /// Load a single section and inject it into the WebView
    @MainActor
    private func loadSectionInBackground(_ sectionIndex: Int) async {
        guard !loadedSectionIndices.contains(sectionIndex) else { return }
        guard sectionIndex >= 0 && sectionIndex < htmlSections.count else { return }

        let loadStart = CFAbsoluteTimeGetCurrent()

        let section = htmlSections[sectionIndex]
        let bodyContent = extractBodyContent(from: section.annotatedHTML)
        let processedHTML = processHTMLWithImages(bodyContent, basePath: section.basePath, imageCache: section.imageCache)

        // Escape the HTML for JavaScript string
        let escapedHTML = processedHTML
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "'", with: "\\'")

        let sectionDivHTML = "<div class=\\\"spine-item-section\\\" data-section-index=\\\"\(sectionIndex)\\\">\(escapedHTML)</div>"

        let prepTime = CFAbsoluteTimeGetCurrent() - loadStart

        // Inject the section via JavaScript
        let js = "window.injectSection('\(sectionDivHTML)', \(sectionIndex));"

        let injectStart = CFAbsoluteTimeGetCurrent()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            webView.evaluateJavaScript(js) { [weak self] result, error in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                let injectTime = CFAbsoluteTimeGetCurrent() - injectStart
                let totalTime = CFAbsoluteTimeGetCurrent() - loadStart

                if let error = error {
                    Self.logger.error("SECTION-LOAD: Failed to inject section \(sectionIndex): \(error.localizedDescription)")
                } else {
                    self.loadedSectionIndices.insert(sectionIndex)

                    // Log performance
                    let htmlSize = processedHTML.count
                    Self.logger.debug("SECTION-LOAD: Section \(sectionIndex) loaded - prep: \(String(format: "%.3f", prepTime))s, inject: \(String(format: "%.3f", injectTime))s, total: \(String(format: "%.3f", totalTime))s, size: \(htmlSize) chars")

                    // Query memory stats
                    self.logMemoryStats(afterSection: sectionIndex)

                    // Update page count
                    self.updatePageCountAfterInjection()

                    // Report progress
                    let loadedCount = self.loadedSectionIndices.count
                    let totalCount = self.htmlSections.count
                    Self.logger.debug("SECTION-LOAD: Reporting progress \(loadedCount)/\(totalCount)")
                    self.onLoadingProgress?(loadedCount, totalCount)
                }

                continuation.resume()
            }
        }
    }

    /// Log process memory usage (iOS process memory, not JavaScript)
    private func logMemoryStats(afterSection sectionIndex: Int) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1_000_000
            Self.logger.debug("SECTION-LOAD: Memory after section \(sectionIndex) - process: \(String(format: "%.1f", usedMB))MB")
        } else {
            Self.logger.debug("SECTION-LOAD: Memory stats unavailable (section \(sectionIndex))")
        }
    }

    /// Update page count after injecting a section
    private func updatePageCountAfterInjection() {
        queryCSSColumnWidth { [weak self] in
            self?.updateCurrentPage()
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
        // Cancel any existing background loading
        backgroundLoadingTask?.cancel()
        backgroundLoadingTask = nil

        // Save current position using block ID (not scroll percentage)
        // This works correctly with progressive loading
        if let blockId = currentBlockId {
            initialBlockId = blockId
            Self.logger.debug("SECTION-LOAD: Font scale changed, will restore to block \(blockId)")
        }

        // Reset state for fresh load
        hasRestoredPosition = false
        loadedSectionIndices.removeAll()

        // Reload content - will load section containing initialBlockId
        loadContent()

        // Position restoration happens automatically via initialBlockId in webView(_:didFinish:)
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
        }
    }

    public func navigateToNextPage() {
        let scrollView = webView.scrollView
        let pageWidth = currentPageWidth()
        let nextOffset = min(scrollView.contentOffset.x + pageWidth, scrollView.contentSize.width - pageWidth)
        scrollView.setContentOffset(CGPoint(x: nextOffset, y: 0), animated: true)
    }

    public func navigateToPreviousPage() {
        let scrollView = webView.scrollView
        let pageWidth = currentPageWidth()
        let prevOffset = max(scrollView.contentOffset.x - pageWidth, 0)
        scrollView.setContentOffset(CGPoint(x: prevOffset, y: 0), animated: true)
    }

    // Navigate to a specific page (0-indexed)
    public func navigateToPage(_ pageIndex: Int, animated: Bool = true) {
        let scrollView = webView.scrollView
        let pageWidth = currentPageWidth()
        guard pageWidth > 0 else { return }

        let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let targetX = CGFloat(max(0, pageIndex)) * pageWidth
        let clampedX = min(targetX, maxX)

        scrollView.setContentOffset(CGPoint(x: clampedX, y: 0), animated: animated)

        // For non-animated navigation (e.g., scrubber), manually update position
        // since scroll delegate callbacks won't fire
        if !animated {
            DispatchQueue.main.async { [weak self] in
                self?.updateCurrentPage()
                self?.updateBlockPosition()
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
    /// - Parameters:
    ///   - spineItemId: The spine item ID to navigate to
    ///   - animated: Whether to animate the scroll
    public func navigateToSpineItem(_ spineItemId: String, animated: Bool = false) {
        // Find the section index for this spine item
        guard let sectionIndex = htmlSections.firstIndex(where: { $0.spineItemId == spineItemId }) else {
            Self.logger.warning("Spine item \(spineItemId) not found in htmlSections")
            return
        }

        // If section not loaded, load it first then navigate
        if !loadedSectionIndices.contains(sectionIndex) {
            Self.logger.debug("SECTION-LOAD: Loading section \(sectionIndex) for navigation to \(spineItemId)")
            Task { @MainActor in
                await self.loadSectionInBackground(sectionIndex)
                self.performSpineItemNavigation(spineItemId, animated: animated)
            }
        } else {
            performSpineItemNavigation(spineItemId, animated: animated)
        }
    }

    /// Actually perform the navigation (section must be loaded)
    private func performSpineItemNavigation(_ spineItemId: String, animated: Bool) {
        let js = """
        (function() {
            // Find the first element with this spine item ID
            const element = document.querySelector('[data-spine-item-id="\(spineItemId)"]');
            if (!element) return null;

            const rect = element.getBoundingClientRect();
            const scrollLeft = window.scrollX || document.documentElement.scrollLeft;

            // Calculate the page that contains this element
            const viewportWidth = window.innerWidth;
            const elementLeft = rect.left + scrollLeft;
            const targetPage = Math.floor(elementLeft / viewportWidth);

            return targetPage * viewportWidth;
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                Self.logger.error("Failed to navigate to spine item: \(error.localizedDescription)")
                return
            }

            if let targetX = result as? Double {
                Self.logger.info("Navigating to spine item \(spineItemId) at x=\(targetX)")
                self.webView.scrollView.setContentOffset(
                    CGPoint(x: CGFloat(targetX), y: 0),
                    animated: animated
                )

                // Update page and block position after navigation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.updateCurrentPage()
                    self?.updateBlockPosition()
                }
            } else {
                Self.logger.warning("Spine item \(spineItemId) not found in content after loading")
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
    public func scrollViewWillEndDragging(
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

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        snapToNearestPage()
        updateCurrentPage()
        updateBlockPosition()
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateCurrentPage()
        updateBlockPosition()
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            snapToNearestPage()
            updateCurrentPage()
            updateBlockPosition()
        }
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
                    self?.updateBlockPosition()
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

                        // Prefer block-based restoration over page-based
                        if let blockId = self.initialBlockId {
                            Self.logger.info("Restoring position to block \(blockId)")
                            self.navigateToBlock(blockId, animated: false)
                            // Wait for scroll to complete before updating position
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                                self?.updateCurrentPage()
                                self?.updateBlockPosition()
                                self?.onRenderReady?()
                            }
                        } else if self.initialPageIndex > 0 {
                            // Fallback to legacy page-based restoration
                            Self.logger.info("Restoring position to page \(self.initialPageIndex)")
                            self.navigateToPage(self.initialPageIndex, animated: false)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                                self?.updateCurrentPage()
                                self?.updateBlockPosition()
                                self?.onRenderReady?()
                            }
                        } else {
                            self.updateCurrentPage()
                            self.updateBlockPosition()
                            self.onRenderReady?()
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
