import Foundation
import OSLog

/// Service for managing page layout calculations with caching
public actor PageLayoutService {
    private static let logger = Logger(subsystem: "com.splap.reader", category: "PageLayoutService")

    /// Shared instance
    public static let shared = PageLayoutService()

    private let store = PageLayoutStore.shared

    private init() {}

    // MARK: - Public API

    /// Gets a cached layout or returns nil if not cached
    /// Use this for fast cache-only lookups
    public func getCachedLayout(
        bookId: String,
        spineItemId: String,
        config: LayoutConfig
    ) async -> ChapterLayout? {
        do {
            let layout = try await store.loadLayout(bookId: bookId, spineItemId: spineItemId, config: config)
            if layout != nil {
                Self.logger.debug("Cache hit: layout for \(spineItemId)")
            }
            return layout
        } catch {
            Self.logger.error("Failed to load layout: \(error.localizedDescription)")
            return nil
        }
    }

    /// Saves a calculated layout to the cache
    public func saveLayout(_ layout: ChapterLayout) async {
        do {
            try await store.saveLayout(layout)
            Self.logger.debug("Cache save: layout for \(layout.spineItemId) with \(layout.totalPages) pages")
        } catch {
            Self.logger.error("Failed to save layout: \(error.localizedDescription)")
        }
    }

    /// Checks if a layout is cached
    public func hasLayout(
        bookId: String,
        spineItemId: String,
        config: LayoutConfig
    ) async -> Bool {
        do {
            return try await store.hasLayout(bookId: bookId, spineItemId: spineItemId, config: config)
        } catch {
            return false
        }
    }

    /// Deletes all cached layouts for a book
    public func invalidateBook(bookId: String) async {
        do {
            try await store.deleteLayouts(bookId: bookId)
            Self.logger.info("Cache invalidate: all layouts for book \(bookId)")
        } catch {
            Self.logger.error("Failed to invalidate layouts: \(error.localizedDescription)")
        }
    }

    /// Gets the count of cached layouts for a book
    public func cachedLayoutCount(bookId: String) async -> Int {
        do {
            return try await store.layoutCount(bookId: bookId)
        } catch {
            return 0
        }
    }
}
