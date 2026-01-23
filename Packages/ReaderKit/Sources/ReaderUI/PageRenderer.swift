import UIKit
import ReaderCore

/// Protocol defining the interface for page renderers
/// Both WebView and native attributed string renderers implement this protocol
public protocol PageRenderer: AnyObject {
    /// The view controller to embed in the reader
    var viewController: UIViewController { get }

    /// Current font scale (1.0 - 1.8)
    var fontScale: CGFloat { get set }

    /// Navigate to next page
    func navigateToNextPage()

    /// Navigate to previous page
    func navigateToPreviousPage()

    /// Navigate to specific page index
    func navigateToPage(_ pageIndex: Int, animated: Bool)

    /// Navigate to a specific block by ID (preferred for position restoration)
    func navigateToBlock(_ blockId: String, animated: Bool)

    /// Navigate to the first page of a specific spine item (chapter)
    func navigateToSpineItem(_ spineItemId: String, animated: Bool)

    /// Query the first visible block ID and spine item ID
    func queryFirstVisibleBlock(completion: @escaping (_ blockId: String?, _ spineItemId: String?) -> Void)

    /// Callback when page changes (currentPage, totalPages)
    var onPageChanged: ((_ currentPage: Int, _ totalPages: Int) -> Void)? { get set }

    /// Callback when visible block changes
    var onBlockPositionChanged: ((_ blockId: String, _ spineItemId: String?) -> Void)? { get set }

    /// Callback for text selection sent to LLM
    var onSendToLLM: ((SelectionPayload) -> Void)? { get set }

    /// Callback when rendering is complete and content is ready for display
    /// This is fired after CSS layout is complete (WebView) or after buildPages() completes (Native)
    var onRenderReady: (() -> Void)? { get set }
}
