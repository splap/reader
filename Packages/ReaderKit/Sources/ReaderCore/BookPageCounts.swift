import Foundation

/// Page counts for each spine item in a book, keyed by layout configuration
public struct BookPageCounts: Codable, Equatable {
    /// Book identifier
    public let bookId: String

    /// Layout configuration when these counts were generated
    public let layoutKey: LayoutKey

    /// Page count for each spine item (index = spine index)
    public let spinePageCounts: [Int]

    /// Total pages across all spine items
    public var totalPages: Int {
        spinePageCounts.reduce(0, +)
    }

    public init(bookId: String, layoutKey: LayoutKey, spinePageCounts: [Int]) {
        self.bookId = bookId
        self.layoutKey = layoutKey
        self.spinePageCounts = spinePageCounts
    }

    /// Calculate the global page number (1-indexed for display) from spine index and local page
    /// - Parameters:
    ///   - spineIndex: Current spine item index
    ///   - localPage: Page within the current spine item (0-indexed)
    /// - Returns: Global page number (1-indexed)
    public func globalPage(spineIndex: Int, localPage: Int) -> Int {
        guard spineIndex >= 0, spineIndex < spinePageCounts.count else {
            return 1
        }
        let priorPages = spinePageCounts[0 ..< spineIndex].reduce(0, +)
        return priorPages + localPage + 1
    }

    /// Get the starting global page for a spine item
    /// - Parameter spineIndex: Spine item index
    /// - Returns: First global page of that spine (1-indexed)
    public func startingPage(forSpine spineIndex: Int) -> Int {
        guard spineIndex > 0, spineIndex <= spinePageCounts.count else {
            return 1
        }
        return spinePageCounts[0 ..< spineIndex].reduce(0, +) + 1
    }

    /// Convert a global page number (1-indexed) to spine index and local page (0-indexed)
    /// - Parameter globalPage: Global page number (1-indexed)
    /// - Returns: Tuple of (spineIndex, localPage) where localPage is 0-indexed
    public func localPosition(forGlobalPage globalPage: Int) -> (spineIndex: Int, localPage: Int) {
        guard globalPage >= 1, !spinePageCounts.isEmpty else {
            return (0, 0)
        }

        var remaining = globalPage - 1 // Convert to 0-indexed
        for (index, count) in spinePageCounts.enumerated() {
            if remaining < count {
                return (index, remaining)
            }
            remaining -= count
        }

        // Past the end - return last page of last spine
        let lastIndex = spinePageCounts.count - 1
        let lastPage = max(0, spinePageCounts[lastIndex] - 1)
        return (lastIndex, lastPage)
    }
}

/// In-memory cache for book page counts
public actor BookPageCountsCache {
    public static let shared = BookPageCountsCache()

    private var cache: [String: BookPageCounts] = [:]

    private init() {}

    private func cacheKey(bookId: String, layoutKey: LayoutKey) -> String {
        "\(bookId):\(layoutKey.hashString)"
    }

    /// Retrieve cached page counts for a book with a specific layout
    public func get(bookId: String, layoutKey: LayoutKey) -> BookPageCounts? {
        cache[cacheKey(bookId: bookId, layoutKey: layoutKey)]
    }

    /// Store page counts in the cache
    public func set(_ pageCounts: BookPageCounts) {
        let key = cacheKey(bookId: pageCounts.bookId, layoutKey: pageCounts.layoutKey)
        cache[key] = pageCounts
    }

    /// Remove all cached page counts for a book (all layouts)
    public func invalidate(bookId: String) {
        cache = cache.filter { !$0.key.hasPrefix("\(bookId):") }
    }

    /// Remove all cached data
    public func invalidateAll() {
        cache.removeAll()
    }
}
