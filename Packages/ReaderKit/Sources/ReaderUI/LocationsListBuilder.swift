import Foundation
import WebKit
import ReaderCore
import OSLog

/// Builds a LocationsList by generating CFIs at regular intervals through the book
/// This runs in the background after the initial spine item loads
public actor LocationsListBuilder {
    private static let logger = Log.logger(category: "locations")

    /// Default character interval between locations
    public static let defaultInterval = 1024

    /// Build status for progress reporting
    public enum Status: Equatable {
        case idle
        case building(current: Int, total: Int)
        case complete(LocationsList)
        case failed(String)
    }

    private var status: Status = .idle
    private var buildTask: Task<LocationsList?, Never>?

    public init() {}

    /// Get current build status
    public func getStatus() -> Status {
        status
    }

    /// Cancel any ongoing build
    public func cancel() {
        buildTask?.cancel()
        buildTask = nil
        status = .idle
    }

    /// Build a locations list for the given book
    /// - Parameters:
    ///   - htmlSections: The HTML sections (spine items) of the book
    ///   - bookId: Book identifier
    ///   - layoutKey: Current layout configuration
    ///   - characterInterval: Characters between each location
    ///   - webViewProvider: Closure that provides a WKWebView for generating locations
    /// - Returns: The built locations list, or nil if cancelled/failed
    public func build(
        htmlSections: [HTMLSection],
        bookId: String,
        layoutKey: LayoutKey,
        characterInterval: Int = defaultInterval,
        webViewProvider: @escaping @Sendable () async -> WKWebView?
    ) async -> LocationsList? {
        // Cancel any existing build
        cancel()

        status = .building(current: 0, total: htmlSections.count)

        let task = Task<LocationsList?, Never> { [weak self] in
            guard let self = self else { return nil }

            var allLocations: [String] = []
            var spineItemBoundaries: [Int] = []

            for (index, section) in htmlSections.enumerated() {
                if Task.isCancelled {
                    await self.setStatus(.idle)
                    return nil
                }

                await self.setStatus(.building(current: index, total: htmlSections.count))

                // Generate locations for this spine item
                let spineLocations = await self.generateLocationsForSpine(
                    section: section,
                    spineIndex: index,
                    characterInterval: characterInterval,
                    webViewProvider: webViewProvider
                )

                // Record boundary
                spineItemBoundaries.append(allLocations.count)
                allLocations.append(contentsOf: spineLocations)

                Self.logger.debug("LOCATIONS: Spine \(index) generated \(spineLocations.count) locations")
            }

            let locationsList = LocationsList(
                bookId: bookId,
                layoutKey: layoutKey,
                locations: allLocations,
                spineItemBoundaries: spineItemBoundaries,
                characterInterval: characterInterval
            )

            await self.setStatus(.complete(locationsList))

            Self.logger.info("LOCATIONS: Built \(allLocations.count) locations for \(htmlSections.count) spine items")

            return locationsList
        }

        buildTask = task
        return await task.value
    }

    private func setStatus(_ newStatus: Status) {
        status = newStatus
    }

    /// Generate location CFIs for a single spine item
    private func generateLocationsForSpine(
        section: HTMLSection,
        spineIndex: Int,
        characterInterval: Int,
        webViewProvider: @escaping @Sendable () async -> WKWebView?
    ) async -> [String] {
        // For now, generate a simple location at the start of each spine item
        // A full implementation would load the spine into a hidden WebView and
        // generate CFIs at character intervals using JavaScript

        let idref = section.spineItemId.isEmpty ? nil : section.spineItemId

        // Generate a base CFI for the spine item start
        let baseCFI = CFIParser.generateFullCFI(
            spineIndex: spineIndex,
            idref: idref,
            domPath: [0],
            charOffset: 0
        )

        // Estimate number of locations based on text content length
        let textLength = section.blocks.reduce(0) { $0 + $1.textContent.count }
        let estimatedLocations = max(1, textLength / characterInterval)

        // Generate evenly spaced locations
        var locations: [String] = []
        for i in 0..<estimatedLocations {
            let charOffset = i * characterInterval
            let cfi = CFIParser.generateFullCFI(
                spineIndex: spineIndex,
                idref: idref,
                domPath: [0],
                charOffset: charOffset
            )
            locations.append(cfi)
        }

        return locations
    }
}

// MARK: - JavaScript for Locations Generation

/// JavaScript code that can be injected into a WebView to generate location CFIs
public enum LocationsJavaScript {
    /// JavaScript function to generate locations at character intervals
    public static let generateLocationsFunction = """
    window.generateLocationsForSpine = function(charInterval) {
        var locations = [];
        var charCount = 0;
        var lastLocationChar = 0;

        // Walk all text nodes in document order
        function walkTextNodes(node) {
            if (node.nodeType === 3) { // Text node
                var text = node.textContent;
                var parent = node.parentElement;
                if (!parent) return;

                for (var i = 0; i < text.length; i++) {
                    charCount++;
                    if (charCount - lastLocationChar >= charInterval) {
                        // Generate a CFI for this position
                        var path = window.buildDOMPath(parent);
                        locations.push({
                            domPath: path,
                            charOffset: i
                        });
                        lastLocationChar = charCount;
                    }
                }
            } else if (node.nodeType === 1) { // Element node
                for (var j = 0; j < node.childNodes.length; j++) {
                    walkTextNodes(node.childNodes[j]);
                }
            }
        }

        walkTextNodes(document.body);

        // Always include at least the start
        if (locations.length === 0) {
            locations.push({
                domPath: [0],
                charOffset: 0
            });
        }

        return locations;
    };
    """
}
