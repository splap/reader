import Foundation

/// Key that uniquely identifies a layout configuration
/// Locations lists are invalidated when layout changes
public struct LayoutKey: Codable, Hashable, Equatable {
    /// Font scale factor (1.0 = default)
    public let fontScale: Double

    /// Margin size setting
    public let marginSize: Int

    /// Viewport width in points
    public let viewportWidth: Int

    /// Viewport height in points
    public let viewportHeight: Int

    public init(fontScale: Double, marginSize: Int, viewportWidth: Int, viewportHeight: Int) {
        self.fontScale = fontScale
        self.marginSize = marginSize
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
    }

    /// Generate a hash string for use as cache key
    public var hashString: String {
        "\(fontScale)-\(marginSize)-\(viewportWidth)-\(viewportHeight)"
    }
}

/// A list of CFI locations at regular intervals through a book
/// Used for global progress tracking and "page X of Y" display
public struct LocationsList: Codable, Equatable {
    /// Book identifier
    public let bookId: String

    /// Layout configuration when this list was generated
    public let layoutKey: LayoutKey

    /// Array of CFI strings at regular intervals (e.g., every ~1000 characters)
    /// Each CFI points to a specific position in the book
    public let locations: [String]

    /// Indices in the locations array where each spine item starts
    /// locations[spineItemBoundaries[i]] is the first location in spine item i
    public let spineItemBoundaries: [Int]

    /// When this locations list was generated
    public let generatedAt: Date

    /// Interval in characters between locations (for reference)
    public let characterInterval: Int

    public init(
        bookId: String,
        layoutKey: LayoutKey,
        locations: [String],
        spineItemBoundaries: [Int],
        characterInterval: Int = 1024,
        generatedAt: Date = Date()
    ) {
        self.bookId = bookId
        self.layoutKey = layoutKey
        self.locations = locations
        self.spineItemBoundaries = spineItemBoundaries
        self.characterInterval = characterInterval
        self.generatedAt = generatedAt
    }

    /// Total number of "pages" (locations)
    public var totalLocations: Int {
        locations.count
    }

    /// Find the location index for a given CFI
    /// Returns the index of the location at or before the given CFI
    public func locationIndex(for cfi: String) -> Int? {
        // Parse the CFI to get spine index
        guard let parsed = CFIParser.parseFullCFI(cfi) else { return nil }
        let spineIndex = parsed.spineIndex

        // Find the spine boundary
        guard spineIndex < spineItemBoundaries.count else { return nil }
        let spineStart = spineItemBoundaries[spineIndex]
        let spineEnd = spineIndex + 1 < spineItemBoundaries.count
            ? spineItemBoundaries[spineIndex + 1]
            : locations.count

        // Binary search within spine for the closest location
        // For now, return the spine start as a simple approximation
        // A more accurate implementation would compare DOM paths
        return spineStart
    }

    /// Get the CFI at a specific location index
    public func cfi(at index: Int) -> String? {
        guard index >= 0, index < locations.count else { return nil }
        return locations[index]
    }

    /// Get the spine item index for a location
    public func spineIndex(for locationIndex: Int) -> Int? {
        guard locationIndex >= 0, locationIndex < locations.count else { return nil }

        // Find which spine item this location belongs to
        for (index, boundary) in spineItemBoundaries.enumerated().reversed() {
            if locationIndex >= boundary {
                return index
            }
        }
        return 0
    }
}

// MARK: - Locations List Storage

/// Protocol for storing and retrieving locations lists
public protocol LocationsListStoring {
    /// Load a locations list for a book with a specific layout
    func load(bookId: String, layoutKey: LayoutKey) async -> LocationsList?

    /// Save a locations list
    func save(_ locationsList: LocationsList) async throws

    /// Delete all locations lists for a book
    func deleteBook(bookId: String) async throws

    /// Check if a valid locations list exists for this book and layout
    func hasValidList(bookId: String, layoutKey: LayoutKey) async -> Bool
}

/// In-memory cache for locations lists (for fast lookups)
public actor LocationsListCache: LocationsListStoring {
    private var cache: [String: LocationsList] = [:]

    public init() {}

    private func cacheKey(bookId: String, layoutKey: LayoutKey) -> String {
        "\(bookId):\(layoutKey.hashString)"
    }

    public func load(bookId: String, layoutKey: LayoutKey) async -> LocationsList? {
        cache[cacheKey(bookId: bookId, layoutKey: layoutKey)]
    }

    public func save(_ locationsList: LocationsList) async throws {
        let key = cacheKey(bookId: locationsList.bookId, layoutKey: locationsList.layoutKey)
        cache[key] = locationsList
    }

    public func deleteBook(bookId: String) async throws {
        cache = cache.filter { !$0.key.hasPrefix("\(bookId):") }
    }

    public func hasValidList(bookId: String, layoutKey: LayoutKey) async -> Bool {
        cache[cacheKey(bookId: bookId, layoutKey: layoutKey)] != nil
    }
}
