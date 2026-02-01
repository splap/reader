import Foundation
import OSLog

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

/// Cache for book page counts with disk persistence
/// Uses memory cache for fast lookups, persists to disk for cross-session retention
public actor BookPageCountsCache {
    private static let logger = Log.logger(category: "page-cache")

    public static let shared = BookPageCountsCache()

    /// In-memory cache for fast lookups
    private var cache: [String: BookPageCounts] = [:]

    /// Directory for persisted cache files
    private let cacheDirectory: URL

    private init() {
        // Use Library/Caches/PageCounts/ for cache files
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDir.appendingPathComponent("PageCounts", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private func cacheKey(bookId: String, layoutKey: LayoutKey) -> String {
        "\(bookId):\(layoutKey.hashString)"
    }

    /// Generate a safe filename for disk storage
    private func cacheFileName(bookId: String, layoutKey: LayoutKey) -> String {
        // Sanitize bookId to be filesystem-safe
        let safeBookId = bookId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return "\(safeBookId)_\(layoutKey.hashString).json"
    }

    private func cacheFileURL(bookId: String, layoutKey: LayoutKey) -> URL {
        cacheDirectory.appendingPathComponent(cacheFileName(bookId: bookId, layoutKey: layoutKey))
    }

    /// Retrieve cached page counts for a book with a specific layout
    /// Checks memory cache first, then disk
    public func get(bookId: String, layoutKey: LayoutKey) -> BookPageCounts? {
        let key = cacheKey(bookId: bookId, layoutKey: layoutKey)

        // Check memory cache first
        if let cached = cache[key] {
            return cached
        }

        // Try loading from disk
        let fileURL = cacheFileURL(bookId: bookId, layoutKey: layoutKey)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let pageCounts = try JSONDecoder().decode(BookPageCounts.self, from: data)

            // Validate that the loaded data matches the requested key
            guard pageCounts.bookId == bookId, pageCounts.layoutKey == layoutKey else {
                Self.logger.warning("Disk cache mismatch for \(bookId), removing stale file")
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }

            // Store in memory cache for faster subsequent access
            cache[key] = pageCounts
            Self.logger.debug("Loaded page counts from disk for \(bookId)")
            return pageCounts
        } catch {
            Self.logger.error("Failed to load page counts from disk: \(error.localizedDescription)")
            // Remove corrupted file
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    /// Store page counts in both memory and disk cache
    public func set(_ pageCounts: BookPageCounts) {
        let key = cacheKey(bookId: pageCounts.bookId, layoutKey: pageCounts.layoutKey)

        // Store in memory
        cache[key] = pageCounts

        // Persist to disk
        let fileURL = cacheFileURL(bookId: pageCounts.bookId, layoutKey: pageCounts.layoutKey)
        do {
            let data = try JSONEncoder().encode(pageCounts)
            try data.write(to: fileURL, options: .atomic)
            Self.logger.debug("Persisted page counts to disk for \(pageCounts.bookId)")
        } catch {
            Self.logger.error("Failed to persist page counts to disk: \(error.localizedDescription)")
        }
    }

    /// Remove all cached page counts for a book (all layouts)
    public func invalidate(bookId: String) {
        // Remove from memory cache
        cache = cache.filter { !$0.key.hasPrefix("\(bookId):") }

        // Remove disk files for this book
        let safeBookId = bookId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        do {
            let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in files where file.lastPathComponent.hasPrefix(safeBookId + "_") {
                try FileManager.default.removeItem(at: file)
            }
            Self.logger.debug("Invalidated disk cache for book \(bookId)")
        } catch {
            Self.logger.error("Failed to invalidate disk cache: \(error.localizedDescription)")
        }
    }

    /// Remove all cached data (memory and disk)
    public func invalidateAll() {
        cache.removeAll()

        do {
            let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
            Self.logger.debug("Invalidated all page count caches")
        } catch {
            Self.logger.error("Failed to invalidate all disk caches: \(error.localizedDescription)")
        }
    }
}
