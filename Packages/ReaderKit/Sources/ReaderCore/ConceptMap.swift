import Foundation

/// The type of an entity (can be inferred or LLM-labeled)
public enum EntityType: String, Codable {
    case person
    case place
    case organization
    case event
    case concept
    case object
    case unknown
}

/// A normalized entity in the concept map
public struct Entity: Codable, Identifiable, Equatable {
    /// Unique identifier
    public let id: String

    /// The canonical text of the entity
    public let text: String

    /// Entity type (nil if not yet labeled)
    public let type: EntityType?

    /// Chapter IDs where this entity appears (limited to top 24)
    public let chapterIds: [String]

    /// Total frequency across all chapters
    public let frequency: Int

    /// Evidence snippets (1-2 representative quotes)
    public let evidence: [String]

    /// Salience score (0-1)
    public let salience: Double

    public init(
        id: String,
        text: String,
        type: EntityType?,
        chapterIds: [String],
        frequency: Int,
        evidence: [String],
        salience: Double
    ) {
        self.id = id
        self.text = text
        self.type = type
        // Cap at 24 chapters per the plan spec
        self.chapterIds = Array(chapterIds.prefix(24))
        self.frequency = frequency
        self.evidence = evidence
        self.salience = salience
    }

    /// Creates from an EntityCandidate
    public static func from(candidate: EntityExtractor.EntityCandidate) -> Entity {
        // Extract evidence snippets from first few mentions
        let evidence = candidate.mentions.prefix(2).map { mention in
            mention.text
        }

        return Entity(
            id: candidate.id,
            text: candidate.text,
            type: nil,  // Type will be labeled by LLM later
            chapterIds: candidate.chapterIds,
            frequency: candidate.frequency,
            evidence: evidence,
            salience: candidate.salience
        )
    }
}

/// A theme cluster in the concept map
public struct Theme: Codable, Identifiable, Equatable {
    /// Unique identifier
    public let id: String

    /// Human-readable label
    public let label: String

    /// Representative keywords
    public let keywords: [String]

    /// Chapter IDs in this theme cluster
    public let chapterIds: [String]

    /// Average similarity score within the cluster
    public let cohesion: Double

    public init(
        id: String,
        label: String,
        keywords: [String],
        chapterIds: [String],
        cohesion: Double
    ) {
        self.id = id
        self.label = label
        self.keywords = keywords
        self.chapterIds = chapterIds
        self.cohesion = cohesion
    }
}

/// An event or significant occurrence in the book
public struct BookEvent: Codable, Identifiable, Equatable {
    /// Unique identifier
    public let id: String

    /// Human-readable label (nil if not LLM-labeled)
    public let label: String?

    /// Participating entity IDs
    public let participants: [String]

    /// Chapter IDs where this event occurs
    public let chapterIds: [String]

    /// Evidence pointers (chunk IDs or snippets)
    public let evidence: [String]

    public init(
        id: String,
        label: String?,
        participants: [String],
        chapterIds: [String],
        evidence: [String]
    ) {
        self.id = id
        self.label = label
        self.participants = participants
        self.chapterIds = chapterIds
        self.evidence = evidence
    }

    /// Generates a deterministic label from participants when no LLM label available
    public var displayLabel: String {
        if let label = label {
            return label
        }

        // Generate from participants: "Encounter: Achilles + Hector"
        if participants.count == 2 {
            return "Interaction: \(participants[0]) & \(participants[1])"
        } else if participants.count > 2 {
            return "Event: \(participants.prefix(2).joined(separator: ", ")) & others"
        } else if participants.count == 1 {
            return "Event: \(participants[0])"
        }

        return "Unknown Event"
    }
}

/// The complete concept map for a book
public struct ConceptMap: Codable, Equatable {
    /// The book this concept map belongs to
    public let bookId: String

    /// Extracted and normalized entities (≤500)
    public let entities: [Entity]

    /// Theme clusters (≤200)
    public let themes: [Theme]

    /// Detected events (≤500, optional)
    public let events: [BookEvent]

    /// When the concept map was built
    public let buildDate: Date

    /// Version of the concept map algorithm
    public let version: String

    /// Build statistics
    public let stats: BuildStats

    public struct BuildStats: Codable, Equatable {
        public let chapterCount: Int
        public let totalBlocks: Int
        public let processingTimeMs: Int
        public let embeddingsUsed: Bool

        public init(chapterCount: Int, totalBlocks: Int, processingTimeMs: Int, embeddingsUsed: Bool) {
            self.chapterCount = chapterCount
            self.totalBlocks = totalBlocks
            self.processingTimeMs = processingTimeMs
            self.embeddingsUsed = embeddingsUsed
        }
    }

    public init(
        bookId: String,
        entities: [Entity],
        themes: [Theme],
        events: [BookEvent],
        buildDate: Date = Date(),
        version: String = "1.0",
        stats: BuildStats
    ) {
        self.bookId = bookId
        // Enforce limits from plan spec
        self.entities = Array(entities.prefix(500))
        self.themes = Array(themes.prefix(200))
        self.events = Array(events.prefix(500))
        self.buildDate = buildDate
        self.version = version
        self.stats = stats
    }

    // MARK: - Lookup Methods

    /// Finds entities matching a query
    public func lookupEntities(query: String) -> [Entity] {
        let lowercaseQuery = query.lowercased()
        return entities.filter { entity in
            entity.text.lowercased().contains(lowercaseQuery)
        }.sorted { $0.salience > $1.salience }
    }

    /// Finds themes matching a query
    public func lookupThemes(query: String) -> [Theme] {
        let lowercaseQuery = query.lowercased()
        return themes.filter { theme in
            theme.label.lowercased().contains(lowercaseQuery) ||
            theme.keywords.contains { $0.lowercased().contains(lowercaseQuery) }
        }
    }

    /// Finds events matching a query
    public func lookupEvents(query: String) -> [BookEvent] {
        let lowercaseQuery = query.lowercased()
        return events.filter { event in
            event.displayLabel.lowercased().contains(lowercaseQuery) ||
            event.participants.contains { $0.lowercased().contains(lowercaseQuery) }
        }
    }

    /// Gets all chapter IDs relevant to a query
    public func getRelevantChapters(query: String) -> [String] {
        var chapters = Set<String>()

        for entity in lookupEntities(query: query) {
            chapters.formUnion(entity.chapterIds)
        }

        for theme in lookupThemes(query: query) {
            chapters.formUnion(theme.chapterIds)
        }

        for event in lookupEvents(query: query) {
            chapters.formUnion(event.chapterIds)
        }

        return Array(chapters)
    }

    /// Comprehensive lookup returning all matches
    public func lookup(query: String) -> LookupResult {
        LookupResult(
            entities: lookupEntities(query: query),
            themes: lookupThemes(query: query),
            events: lookupEvents(query: query)
        )
    }

    public struct LookupResult: Codable {
        public let entities: [Entity]
        public let themes: [Theme]
        public let events: [BookEvent]

        public var isEmpty: Bool {
            entities.isEmpty && themes.isEmpty && events.isEmpty
        }

        public var chapterIds: [String] {
            var chapters = Set<String>()
            entities.forEach { chapters.formUnion($0.chapterIds) }
            themes.forEach { chapters.formUnion($0.chapterIds) }
            events.forEach { chapters.formUnion($0.chapterIds) }
            return Array(chapters)
        }
    }
}
