import Foundation

// MARK: - Routing Decision Types

/// Route classification for a question
public enum RouteDecision: String, Codable {
    /// Question is about the book - use book tools
    case book = "BOOK"
    /// Question is not about the book - answer from general knowledge
    case notBook = "NOT_BOOK"
    /// Ambiguous - needs concept map lookup to decide
    case ambiguous = "AMBIGUOUS"
}

/// Result of routing a question
public struct RoutingResult: Codable {
    public let route: RouteDecision
    public let confidence: Double
    public let suggestedChapterIds: [String]
    public let suggestedQueries: [String]
    public let reasoning: String?

    public init(
        route: RouteDecision,
        confidence: Double,
        suggestedChapterIds: [String] = [],
        suggestedQueries: [String] = [],
        reasoning: String? = nil
    ) {
        self.route = route
        self.confidence = confidence
        self.suggestedChapterIds = suggestedChapterIds
        self.suggestedQueries = suggestedQueries
        self.reasoning = reasoning
    }
}

// MARK: - Book Chat Router

/// Routes questions to determine if they're about the book or general knowledge
public actor BookChatRouter {
    private static let logger = Log.logger(category: "BookChatRouter")

    public init() {}

    /// Route a question to determine handling strategy
    /// - Parameters:
    ///   - question: The user's question
    ///   - bookTitle: Title of the current book
    ///   - bookAuthor: Author of the current book (optional)
    ///   - conceptMap: The book's concept map (optional, for disambiguation)
    /// - Returns: Routing result with decision, confidence, and suggested scope
    public func route(
        question: String,
        bookTitle: String,
        bookAuthor: String?,
        conceptMap: ConceptMap?
    ) async -> RoutingResult {
        // Step 1: Apply heuristic rules for fast classification
        let heuristicResult = applyHeuristics(question: question, bookTitle: bookTitle, bookAuthor: bookAuthor)

        if heuristicResult.confidence >= 0.85 {
            Self.logger.debug("High-confidence heuristic: \(heuristicResult.route.rawValue)")
            return heuristicResult
        }

        // Step 2: For ambiguous cases, use concept map if available
        if let conceptMap = conceptMap, heuristicResult.route == .ambiguous || heuristicResult.confidence < 0.7 {
            let conceptMapResult = resolveWithConceptMap(question: question, conceptMap: conceptMap)

            if conceptMapResult.confidence > heuristicResult.confidence {
                Self.logger.debug("Concept map resolved to: \(conceptMapResult.route.rawValue)")
                return conceptMapResult
            }
        }

        return heuristicResult
    }

    // MARK: - Heuristic Classification

    private func applyHeuristics(
        question: String,
        bookTitle: String,
        bookAuthor: String?
    ) -> RoutingResult {
        let questionLower = question.lowercased()

        // Patterns that strongly indicate book questions
        let bookPatterns: [(pattern: String, weight: Double)] = [
            // Direct references to "the book"
            ("in the book", 0.95),
            ("in this book", 0.95),
            ("the book says", 0.95),
            ("according to the book", 0.95),
            ("from the book", 0.9),
            ("the author says", 0.9),
            ("the author writes", 0.9),

            // Chapter/plot references
            ("in chapter", 0.95),
            ("in this chapter", 0.95),
            ("what chapter", 0.9),
            ("which chapter", 0.9),
            ("the plot", 0.8),
            ("the story", 0.75),
            ("the narrative", 0.85),

            // Character/entity questions
            ("the protagonist", 0.9),
            ("the main character", 0.9),
            ("the antagonist", 0.9),
            ("who is [a-z]+\\?", 0.7), // "who is Victor?"
            ("what happens to", 0.8),
            ("why did [a-z]+ ", 0.75),
            ("how does [a-z]+ ", 0.7),

            // Quote/passage references
            ("this passage", 0.95),
            ("this quote", 0.95),
            ("this text", 0.9),
            ("the passage", 0.85),
            ("the quote", 0.85),
            ("what does this mean", 0.8),

            // Reading context
            ("what i'm reading", 0.9),
            ("reading about", 0.7),
            ("just read", 0.85),

            // Specific literary elements
            ("the theme of", 0.85),
            ("symbolism in", 0.85),
            ("the meaning of", 0.7),
            ("the significance of", 0.75)
        ]

        // Patterns that strongly indicate NOT book questions
        let notBookPatterns: [(pattern: String, weight: Double)] = [
            // Real-world facts
            ("in real life", 0.95),
            ("in reality", 0.9),
            ("historically", 0.85),
            ("in history", 0.85),
            ("wikipedia", 0.95),

            // General knowledge queries
            ("what is the capital of", 0.95),
            ("who was the president", 0.9),
            ("when did [a-z]+ happen", 0.85),
            ("how do you", 0.9),
            ("what is [a-z]+ in real", 0.95),

            // External references
            ("on the internet", 0.95),
            ("according to google", 0.95),
            ("look up", 0.8),
            ("search for", 0.75),

            // App/reader questions
            ("how do i use", 0.95),
            ("app settings", 0.95),
            ("reader settings", 0.95),

            // Current events
            ("today's news", 0.95),
            ("current events", 0.95),
            ("latest news", 0.95)
        ]

        // Check for book title or author mentions - strong book indicator
        let titleLower = bookTitle.lowercased()
        let titleWords = titleLower.split(separator: " ").filter { $0.count > 3 }.map { String($0) }
        if titleWords.contains(where: { questionLower.contains($0) }) {
            return RoutingResult(
                route: .book,
                confidence: 0.9,
                reasoning: "Question mentions book title"
            )
        }

        if let author = bookAuthor {
            let authorLower = author.lowercased()
            let authorWords = authorLower.split(separator: " ").filter { $0.count > 3 }.map { String($0) }
            if authorWords.contains(where: { questionLower.contains($0) }) {
                return RoutingResult(
                    route: .book,
                    confidence: 0.85,
                    reasoning: "Question mentions author name"
                )
            }
        }

        // Score against book patterns
        var bookScore = 0.0
        for (pattern, weight) in bookPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(question.startIndex..., in: question)
                if regex.firstMatch(in: question, options: [], range: range) != nil {
                    bookScore = max(bookScore, weight)
                }
            } else if questionLower.contains(pattern) {
                bookScore = max(bookScore, weight)
            }
        }

        // Score against not-book patterns
        var notBookScore = 0.0
        for (pattern, weight) in notBookPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(question.startIndex..., in: question)
                if regex.firstMatch(in: question, options: [], range: range) != nil {
                    notBookScore = max(notBookScore, weight)
                }
            } else if questionLower.contains(pattern) {
                notBookScore = max(notBookScore, weight)
            }
        }

        // Decide based on scores
        if bookScore >= 0.8 && bookScore > notBookScore {
            return RoutingResult(
                route: .book,
                confidence: bookScore,
                reasoning: "Strong book-related patterns detected"
            )
        }

        if notBookScore >= 0.8 && notBookScore > bookScore {
            return RoutingResult(
                route: .notBook,
                confidence: notBookScore,
                reasoning: "Strong general knowledge patterns detected"
            )
        }

        // Check for question word patterns
        let questionWords = ["who", "what", "where", "when", "why", "how"]
        let hasQuestionWord = questionWords.contains { questionLower.hasPrefix($0) }

        // Short questions about entities are often book-related when reading
        if hasQuestionWord && question.count < 50 {
            return RoutingResult(
                route: .ambiguous,
                confidence: 0.5,
                reasoning: "Short question - context needed"
            )
        }

        // Default to ambiguous for unclear cases
        return RoutingResult(
            route: .ambiguous,
            confidence: max(bookScore, notBookScore, 0.4),
            reasoning: "Unable to determine from question text alone"
        )
    }

    // MARK: - Concept Map Resolution

    private func resolveWithConceptMap(
        question: String,
        conceptMap: ConceptMap
    ) -> RoutingResult {
        // Look up the question in the concept map
        let lookupResult = conceptMap.lookup(query: question)

        // Strong hits indicate book question
        if !lookupResult.entities.isEmpty || !lookupResult.themes.isEmpty {
            let entityCount = lookupResult.entities.count
            let themeCount = lookupResult.themes.count
            let eventCount = lookupResult.events.count
            let totalHits = entityCount + themeCount + eventCount

            // Calculate confidence based on hit strength
            let topEntitySalience = lookupResult.entities.first?.salience ?? 0
            let confidence: Double

            if totalHits >= 3 || topEntitySalience >= 0.7 {
                confidence = 0.9
            } else if totalHits >= 2 || topEntitySalience >= 0.5 {
                confidence = 0.8
            } else if totalHits >= 1 {
                confidence = 0.7
            } else {
                confidence = 0.5
            }

            // Extract suggested chapter IDs from concept map hits
            var suggestedChapterIds = Set<String>()
            for entity in lookupResult.entities.prefix(3) {
                suggestedChapterIds.formUnion(entity.chapterIds.prefix(5))
            }
            for theme in lookupResult.themes.prefix(2) {
                suggestedChapterIds.formUnion(theme.chapterIds.prefix(5))
            }

            // Build suggested queries from entity names
            let suggestedQueries = lookupResult.entities.prefix(3).map { $0.text }

            return RoutingResult(
                route: .book,
                confidence: confidence,
                suggestedChapterIds: Array(suggestedChapterIds).sorted(),
                suggestedQueries: Array(suggestedQueries),
                reasoning: "Matched \(entityCount) entities, \(themeCount) themes in concept map"
            )
        }

        // No hits in concept map - likely not about the book
        return RoutingResult(
            route: .notBook,
            confidence: 0.65,
            reasoning: "No matches in book concept map"
        )
    }
}

// MARK: - Execution Guardrails

    /// Guardrails for tool execution in book chat
public struct ExecutionGuardrails {
    /// Maximum number of tool calls per question
    public static let maxToolCalls = 8

    /// Maximum scope escalations (chapter → book)
    public static let maxEscalations = 1

    /// Minimum evidence chunks required for book-specific answers
    public static let minEvidenceChunks = 1

    /// Tool call budget tracker
    public struct ToolBudget {
        public var remaining: Int
        public var escalationsUsed: Int
        public var evidenceChunksFound: Int

        public init() {
            self.remaining = ExecutionGuardrails.maxToolCalls
            self.escalationsUsed = 0
            self.evidenceChunksFound = 0
        }

        public mutating func useToolCall() -> Bool {
            guard remaining > 0 else { return false }
            remaining -= 1
            return true
        }

        public mutating func useEscalation() -> Bool {
            guard escalationsUsed < ExecutionGuardrails.maxEscalations else { return false }
            escalationsUsed += 1
            return true
        }

        public mutating func recordEvidence(count: Int) {
            evidenceChunksFound += count
        }

        public var hasEvidence: Bool {
            evidenceChunksFound >= ExecutionGuardrails.minEvidenceChunks
        }

        public var canMakeToolCall: Bool {
            remaining > 0
        }

        public var canEscalate: Bool {
            escalationsUsed < ExecutionGuardrails.maxEscalations
        }
    }
}
