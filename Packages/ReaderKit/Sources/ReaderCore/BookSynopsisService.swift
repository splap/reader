import Foundation

// MARK: - Book Synopsis Types

/// A cached book synopsis
public struct BookSynopsis: Codable, Identifiable {
    public let id: String
    public let bookId: String
    public let bookTitle: String
    public let bookAuthor: String?
    public let synopsis: String
    public let mainCharacters: [CharacterSummary]
    public let mainThemes: [String]
    public let chapterCount: Int
    public let generatedAt: Date

    public struct CharacterSummary: Codable {
        public let name: String
        public let description: String

        public init(name: String, description: String) {
            self.name = name
            self.description = description
        }
    }

    public init(
        id: String = UUID().uuidString,
        bookId: String,
        bookTitle: String,
        bookAuthor: String?,
        synopsis: String,
        mainCharacters: [CharacterSummary],
        mainThemes: [String],
        chapterCount: Int,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.synopsis = synopsis
        self.mainCharacters = mainCharacters
        self.mainThemes = mainThemes
        self.chapterCount = chapterCount
        self.generatedAt = generatedAt
    }
}

// MARK: - Book Synopsis Store

/// Persistent storage for book synopses
public actor BookSynopsisStore {
    private static let logger = Log.logger(category: "BookSynopsisStore")

    public static let shared = BookSynopsisStore()

    private let storeDirectory: URL
    private var cache: [String: BookSynopsis] = [:]

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let readerDir = appSupport.appendingPathComponent("com.splap.reader", isDirectory: true)
        storeDirectory = readerDir.appendingPathComponent("book_synopses", isDirectory: true)

        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Gets a book synopsis, returning nil if not cached
    public func get(bookId: String) -> BookSynopsis? {
        if let cached = cache[bookId] {
            return cached
        }

        let path = synopsisPath(bookId: bookId)
        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: path)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let synopsis = try decoder.decode(BookSynopsis.self, from: data)
            cache[bookId] = synopsis
            return synopsis
        } catch {
            Self.logger.error("Failed to load book synopsis: \(error.localizedDescription)")
            return nil
        }
    }

    /// Saves a book synopsis
    public func save(_ synopsis: BookSynopsis) throws {
        cache[synopsis.bookId] = synopsis

        let path = synopsisPath(bookId: synopsis.bookId)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]

        let data = try encoder.encode(synopsis)
        try data.write(to: path)

        Self.logger.debug("Saved synopsis for book \(synopsis.bookId)")
    }

    /// Checks if a synopsis exists for a book
    public func exists(bookId: String) -> Bool {
        if cache[bookId] != nil { return true }

        let path = synopsisPath(bookId: bookId)
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// Deletes a book's synopsis
    public func delete(bookId: String) throws {
        cache.removeValue(forKey: bookId)

        let path = synopsisPath(bookId: bookId)
        try? FileManager.default.removeItem(at: path)

        Self.logger.info("Deleted synopsis for book \(bookId)")
    }

    private func synopsisPath(bookId: String) -> URL {
        storeDirectory.appendingPathComponent("\(bookId).json")
    }
}

// MARK: - Book Synopsis Service

/// Service for generating and caching book synopses
public actor BookSynopsisService {
    private static let logger = Log.logger(category: "BookSynopsisService")

    public static let shared = BookSynopsisService()

    private init() {}

    // MARK: - Public API

    /// Gets a book synopsis, generating if needed
    /// - Parameters:
    ///   - bookId: The book identifier
    ///   - bookTitle: The book title
    ///   - bookAuthor: The book author (optional)
    ///   - chapters: The book chapters for generating summaries
    ///   - conceptMap: The book's concept map (optional, used for entity info)
    /// - Returns: The book synopsis
    public func getSynopsis(
        bookId: String,
        bookTitle: String,
        bookAuthor: String?,
        chapters: [SectionInfo],
        conceptMap: ConceptMap?
    ) async throws -> BookSynopsis {
        // Check cache first
        if let cached = await BookSynopsisStore.shared.get(bookId: bookId) {
            Self.logger.debug("Cache hit for book synopsis \(bookId)")
            return cached
        }

        Self.logger.info("Generating synopsis for book \(bookId)")

        // Generate synopsis
        let synopsis = try await generateSynopsis(
            bookId: bookId,
            bookTitle: bookTitle,
            bookAuthor: bookAuthor,
            chapters: chapters,
            conceptMap: conceptMap
        )

        // Cache the result
        try await BookSynopsisStore.shared.save(synopsis)

        return synopsis
    }

    /// Checks if a synopsis is already cached
    public func hasCachedSynopsis(bookId: String) async -> Bool {
        await BookSynopsisStore.shared.exists(bookId: bookId)
    }

    // MARK: - Synopsis Generation

    private func generateSynopsis(
        bookId: String,
        bookTitle: String,
        bookAuthor: String?,
        chapters: [SectionInfo],
        conceptMap: ConceptMap?
    ) async throws -> BookSynopsis {
        guard let apiKey = OpenRouterConfig.apiKey, !apiKey.isEmpty else {
            throw OpenRouterError.missingAPIKey
        }

        // Gather chapter summaries if available
        var chapterSummaryTexts: [String] = []
        for chapter in chapters {
            if let summary = await ChapterSummaryStore.shared.get(bookId: bookId, chapterId: chapter.spineItemId) {
                let title = chapter.title ?? "Chapter"
                chapterSummaryTexts.append("**\(title)**: \(summary.summary)")
            }
        }

        // Build the synopsis prompt
        let prompt: String = if !chapterSummaryTexts.isEmpty {
            // Use chapter summaries for synthesis
            buildSynopsisFromSummariesPrompt(
                bookTitle: bookTitle,
                bookAuthor: bookAuthor,
                chapterSummaries: chapterSummaryTexts,
                conceptMap: conceptMap
            )
        } else if let conceptMap {
            // Use concept map entities/themes
            buildSynopsisFromConceptMapPrompt(
                bookTitle: bookTitle,
                bookAuthor: bookAuthor,
                conceptMap: conceptMap
            )
        } else {
            // Fallback: basic prompt
            buildBasicSynopsisPrompt(
                bookTitle: bookTitle,
                bookAuthor: bookAuthor,
                chapterCount: chapters.count
            )
        }

        let response = try await callLLM(prompt: prompt, apiKey: apiKey)

        return parseSynopsisResponse(
            response: response,
            bookId: bookId,
            bookTitle: bookTitle,
            bookAuthor: bookAuthor,
            chapterCount: chapters.count
        )
    }

    private func buildSynopsisFromSummariesPrompt(
        bookTitle: String,
        bookAuthor: String?,
        chapterSummaries: [String],
        conceptMap: ConceptMap?
    ) -> String {
        var prompt = """
        Based on these chapter summaries, create a comprehensive synopsis for "\(bookTitle)"
        """

        if let author = bookAuthor {
            prompt += " by \(author)"
        }

        prompt += """
        .

        Chapter summaries:
        \(chapterSummaries.joined(separator: "\n\n"))

        """

        if let conceptMap {
            let topEntities = conceptMap.entities.prefix(10).map(\.text)
            let topThemes = conceptMap.themes.prefix(5).map(\.label)

            if !topEntities.isEmpty {
                prompt += "\nKey entities in the book: \(topEntities.joined(separator: ", "))"
            }
            if !topThemes.isEmpty {
                prompt += "\nKey themes: \(topThemes.joined(separator: ", "))"
            }
        }

        prompt += """


        Provide:
        1. A synopsis of the entire book (3-4 paragraphs)
        2. Main characters with brief descriptions
        3. Main themes

        Format your response as:
        SYNOPSIS:
        [your synopsis]

        CHARACTERS:
        - [Name]: [description]
        - [Name]: [description]
        ...

        THEMES:
        - [theme 1]
        - [theme 2]
        ...
        """

        return prompt
    }

    private func buildSynopsisFromConceptMapPrompt(
        bookTitle: String,
        bookAuthor: String?,
        conceptMap: ConceptMap
    ) -> String {
        let topEntities = conceptMap.entities.prefix(15)
        let topThemes = conceptMap.themes.prefix(8)

        var prompt = """
        Create a synopsis for "\(bookTitle)"
        """

        if let author = bookAuthor {
            prompt += " by \(author)"
        }

        prompt += """
        .

        Key entities in the book:
        """

        for entity in topEntities {
            let typeStr = entity.type?.rawValue ?? "entity"
            prompt += "\n- \(entity.text) (\(typeStr), salience: \(String(format: "%.2f", entity.salience)))"
        }

        prompt += "\n\nThemes identified:\n"

        for theme in topThemes {
            prompt += "- \(theme.label) (keywords: \(theme.keywords.prefix(3).joined(separator: ", ")))\n"
        }

        prompt += """

        Based on these entities and themes, provide:
        1. A likely synopsis of the book (2-3 paragraphs)
        2. Main characters with brief descriptions
        3. Main themes explained

        Format your response as:
        SYNOPSIS:
        [your synopsis]

        CHARACTERS:
        - [Name]: [description]
        - [Name]: [description]
        ...

        THEMES:
        - [theme 1]
        - [theme 2]
        ...
        """

        return prompt
    }

    private func buildBasicSynopsisPrompt(
        bookTitle: String,
        bookAuthor: String?,
        chapterCount: Int
    ) -> String {
        var prompt = """
        Provide a synopsis for "\(bookTitle)"
        """

        if let author = bookAuthor {
            prompt += " by \(author)"
        }

        prompt += """
        .

        The book has \(chapterCount) chapters.

        Provide:
        1. A synopsis of the book (2-3 paragraphs)
        2. Main characters with brief descriptions (if known)
        3. Main themes (if known)

        Format your response as:
        SYNOPSIS:
        [your synopsis]

        CHARACTERS:
        - [Name]: [description]
        ...

        THEMES:
        - [theme 1]
        ...

        If you're not familiar with this book, say so and provide what you can.
        """

        return prompt
    }

    private func parseSynopsisResponse(
        response: String,
        bookId: String,
        bookTitle: String,
        bookAuthor: String?,
        chapterCount: Int
    ) -> BookSynopsis {
        var synopsis = ""
        var characters: [BookSynopsis.CharacterSummary] = []
        var themes: [String] = []

        let lines = response.components(separatedBy: .newlines)
        var currentSection = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.uppercased().hasPrefix("SYNOPSIS:") {
                currentSection = "synopsis"
                let afterPrefix = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                if !afterPrefix.isEmpty {
                    synopsis = afterPrefix
                }
            } else if trimmed.uppercased().hasPrefix("CHARACTERS:") {
                currentSection = "characters"
            } else if trimmed.uppercased().hasPrefix("THEMES:") {
                currentSection = "themes"
            } else if currentSection == "synopsis", !trimmed.isEmpty {
                if synopsis.isEmpty {
                    synopsis = trimmed
                } else {
                    synopsis += " " + trimmed
                }
            } else if currentSection == "characters", trimmed.hasPrefix("-") {
                let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if let colonIndex = content.firstIndex(of: ":") {
                    let name = String(content[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                    let description = String(content[content.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty, !description.isEmpty {
                        characters.append(BookSynopsis.CharacterSummary(name: name, description: description))
                    }
                }
            } else if currentSection == "themes", trimmed.hasPrefix("-") {
                let theme = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !theme.isEmpty {
                    themes.append(theme)
                }
            }
        }

        // Fallback if parsing failed
        if synopsis.isEmpty {
            synopsis = response
        }

        return BookSynopsis(
            bookId: bookId,
            bookTitle: bookTitle,
            bookAuthor: bookAuthor,
            synopsis: synopsis,
            mainCharacters: characters,
            mainThemes: themes,
            chapterCount: chapterCount
        )
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
                ["role": "user", "content": prompt],
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenRouterError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw OpenRouterError.invalidResponse
        }

        return content
    }
}
