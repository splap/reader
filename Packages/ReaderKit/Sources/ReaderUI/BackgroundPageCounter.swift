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

    /// Start counting pages for all spine items using lazy loading
    /// - Parameters:
    ///   - lazyChapter: The lazy chapter to count pages for
    ///   - bookId: Book identifier for caching (use the library's UUID, not the filename)
    ///   - layoutKey: Current layout configuration
    public func startCounting(
        lazyChapter: LazyChapter,
        bookId: String,
        layoutKey: LayoutKey
    ) {
        // Cancel any existing counting task
        cancel()

        guard lazyChapter.sectionCount > 0 else {
            Self.logger.warning("No sections to count")
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
                    lazyChapter: lazyChapter,
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
        lazyChapter: LazyChapter,
        bookId: String,
        layoutKey: LayoutKey
    ) async {
        let totalSpines = lazyChapter.sectionCount
        status = .counting(completed: 0, total: totalSpines)

        Self.logger.info("Starting page count for \(totalSpines) spine items, layout: \(layoutKey.hashString)")

        // Create hidden WebView with image cache from lazy chapter metadata
        let webView = createHiddenWebView(imageCache: lazyChapter.spineMetadata.imageCache, layoutKey: layoutKey)
        hiddenWebView = webView

        var spinePageCounts: [Int] = []

        for index in 0 ..< totalSpines {
            if Task.isCancelled {
                Self.logger.info("Page counting cancelled at spine \(index)")
                return
            }

            do {
                // Load section off main thread (ZIP I/O + HTML parsing can block for seconds)
                let section = try await Task.detached(priority: .utility) {
                    try lazyChapter.section(at: index)
                }.value

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

    private func createHiddenWebView(imageCache: [String: Data], layoutKey: LayoutKey) -> WKWebView {
        // Create URL scheme handler for serving images
        let schemeHandler = EPUBURLSchemeHandler(imageCache: imageCache)
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
        // Use shared HTML renderer to ensure identical rendering with WebPageViewController
        let wrappedHTML = SectionHTMLRenderer.generateSectionHTML(section: section, layoutKey: layoutKey)

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
