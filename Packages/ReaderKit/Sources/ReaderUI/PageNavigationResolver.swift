import CoreGraphics

/// Input to the page navigation resolver describing the current drag state.
public struct NavigationInput: Equatable {
    /// The page the user was on when they started dragging (0-indexed)
    public let startPage: Int
    /// The nearest page to the current scroll offset at finger lift (0-indexed)
    public let currentPage: Int
    /// Total number of pages in the current spine item
    public let totalPages: Int
    /// Horizontal velocity at finger lift (positive = forward/left swipe, negative = backward/right swipe)
    public let velocity: CGFloat
    /// Current spine index (0-indexed)
    public let spineIndex: Int
    /// Total number of spine items in the book
    public let totalSpines: Int

    public init(startPage: Int, currentPage: Int, totalPages: Int, velocity: CGFloat, spineIndex: Int, totalSpines: Int) {
        self.startPage = startPage
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.velocity = velocity
        self.spineIndex = spineIndex
        self.totalSpines = totalSpines
    }
}

/// The resolved action for a page navigation gesture.
public enum NavigationAction: Equatable {
    /// Snap to a specific page within the current spine item (0-indexed)
    case snapToPage(Int)
    /// Transition to the next spine item (chapter)
    case transitionForward
    /// Transition to the previous spine item (chapter)
    case transitionBackward
    /// Bounce at the edge (already at first/last spine, nowhere to go)
    case bounce
}

/// Pure decision function for page navigation.
/// Takes page state + velocity, returns one of four actions.
/// No UIKit dependencies - fully testable.
public enum PageNavigationResolver {
    /// Velocity threshold for triggering a page turn. Must be exceeded (not just equaled).
    public static let velocityThreshold: CGFloat = 0.5

    /// Resolve the navigation action for a given input.
    public static func resolve(_ input: NavigationInput) -> NavigationAction {
        let maxPage = max(0, input.totalPages - 1)
        let isOnLastPage = input.startPage >= maxPage
        let isOnFirstPage = input.startPage <= 0

        // Forward swipe (velocity > threshold)
        if input.velocity > velocityThreshold {
            if isOnLastPage {
                // At last page: try spine transition forward
                if input.spineIndex < input.totalSpines - 1 {
                    return .transitionForward
                } else {
                    return .bounce
                }
            } else {
                // Mid-chapter: advance one page
                return .snapToPage(min(input.startPage + 1, maxPage))
            }
        }

        // Backward swipe (velocity < -threshold)
        if input.velocity < -velocityThreshold {
            if isOnFirstPage {
                // At first page: try spine transition backward
                if input.spineIndex > 0 {
                    return .transitionBackward
                } else {
                    return .bounce
                }
            } else {
                // Mid-chapter: go back one page
                return .snapToPage(max(input.startPage - 1, 0))
            }
        }

        // Below threshold: snap to nearest page at finger lift (prevents overshoot)
        let clampedPage = max(0, min(input.currentPage, maxPage))
        return .snapToPage(clampedPage)
    }
}
