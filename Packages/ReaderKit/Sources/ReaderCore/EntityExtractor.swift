import Foundation
import OSLog

/// Extracts entity candidates from book chapters using pattern-based detection
public struct EntityExtractor {
    private static let logger = Logger(subsystem: "com.splap.reader", category: "EntityExtractor")

    /// An entity candidate detected in the text
    public struct EntityCandidate: Codable, Equatable, Identifiable {
        /// Unique identifier for this entity
        public let id: String

        /// The canonical text of the entity (longest form found)
        public let text: String

        /// All variations of this entity found
        public let variations: [String]

        /// Mentions across chapters
        public let mentions: [EntityMention]

        /// Co-occurring entities (entity ID -> count)
        public let coOccurrences: [String: Int]

        /// Salience score (0-1, higher = more important)
        public let salience: Double

        /// Chapter IDs where this entity appears
        public var chapterIds: [String] {
            Array(Set(mentions.map(\.chapterId)))
        }

        /// Total frequency across all chapters
        public var frequency: Int {
            mentions.count
        }

        public init(
            id: String,
            text: String,
            variations: [String],
            mentions: [EntityMention],
            coOccurrences: [String: Int],
            salience: Double
        ) {
            self.id = id
            self.text = text
            self.variations = variations
            self.mentions = mentions
            self.coOccurrences = coOccurrences
            self.salience = salience
        }
    }

    /// A single mention of an entity in the text
    public struct EntityMention: Codable, Equatable {
        public let chapterId: String
        public let blockId: String
        public let offset: Int
        public let text: String

        public init(chapterId: String, blockId: String, offset: Int, text: String) {
            self.chapterId = chapterId
            self.blockId = blockId
            self.offset = offset
            self.text = text
        }
    }

    /// Configuration for entity extraction
    public struct Config {
        /// Minimum mentions to consider an entity
        public var minMentions: Int = 3

        /// Minimum chapters for high-salience entities
        public var minChapters: Int = 2

        /// Maximum entities to return
        public var maxEntities: Int = 500

        /// Co-occurrence window size in characters
        public var coOccurrenceWindow: Int = 500

        public init() {}
    }

    // MARK: - Public API

    /// Extracts entity candidates from chapters
    /// - Parameters:
    ///   - chapters: The chapters to analyze
    ///   - tfidfResult: Optional TF-IDF results for salience boosting
    ///   - config: Extraction configuration
    /// - Returns: Array of entity candidates sorted by salience
    public static func extract(
        chapters: [Chapter],
        tfidfResult: TFIDFAnalyzer.AnalysisResult? = nil,
        config: Config = Config()
    ) -> [EntityCandidate] {
        guard !chapters.isEmpty else { return [] }

        logger.info("Extracting entities from \(chapters.count) chapters")

        // Step 1: Find all capitalized spans
        var allMentions: [String: [EntityMention]] = [:]

        for chapter in chapters {
            for section in chapter.htmlSections {
                for block in section.blocks {
                    let spans = findCapitalizedSpans(in: block.textContent, blockId: block.id, chapterId: chapter.id)
                    for (text, mention) in spans {
                        allMentions[text.lowercased(), default: []].append(mention)
                    }
                }
            }
        }

        // Step 2: Merge variations (e.g., "Elizabeth" and "Elizabeth Bennet")
        let mergedEntities = mergeVariations(allMentions)

        // Step 3: Filter by minimum frequency
        let filteredEntities = mergedEntities.filter { $0.value.count >= config.minMentions }

        logger.debug("Found \(filteredEntities.count) entities after frequency filter")

        // Step 4: Build co-occurrence matrix
        let coOccurrences = buildCoOccurrenceMatrix(
            entities: filteredEntities,
            chapters: chapters,
            windowSize: config.coOccurrenceWindow
        )

        // Step 5: Compute salience and create candidates
        var candidates: [EntityCandidate] = []

        for (canonicalText, mentionGroups) in filteredEntities {
            let allMentions = mentionGroups.flatMap { $0.mentions }
            let chapterSet = Set(allMentions.map(\.chapterId))
            let variations = mentionGroups.map(\.text)

            // Compute salience
            let frequencyScore = min(1.0, Double(allMentions.count) / 50.0)
            let spreadScore = min(1.0, Double(chapterSet.count) / Double(max(1, chapters.count / 3)))

            // TF-IDF boost: check if entity terms are high-TF-IDF
            var tfidfBoost = 0.0
            if let tfidfResult = tfidfResult {
                let entityTerms = canonicalText.lowercased().split(separator: " ").map(String.init)
                for chapterId in chapterSet {
                    if let keywords = tfidfResult.keywordsByChapter[chapterId] {
                        for term in entityTerms {
                            if let keyword = keywords.first(where: { $0.term == term }) {
                                tfidfBoost += keyword.tfidf / 10.0  // Normalize
                            }
                        }
                    }
                }
                tfidfBoost = min(0.3, tfidfBoost / Double(max(1, chapterSet.count)))
            }

            let salience = (frequencyScore * 0.4 + spreadScore * 0.4 + tfidfBoost) * (chapterSet.count >= config.minChapters ? 1.0 : 0.5)

            let entityId = generateEntityId(text: canonicalText)
            let entityCoOccurrences = coOccurrences[entityId] ?? [:]

            candidates.append(EntityCandidate(
                id: entityId,
                text: canonicalText,
                variations: variations,
                mentions: allMentions,
                coOccurrences: entityCoOccurrences,
                salience: salience
            ))
        }

        // Sort by salience and limit
        candidates.sort { $0.salience > $1.salience }
        candidates = Array(candidates.prefix(config.maxEntities))

        logger.info("Extracted \(candidates.count) entity candidates")

        return candidates
    }

    // MARK: - Private Helpers

    /// Finds capitalized spans in text that might be entities
    private static func findCapitalizedSpans(
        in text: String,
        blockId: String,
        chapterId: String
    ) -> [(String, EntityMention)] {
        var results: [(String, EntityMention)] = []

        // Pattern: One or more capitalized words
        // Matches: "Elizabeth", "Elizabeth Bennet", "Mr. Darcy"
        let pattern = #"\b[A-Z][a-z]+(?:[\s'-]+[A-Z][a-z]+){0,3}\b"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        for match in matches {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            let matchText = String(text[swiftRange])
            let offset = text.distance(from: text.startIndex, to: swiftRange.lowerBound)

            // Skip if this looks like a sentence start
            if isSentenceStart(text: text, at: swiftRange.lowerBound) {
                // Only skip single words at sentence start
                if !matchText.contains(" ") {
                    continue
                }
            }

            // Skip common false positives
            if commonWords.contains(matchText.lowercased()) {
                continue
            }

            let mention = EntityMention(
                chapterId: chapterId,
                blockId: blockId,
                offset: offset,
                text: matchText
            )

            results.append((matchText, mention))
        }

        return results
    }

    /// Checks if a position is at the start of a sentence
    private static func isSentenceStart(text: String, at position: String.Index) -> Bool {
        guard position > text.startIndex else { return true }

        // Look back for sentence-ending punctuation
        var idx = text.index(before: position)

        // Skip whitespace
        while idx > text.startIndex && text[idx].isWhitespace {
            idx = text.index(before: idx)
        }

        // Check if previous character is sentence-ending
        let prevChar = text[idx]
        return prevChar == "." || prevChar == "!" || prevChar == "?" || prevChar == "\n"
    }

    /// Merges entity variations (e.g., "Elizabeth" with "Elizabeth Bennet")
    private static func mergeVariations(
        _ mentions: [String: [EntityMention]]
    ) -> [String: [(text: String, mentions: [EntityMention])]] {
        // Group by potential canonical form
        var groups: [String: [(text: String, mentions: [EntityMention])]] = [:]

        // Sort by length (longest first) so canonical forms are established first
        let sortedMentions = mentions.sorted { $0.key.count > $1.key.count }

        for (text, mentionList) in sortedMentions {
            let lowerText = text.lowercased()

            // Check if this is a variation of an existing entity
            var merged = false
            for (canonical, _) in groups {
                if lowerText.contains(canonical) || canonical.contains(lowerText) {
                    // Merge into existing group
                    groups[canonical, default: []].append((text: text, mentions: mentionList))
                    merged = true
                    break
                }
            }

            if !merged {
                // Create new group
                groups[lowerText] = [(text: text, mentions: mentionList)]
            }
        }

        // Select canonical form (longest version with most mentions)
        var result: [String: [(text: String, mentions: [EntityMention])]] = [:]

        for (_, variations) in groups {
            // Find the best canonical form
            let sorted = variations.sorted { a, b in
                // Prefer longer names
                if a.text.count != b.text.count {
                    return a.text.count > b.text.count
                }
                // Then prefer more mentions
                return a.mentions.count > b.mentions.count
            }

            if let canonical = sorted.first {
                result[canonical.text] = variations
            }
        }

        return result
    }

    /// Builds co-occurrence matrix between entities
    private static func buildCoOccurrenceMatrix(
        entities: [String: [(text: String, mentions: [EntityMention])]],
        chapters: [Chapter],
        windowSize: Int
    ) -> [String: [String: Int]] {
        var coOccurrences: [String: [String: Int]] = [:]

        // Build entity ID lookup
        let entityIds = Dictionary(uniqueKeysWithValues: entities.keys.map { (generateEntityId(text: $0), $0) })

        // For each chapter, find entities that co-occur within window
        for chapter in chapters {
            let fullText = chapter.htmlSections.flatMap { $0.blocks }.map(\.textContent).joined(separator: " ")

            // Find all entity positions in this chapter
            var entityPositions: [(entityId: String, position: Int)] = []

            for (canonicalText, variations) in entities {
                let entityId = generateEntityId(text: canonicalText)

                for variation in variations {
                    // Find all occurrences of this variation
                    var searchStart = fullText.startIndex
                    while let range = fullText.range(of: variation.text, range: searchStart..<fullText.endIndex) {
                        let position = fullText.distance(from: fullText.startIndex, to: range.lowerBound)
                        entityPositions.append((entityId: entityId, position: position))
                        searchStart = range.upperBound
                    }
                }
            }

            // Sort by position
            entityPositions.sort { $0.position < $1.position }

            // Count co-occurrences within window
            for i in 0..<entityPositions.count {
                let entity1 = entityPositions[i]

                for j in (i + 1)..<entityPositions.count {
                    let entity2 = entityPositions[j]

                    // Stop if outside window
                    if entity2.position - entity1.position > windowSize {
                        break
                    }

                    // Skip self-co-occurrence
                    if entity1.entityId == entity2.entityId {
                        continue
                    }

                    // Count bidirectional co-occurrence
                    coOccurrences[entity1.entityId, default: [:]][entity2.entityId, default: 0] += 1
                    coOccurrences[entity2.entityId, default: [:]][entity1.entityId, default: 0] += 1
                }
            }
        }

        return coOccurrences
    }

    /// Generates a stable entity ID from text
    private static func generateEntityId(text: String) -> String {
        let normalized = text.lowercased().replacingOccurrences(of: " ", with: "_")
        return "entity_\(normalized.prefix(50))"
    }

    /// Common words that look like proper nouns but aren't entities
    private static let commonWords: Set<String> = [
        "the", "a", "an", "this", "that", "these", "those",
        "i", "you", "he", "she", "it", "we", "they",
        "my", "your", "his", "her", "its", "our", "their",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december",
        "chapter", "part", "section", "book", "volume",
        "sir", "madam", "mr", "mrs", "ms", "miss", "dr", "prof",
        "yes", "no", "oh", "ah", "well", "now", "then",
        "here", "there", "where", "when", "why", "how", "what",
        "very", "much", "more", "most", "some", "any", "all",
        "first", "second", "third", "last", "next", "other",
    ]
}
