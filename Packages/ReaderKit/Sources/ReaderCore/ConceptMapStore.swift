import Foundation
import OSLog

/// Persistent storage for book concept maps
public actor ConceptMapStore {
    private static let logger = Logger(subsystem: "com.splap.reader", category: "ConceptMapStore")

    /// Shared instance
    public static let shared = ConceptMapStore()

    /// Directory for storing concept maps
    private let storeDirectory: URL

    /// In-memory cache of loaded concept maps
    private var cache: [String: ConceptMap] = [:]

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let readerDir = appSupport.appendingPathComponent("com.splap.reader", isDirectory: true)
        storeDirectory = readerDir.appendingPathComponent("concept_maps", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Saves a concept map for a book
    public func save(map: ConceptMap) throws {
        let path = conceptMapPath(for: map.bookId)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(map)
        try data.write(to: path)

        // Update cache
        cache[map.bookId] = map

        Self.logger.info("Saved concept map for book \(map.bookId) (\(data.count) bytes)")
    }

    /// Loads a concept map for a book
    public func load(bookId: String) throws -> ConceptMap? {
        // Check cache first
        if let cached = cache[bookId] {
            return cached
        }

        // Load from disk
        let path = conceptMapPath(for: bookId)

        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
        }

        let data = try Data(contentsOf: path)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let map = try decoder.decode(ConceptMap.self, from: data)

        // Update cache
        cache[bookId] = map

        Self.logger.debug("Loaded concept map for book \(bookId)")

        return map
    }

    /// Deletes the concept map for a book
    public func delete(bookId: String) throws {
        // Remove from cache
        cache.removeValue(forKey: bookId)

        // Remove file
        let path = conceptMapPath(for: bookId)
        try? FileManager.default.removeItem(at: path)

        Self.logger.info("Deleted concept map for book \(bookId)")
    }

    /// Checks if a concept map exists for a book
    public func exists(bookId: String) -> Bool {
        if cache[bookId] != nil { return true }

        let path = conceptMapPath(for: bookId)
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// Clears the in-memory cache
    public func clearCache() {
        cache.removeAll()
        Self.logger.info("Cleared concept map cache")
    }

    /// Lists all book IDs with concept maps
    public func listBookIds() -> [String] {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil)
            return files
                .filter { $0.pathExtension == "json" }
                .map { $0.deletingPathExtension().lastPathComponent }
        } catch {
            return []
        }
    }

    // MARK: - Private Helpers

    private func conceptMapPath(for bookId: String) -> URL {
        storeDirectory.appendingPathComponent("\(bookId).json")
    }
}

// MARK: - Concept Map Builder

/// Builds a concept map from book data
public enum ConceptMapBuilder {
    private static let logger = Logger(subsystem: "com.splap.reader", category: "ConceptMapBuilder")

    /// Builds a complete concept map for a book
    /// - Parameters:
    ///   - bookId: The book identifier
    ///   - chapters: The book chapters
    ///   - chunkEmbeddings: Optional chunk embeddings for semantic features
    /// - Returns: The built concept map
    public static func build(
        bookId: String,
        chapters: [Chapter],
        chunkEmbeddings: [String: [Float]]? = nil
    ) -> ConceptMap {
        let startTime = Date()

        logger.info("Building concept map for book \(bookId) with \(chapters.count) chapters")

        // Step 1: TF-IDF analysis
        let tfidfResult = TFIDFAnalyzer.analyze(chapters: chapters)

        // Step 2: Entity extraction
        let entityCandidates = EntityExtractor.extract(chapters: chapters, tfidfResult: tfidfResult)
        let entities = entityCandidates.map { Entity.from(candidate: $0) }

        // Step 3: Compute chapter embeddings (mean of chunk embeddings if available)
        var chapterCentroids: [String: [Float]]? = nil
        if let chunkEmbeddings, !chunkEmbeddings.isEmpty {
            chapterCentroids = computeChapterCentroids(chapters: chapters, chunkEmbeddings: chunkEmbeddings)
        }

        // Step 4: Theme clustering
        let themes = ThemeClusterer.cluster(
            chapters: chapters,
            tfidfResult: tfidfResult,
            chapterEmbeddings: chapterCentroids
        )

        // Step 5: Event detection (from entity co-occurrences)
        let events = detectEvents(entities: entities, entityCandidates: entityCandidates)

        // Compute stats
        let totalBlocks = chapters.flatMap { $0.htmlSections.flatMap(\.blocks) }.count
        let processingTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)

        let stats = ConceptMap.BuildStats(
            chapterCount: chapters.count,
            totalBlocks: totalBlocks,
            processingTimeMs: processingTimeMs,
            embeddingsUsed: chapterCentroids != nil
        )

        logger.info("Concept map built: \(entities.count) entities, \(themes.count) themes, \(events.count) events in \(processingTimeMs)ms")

        return ConceptMap(
            bookId: bookId,
            entities: entities,
            themes: themes,
            events: events,
            stats: stats
        )
    }

    /// Computes chapter centroids from chunk embeddings
    private static func computeChapterCentroids(
        chapters: [Chapter],
        chunkEmbeddings: [String: [Float]]
    ) -> [String: [Float]] {
        var centroids: [String: [Float]] = [:]

        for chapter in chapters {
            var chapterEmbeddings: [[Float]] = []

            // Collect embeddings for chunks in this chapter
            // Note: This assumes chunk IDs follow a pattern including chapter ID
            for (chunkId, embedding) in chunkEmbeddings {
                if chunkId.contains(chapter.id) {
                    chapterEmbeddings.append(embedding)
                }
            }

            // Compute mean
            if !chapterEmbeddings.isEmpty {
                let dim = chapterEmbeddings[0].count
                var centroid = [Float](repeating: 0, count: dim)

                for embedding in chapterEmbeddings {
                    for i in 0 ..< dim {
                        centroid[i] += embedding[i]
                    }
                }

                let count = Float(chapterEmbeddings.count)
                for i in 0 ..< dim {
                    centroid[i] /= count
                }

                // L2 normalize
                let norm = sqrt(centroid.reduce(0) { $0 + $1 * $1 })
                if norm > 0 {
                    for i in 0 ..< dim {
                        centroid[i] /= norm
                    }
                }

                centroids[chapter.id] = centroid
            }
        }

        return centroids
    }

    /// Detects events from entity co-occurrences
    private static func detectEvents(
        entities: [Entity],
        entityCandidates: [EntityExtractor.EntityCandidate]
    ) -> [BookEvent] {
        var events: [BookEvent] = []

        // Build entity ID to text lookup
        let entityTexts = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0.text) })

        // Find significant co-occurrences
        for candidate in entityCandidates {
            // Get top co-occurring entities
            let topCoOccurrences = candidate.coOccurrences
                .sorted { $0.value > $1.value }
                .prefix(3)

            for (otherEntityId, count) in topCoOccurrences where count >= 3 {
                // Check if we already have this event (in either direction)
                let eventId = [candidate.id, otherEntityId].sorted().joined(separator: "_")

                if events.contains(where: { $0.id == eventId }) {
                    continue
                }

                // Find common chapters
                let thisChapters = Set(candidate.chapterIds)
                let otherCandidate = entityCandidates.first { $0.id == otherEntityId }
                let otherChapters = Set(otherCandidate?.chapterIds ?? [])
                let commonChapters = Array(thisChapters.intersection(otherChapters))

                if commonChapters.isEmpty {
                    continue
                }

                // Create event
                let participants = [
                    entityTexts[candidate.id] ?? candidate.text,
                    entityTexts[otherEntityId] ?? otherEntityId,
                ]

                events.append(BookEvent(
                    id: eventId,
                    label: nil, // Will be labeled by LLM later
                    participants: participants,
                    chapterIds: commonChapters,
                    evidence: []
                ))
            }
        }

        // Sort by number of chapters (more significant events first)
        events.sort { $0.chapterIds.count > $1.chapterIds.count }

        return events
    }
}
