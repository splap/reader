import Foundation

// MARK: - Chapter Summary Types

/// A cached chapter summary
public struct ChapterSummary: Codable, Identifiable {
    public let id: String
    public let bookId: String
    public let chapterId: String
    public let chapterTitle: String?
    public let summary: String
    public let keyPoints: [String]
    public let charactersMentioned: [String]
    public let generatedAt: Date
    public let tokenCount: Int

    public init(
        id: String = UUID().uuidString,
        bookId: String,
        chapterId: String,
        chapterTitle: String?,
        summary: String,
        keyPoints: [String],
        charactersMentioned: [String],
        generatedAt: Date = Date(),
        tokenCount: Int
    ) {
        self.id = id
        self.bookId = bookId
        self.chapterId = chapterId
        self.chapterTitle = chapterTitle
        self.summary = summary
        self.keyPoints = keyPoints
        self.charactersMentioned = charactersMentioned
        self.generatedAt = generatedAt
        self.tokenCount = tokenCount
    }
}

// MARK: - Chapter Summary Store

/// Persistent storage for chapter summaries
public actor ChapterSummaryStore {
    private static let logger = Log.logger(category: "ChapterSummaryStore")

    public static let shared = ChapterSummaryStore()

    private let storeDirectory: URL
    private var cache: [String: ChapterSummary] = [:]

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let readerDir = appSupport.appendingPathComponent("com.splap.reader", isDirectory: true)
        self.storeDirectory = readerDir.appendingPathComponent("chapter_summaries", isDirectory: true)

        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Gets a chapter summary, returning nil if not cached
    public func get(bookId: String, chapterId: String) -> ChapterSummary? {
        let cacheKey = "\(bookId)_\(chapterId)"

        if let cached = cache[cacheKey] {
            return cached
        }

        // Try loading from disk
        let path = summaryPath(bookId: bookId, chapterId: chapterId)
        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: path)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let summary = try decoder.decode(ChapterSummary.self, from: data)
            cache[cacheKey] = summary
            return summary
        } catch {
            Self.logger.error("Failed to load chapter summary: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Saves a chapter summary
    public func save(_ summary: ChapterSummary) throws {
        let cacheKey = "\(summary.bookId)_\(summary.chapterId)"
        cache[cacheKey] = summary

        // Ensure book directory exists
        let bookDir = storeDirectory.appendingPathComponent(summary.bookId, isDirectory: true)
        try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)

        let path = summaryPath(bookId: summary.bookId, chapterId: summary.chapterId)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]

        let data = try encoder.encode(summary)
        try data.write(to: path)

        Self.logger.debug("Saved summary for chapter \(summary.chapterId, privacy: .public)")
    }

    /// Checks if a summary exists for a chapter
    public func exists(bookId: String, chapterId: String) -> Bool {
        let cacheKey = "\(bookId)_\(chapterId)"
        if cache[cacheKey] != nil { return true }

        let path = summaryPath(bookId: bookId, chapterId: chapterId)
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// Deletes all summaries for a book
    public func deleteBook(bookId: String) throws {
        // Clear cache entries for this book
        cache = cache.filter { !$0.key.hasPrefix("\(bookId)_") }

        // Delete the book's directory
        let bookDir = storeDirectory.appendingPathComponent(bookId, isDirectory: true)
        try? FileManager.default.removeItem(at: bookDir)

        Self.logger.info("Deleted summaries for book \(bookId, privacy: .public)")
    }

    /// Lists all chapter IDs with summaries for a book
    public func listChapterIds(bookId: String) -> [String] {
        let bookDir = storeDirectory.appendingPathComponent(bookId, isDirectory: true)
        do {
            let files = try FileManager.default.contentsOfDirectory(at: bookDir, includingPropertiesForKeys: nil)
            return files
                .filter { $0.pathExtension == "json" }
                .map { $0.deletingPathExtension().lastPathComponent }
        } catch {
            return []
        }
    }

    private func summaryPath(bookId: String, chapterId: String) -> URL {
        storeDirectory
            .appendingPathComponent(bookId, isDirectory: true)
            .appendingPathComponent("\(chapterId).json")
    }
}

// MARK: - Chapter Summary Service

/// Service for generating and caching chapter summaries lazily
public actor ChapterSummaryService {
    private static let logger = Log.logger(category: "ChapterSummaryService")

    /// Maximum tokens for map-reduce chunking
    private let maxChunkTokens = 4000

    /// Shared instance
    public static let shared = ChapterSummaryService()

    private init() {}

    // MARK: - Public API

    /// Gets a chapter summary, generating if needed
    /// - Parameters:
    ///   - bookId: The book identifier
    ///   - chapterId: The chapter/spine item identifier
    ///   - chapterTitle: The chapter title (for display)
    ///   - chapterText: The full text of the chapter
    /// - Returns: The chapter summary
    public func getSummary(
        bookId: String,
        chapterId: String,
        chapterTitle: String?,
        chapterText: String
    ) async throws -> ChapterSummary {
        // Check cache first
        if let cached = await ChapterSummaryStore.shared.get(bookId: bookId, chapterId: chapterId) {
            Self.logger.debug("Cache hit for chapter \(chapterId, privacy: .public)")
            return cached
        }

        Self.logger.info("Generating summary for chapter \(chapterId, privacy: .public)")

        // Generate summary using map-reduce for long chapters
        let summary = try await generateSummary(
            bookId: bookId,
            chapterId: chapterId,
            chapterTitle: chapterTitle,
            chapterText: chapterText
        )

        // Cache the result
        try await ChapterSummaryStore.shared.save(summary)

        return summary
    }

    /// Checks if a summary is already cached
    public func hasCachedSummary(bookId: String, chapterId: String) async -> Bool {
        await ChapterSummaryStore.shared.exists(bookId: bookId, chapterId: chapterId)
    }

    // MARK: - Summary Generation

    private func generateSummary(
        bookId: String,
        chapterId: String,
        chapterTitle: String?,
        chapterText: String
    ) async throws -> ChapterSummary {
        let tokenCount = estimateTokens(chapterText)

        // For short chapters, summarize directly
        if tokenCount <= maxChunkTokens {
            return try await summarizeDirect(
                bookId: bookId,
                chapterId: chapterId,
                chapterTitle: chapterTitle,
                text: chapterText,
                tokenCount: tokenCount
            )
        }

        // For long chapters, use map-reduce
        return try await summarizeMapReduce(
            bookId: bookId,
            chapterId: chapterId,
            chapterTitle: chapterTitle,
            text: chapterText,
            tokenCount: tokenCount
        )
    }

    private func summarizeDirect(
        bookId: String,
        chapterId: String,
        chapterTitle: String?,
        text: String,
        tokenCount: Int
    ) async throws -> ChapterSummary {
        guard let apiKey = OpenRouterConfig.apiKey, !apiKey.isEmpty else {
            throw OpenRouterError.missingAPIKey
        }

        let prompt = buildSummaryPrompt(text: text, chapterTitle: chapterTitle)
        let response = try await callLLM(prompt: prompt, apiKey: apiKey)

        return parseSummaryResponse(
            response: response,
            bookId: bookId,
            chapterId: chapterId,
            chapterTitle: chapterTitle,
            tokenCount: tokenCount
        )
    }

    private func summarizeMapReduce(
        bookId: String,
        chapterId: String,
        chapterTitle: String?,
        text: String,
        tokenCount: Int
    ) async throws -> ChapterSummary {
        guard let apiKey = OpenRouterConfig.apiKey, !apiKey.isEmpty else {
            throw OpenRouterError.missingAPIKey
        }

        Self.logger.debug("Using map-reduce for \(tokenCount, privacy: .public) tokens")

        // Split into chunks
        let chunks = splitIntoChunks(text: text, maxTokens: maxChunkTokens)

        // Map: Summarize each chunk
        var chunkSummaries: [String] = []
        for (index, chunk) in chunks.enumerated() {
            Self.logger.debug("Summarizing chunk \(index + 1, privacy: .public)/\(chunks.count, privacy: .public)")

            let chunkPrompt = """
            Summarize this section of a chapter. Focus on:
            - Key events and plot points
            - Character actions and developments
            - Important themes or ideas

            Section \(index + 1) of \(chunks.count):
            \(chunk)

            Provide a concise summary (2-3 paragraphs).
            """

            let summary = try await callLLM(prompt: chunkPrompt, apiKey: apiKey)
            chunkSummaries.append(summary)
        }

        // Reduce: Combine chunk summaries
        let combinedSummaries = chunkSummaries.joined(separator: "\n\n---\n\n")
        let reducePrompt = """
        These are summaries of different sections of \(chapterTitle ?? "a chapter").
        Combine them into a single cohesive chapter summary.

        Section summaries:
        \(combinedSummaries)

        Provide:
        1. A unified summary (2-3 paragraphs)
        2. 3-5 key points as bullet points
        3. List of characters mentioned

        Format your response as:
        SUMMARY:
        [your summary]

        KEY_POINTS:
        - [point 1]
        - [point 2]
        ...

        CHARACTERS:
        [character 1], [character 2], ...
        """

        let response = try await callLLM(prompt: reducePrompt, apiKey: apiKey)

        return parseSummaryResponse(
            response: response,
            bookId: bookId,
            chapterId: chapterId,
            chapterTitle: chapterTitle,
            tokenCount: tokenCount
        )
    }

    // MARK: - Helpers

    private func buildSummaryPrompt(text: String, chapterTitle: String?) -> String {
        let titlePart = chapterTitle.map { " titled \"\($0)\"" } ?? ""

        return """
        Summarize this chapter\(titlePart) from a book. Focus on:
        - Key events and plot points
        - Character actions and developments
        - Important themes or ideas

        Chapter text:
        \(text)

        Provide:
        1. A summary (2-3 paragraphs)
        2. 3-5 key points as bullet points
        3. List of characters mentioned

        Format your response as:
        SUMMARY:
        [your summary]

        KEY_POINTS:
        - [point 1]
        - [point 2]
        ...

        CHARACTERS:
        [character 1], [character 2], ...
        """
    }

    private func parseSummaryResponse(
        response: String,
        bookId: String,
        chapterId: String,
        chapterTitle: String?,
        tokenCount: Int
    ) -> ChapterSummary {
        var summary = ""
        var keyPoints: [String] = []
        var characters: [String] = []

        // Parse structured response
        let lines = response.components(separatedBy: .newlines)
        var currentSection = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.uppercased().hasPrefix("SUMMARY:") {
                currentSection = "summary"
                let afterPrefix = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                if !afterPrefix.isEmpty {
                    summary = afterPrefix
                }
            } else if trimmed.uppercased().hasPrefix("KEY_POINTS:") || trimmed.uppercased().hasPrefix("KEY POINTS:") {
                currentSection = "keypoints"
            } else if trimmed.uppercased().hasPrefix("CHARACTERS:") {
                currentSection = "characters"
                let afterPrefix = String(trimmed.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                if !afterPrefix.isEmpty {
                    characters = afterPrefix
                        .components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            } else if currentSection == "summary" && !trimmed.isEmpty {
                if summary.isEmpty {
                    summary = trimmed
                } else {
                    summary += " " + trimmed
                }
            } else if currentSection == "keypoints" && trimmed.hasPrefix("-") {
                let point = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !point.isEmpty {
                    keyPoints.append(point)
                }
            }
        }

        // Fallback if parsing failed
        if summary.isEmpty {
            summary = response
        }

        return ChapterSummary(
            bookId: bookId,
            chapterId: chapterId,
            chapterTitle: chapterTitle,
            summary: summary,
            keyPoints: keyPoints,
            charactersMentioned: characters,
            tokenCount: tokenCount
        )
    }

    private func splitIntoChunks(text: String, maxTokens: Int) -> [String] {
        // Split by paragraphs first
        let paragraphs = text.components(separatedBy: "\n\n")
        var chunks: [String] = []
        var currentChunk = ""
        var currentTokens = 0

        for paragraph in paragraphs {
            let paragraphTokens = estimateTokens(paragraph)

            if currentTokens + paragraphTokens > maxTokens && !currentChunk.isEmpty {
                chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
                currentChunk = paragraph
                currentTokens = paragraphTokens
            } else {
                if !currentChunk.isEmpty {
                    currentChunk += "\n\n"
                }
                currentChunk += paragraph
                currentTokens += paragraphTokens
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return chunks
    }

    private func estimateTokens(_ text: String) -> Int {
        // Rough estimate: ~4 characters per token
        return text.count / 4
    }

    private func callLLM(prompt: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": OpenRouterConfig.model,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenRouterError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenRouterError.invalidResponse
        }

        return content
    }
}
