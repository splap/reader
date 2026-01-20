import Foundation

// MARK: - Tool Registry

/// All available tools for the reader agent
public enum AgentTools {
    /// All tool definitions for the API request
    public static var allTools: [ToolDefinition] {
        return [
            getCurrentPositionTool,
            lexicalSearchTool,
            semanticSearchTool,
            conceptMapLookupTool,
            getSurroundingContextTool,
            getBookStructureTool,
            getChapterSummaryTool,
            getChapterFullTextTool,
            getBookSynopsisTool,
            wikipediaLookupTool,
            showMapTool,
            renderImageTool
        ]
    }

    // MARK: - Tool Definitions

    /// Get the reader's current position in the book
    static let getCurrentPositionTool = ToolDefinition(
        function: FunctionDefinition(
            name: "get_current_position",
            description: """
                Get the reader's current position: chapter name, progress percentage, and block location.
                Use this to understand where the reader is in the book before answering context-dependent questions.
                """,
            parameters: JSONSchema(
                properties: [:],
                required: []
            )
        )
    )

    /// Lexical search for exact word/phrase matches
    static let lexicalSearchTool = ToolDefinition(
        function: FunctionDefinition(
            name: "lexical_search",
            description: """
                Search for exact word or phrase matches in the book text. Uses full-text indexing with BM25 ranking.
                Use this for:
                - Finding specific names, terms, or phrases
                - Locating exact quotes
                - Counting occurrences of a word
                Does NOT find conceptual matches — use semantic_search for that.
                Returns: matching passages with surrounding context.
                """,
            parameters: JSONSchema(
                properties: [
                    "query": PropertySchema(
                        type: "string",
                        description: "The exact word or phrase to search for"
                    ),
                    "scope": PropertySchema(
                        type: "string",
                        description: "Where to search: 'current_chapter' or 'full_book'",
                        enumValues: ["current_chapter", "full_book"]
                    )
                ],
                required: ["query"]
            )
        )
    )

    /// Semantic search for conceptually similar passages
    static let semanticSearchTool = ToolDefinition(
        function: FunctionDefinition(
            name: "semantic_search",
            description: """
                Search for passages by meaning, even without exact word matches. Uses vector embeddings to find conceptually similar text.
                Use this for:
                - Abstract questions ("passages about betrayal")
                - Thematic queries ("where does the book discuss mortality?")
                - When lexical_search returns no results but the concept should exist
                Returns: passages ranked by semantic similarity with relevance scores.
                """,
            parameters: JSONSchema(
                properties: [
                    "query": PropertySchema(
                        type: "string",
                        description: "The concept, theme, or idea to search for"
                    ),
                    "scope": PropertySchema(
                        type: "string",
                        description: "Where to search: 'current_chapter', 'chapters' (specific chapters), or 'full_book'",
                        enumValues: ["current_chapter", "chapters", "full_book"]
                    ),
                    "chapter_ids": PropertySchema(
                        type: "array",
                        description: "Chapter IDs to search (only used when scope is 'chapters')",
                        itemsType: "string",
                        itemsDescription: "Chapter ID"
                    ),
                    "limit": PropertySchema(
                        type: "integer",
                        description: "Maximum results to return (default: 10)"
                    )
                ],
                required: ["query"]
            )
        )
    )

    /// Look up the book concept map for routing
    static let conceptMapLookupTool = ToolDefinition(
        function: FunctionDefinition(
            name: "book_concept_map_lookup",
            description: """
                Look up the book's concept map to find which chapters discuss a topic. The concept map contains pre-extracted:
                - Entities (characters, places, organizations)
                - Themes (abstract concepts)
                - Events (significant plot points)
                Use this tool, 
                    ONLY when you need a chapter list to narrow a subsequent semantic_search or get_chapter_summary, 
                    AND your query is a single concept term (1–2 words) likely to be an entity/theme/event label.
                If the query is a quote, a long phrase, or a specific 3+ word name, prefer lexical_search first.
                Returns: matching entities/themes/events with their chapter locations.
                """,
            parameters: JSONSchema(
                properties: [
                    "query": PropertySchema(
                        type: "string",
                        description: "Entity name, theme, or concept to look up"
                    )
                ],
                required: ["query"]
            )
        )
    )

    /// Get blocks around the current reading position
    static let getSurroundingContextTool = ToolDefinition(
        function: FunctionDefinition(
            name: "get_surrounding_context",
            description: """
                Get text blocks before and after a specific position. Use this for positional expansion:
                - "What happens next?" — expand forward from current position
                - "What led to this?" — expand backward from current position
                - Understanding context around a user's selection
                NOT for finding things — use lexical_search or semantic_search for that.
                """,
            parameters: JSONSchema(
                properties: [
                    "block_id": PropertySchema(
                        type: "string",
                        description: "The block ID to get context around. Use 'current' for the reader's current position."
                    ),
                    "radius": PropertySchema(
                        type: "integer",
                        description: "Number of blocks to include before and after (default: 5)"
                    )
                ],
                required: ["block_id"]
            )
        )
    )

    /// Get the structure/table of contents of the book
    static let getBookStructureTool = ToolDefinition(
        function: FunctionDefinition(
            name: "get_book_structure",
            description: """
                Get the book's table of contents: title, author, and all chapter names with IDs.
                Use this to:
                - Answer "how many chapters?" or "what are the chapter names?"
                - Get chapter IDs for scoped searches
                - Understand the book's organization
                """,
            parameters: JSONSchema(
                properties: [:],
                required: []
            )
        )
    )

    /// Get a chapter summary
    static let getChapterSummaryTool = ToolDefinition(
        function: FunctionDefinition(
            name: "get_chapter_summary",
            description: """
                Get a summary of a specific chapter including key plot points and characters mentioned.
                Use for questions like "what happens in chapter 3?" or to understand a chapter without searching through it.
                Returns: narrative summary, key points, characters mentioned.
                NOTE: If the user asks for specific examples, quotes, or detailed passages after seeing a summary, use get_chapter_full_text instead — summaries don't contain that level of detail.
                """,
            parameters: JSONSchema(
                properties: [
                    "chapter_id": PropertySchema(
                        type: "string",
                        description: "The chapter ID to summarize (from get_book_structure). Use 'current' for the current chapter."
                    )
                ],
                required: ["chapter_id"]
            )
        )
    )

    /// Get the full text of a chapter
    static let getChapterFullTextTool = ToolDefinition(
        function: FunctionDefinition(
            name: "get_chapter_full_text",
            description: """
                Get the complete text of a chapter. Use this when:
                - User asks for specific examples, quotes, or passages from a chapter
                - User asks "what exactly does it say about X?" or "show me the part where..."
                - User wants more detail after seeing a summary
                - You need the actual text to answer a question (not just a summary)
                NOT for initial exploration — use search tools or summaries first.
                Returns: the complete chapter text.
                """,
            parameters: JSONSchema(
                properties: [
                    "chapter_id": PropertySchema(
                        type: "string",
                        description: "The chapter ID (from get_book_structure). Use 'current' for the current chapter."
                    )
                ],
                required: ["chapter_id"]
            )
        )
    )

    /// Get the book synopsis
    static let getBookSynopsisTool = ToolDefinition(
        function: FunctionDefinition(
            name: "get_book_synopsis",
            description: """
                Get a high-level synopsis of the entire book including main characters and themes.
                Use for broad questions like "what is this book about?" or "who are the main characters?"
                NOT for specific plot details — use chapter summaries or searches for those.
                Returns: plot overview, main characters with descriptions, key themes.
                """,
            parameters: JSONSchema(
                properties: [:],
                required: []
            )
        )
    )

    /// Look up information on Wikipedia
    static let wikipediaLookupTool = ToolDefinition(
        function: FunctionDefinition(
            name: "wikipedia_lookup",
            description: """
                Look up factual information on Wikipedia. Use this for:
                - Public figures (politicians, celebrities, historical figures)
                - Places (cities, countries, landmarks)
                - Historical events and dates
                - Scientific concepts and terminology
                - Organizations and companies
                Returns a summary with key facts. Great for verifying factual claims or getting background info on real-world topics mentioned in the book.
                """,
            parameters: JSONSchema(
                properties: [
                    "query": PropertySchema(
                        type: "string",
                        description: "The topic to look up (e.g., 'Albert Einstein', 'World War II', 'Tokyo')"
                    )
                ],
                required: ["query"]
            )
        )
    )

    /// Display an image to the user
    static let renderImageTool = ToolDefinition(
        function: FunctionDefinition(
            name: "render_image",
            description: """
                Display an image inline in chat.
                Use when the user asks what something looks like and you have an image URL (typically from wikipedia_lookup).
                Use sparingly — only when a visual genuinely helps answer the question.
                """,
            parameters: JSONSchema(
                properties: [
                    "url": PropertySchema(
                        type: "string",
                        description: "The URL of the image to display"
                    ),
                    "caption": PropertySchema(
                        type: "string",
                        description: "A brief caption describing the image"
                    )
                ],
                required: ["url"]
            )
        )
    )

    /// Show a map of a place
    static let showMapTool = ToolDefinition(
        function: FunctionDefinition(
            name: "show_map",
            description: """
                Display an inline map for a real-world location.
                Use when the user asks "where is X?" or wants to see a place on a map.
                Only works for real places — not fictional locations from the book.
                """,
            parameters: JSONSchema(
                properties: [
                    "place": PropertySchema(
                        type: "string",
                        description: "The place to show on the map (e.g., 'Eiffel Tower', 'Honduras', 'Baker Street London')"
                    )
                ],
                required: ["place"]
            )
        )
    )
}

// MARK: - Tool Executor

/// Executes tool calls against a BookContext
public struct ToolExecutor {
    private let context: BookContext

    public init(context: BookContext) {
        self.context = context
    }

    /// Execute a tool call and return the result as a string
    public func execute(_ toolCall: ToolCall) async -> String {
        let args = toolCall.function.parseArguments() ?? [:]
        let name = toolCall.function.name

        switch name {
        case "get_current_position":
            return executeGetCurrentPosition()
        case "lexical_search":
            return await executeLexicalSearch(args)
        case "semantic_search":
            return await executeSemanticSearch(args)
        case "book_concept_map_lookup":
            return await executeConceptMapLookup(args)
        case "get_surrounding_context":
            return executeGetSurroundingContext(args)
        case "get_book_structure":
            return executeGetBookStructure()
        case "get_chapter_summary":
            return await executeGetChapterSummary(args)
        case "get_chapter_full_text":
            return executeGetChapterFullText(args)
        case "get_book_synopsis":
            return await executeGetBookSynopsis()
        case "wikipedia_lookup":
            return await executeWikipediaLookup(args)
        case "show_map":
            return await executeShowMap(args)
        case "render_image":
            return executeRenderImage(args)
        default:
            return "Unknown tool: \(name)"
        }
    }

    // MARK: - Tool Implementations

    private func executeGetCurrentPosition() -> String {
        var output = ""

        // Get current section info
        if let currentSection = context.sections.first(where: { $0.spineItemId == context.currentSpineItemId }) {
            let chapterLabel = currentSection.displayLabel
            output += "Current chapter: \(chapterLabel)\n"

            // Calculate percentage through chapter
            if let blockId = context.currentBlockId,
               let block = context.blocksAround(blockId: blockId, count: 0).first,
               currentSection.blockCount > 0 {
                let percentage = Int(round(Double(block.ordinal + 1) / Double(currentSection.blockCount) * 100))
                output += "Position in chapter: \(percentage)% through\n"
                output += "Block \(block.ordinal + 1) of \(currentSection.blockCount)"
            } else {
                output += "Position in chapter: Beginning"
            }
        } else {
            output = "Current position unknown"
        }

        return output
    }

    private func executeLexicalSearch(_ args: [String: Any]) async -> String {
        guard let query = args["query"] as? String else {
            return "Error: query parameter required"
        }

        let scope = args["scope"] as? String ?? "current_chapter"
        let results: [SearchResult]

        if scope == "full_book" {
            results = await context.searchBook(query: query)
        } else {
            results = await context.searchChapter(query: query)
        }

        if results.isEmpty {
            return "No matches found for '\(query)'"
        }

        var output = "Found \(results.count) match(es) for '\(query)':\n\n"
        for (index, result) in results.prefix(10).enumerated() {
            output += "[\(index + 1)] \(result.text)\n\n"
        }

        if results.count > 10 {
            output += "... and \(results.count - 10) more matches"
        }

        return output
    }

    private func executeGetSurroundingContext(_ args: [String: Any]) -> String {
        let blockId = args["block_id"] as? String ?? "current"
        let radius = args["radius"] as? Int ?? 5

        let targetBlockId: String
        if blockId == "current" {
            targetBlockId = context.currentBlockId ?? ""
        } else {
            targetBlockId = blockId
        }

        if targetBlockId.isEmpty {
            return "No current position available"
        }

        let blocks = context.blocksAround(blockId: targetBlockId, count: radius)

        if blocks.isEmpty {
            return "Could not find context around block: \(targetBlockId)"
        }

        var output = "Context (\(blocks.count) blocks):\n\n"
        for block in blocks {
            output += "\(block.textContent)\n\n"
        }

        return output
    }

    private func executeGetBookStructure() -> String {
        var output = "Book: \(context.bookTitle)"
        if let author = context.bookAuthor {
            output += " by \(author)"
        }
        output += "\n\n"

        output += "Sections:\n"
        for (index, section) in context.sections.enumerated() {
            let label = section.displayLabel
            let marker = section.spineItemId == context.currentSpineItemId ? " [current]" : ""
            output += "\(index + 1). \(label) (id: \(section.spineItemId))\(marker)\n"
        }

        return output
    }

    private func executeWikipediaLookup(_ args: [String: Any]) async -> String {
        guard let query = args["query"] as? String else {
            return "Error: query parameter required"
        }

        let service = WikipediaService()

        do {
            // Try direct lookup first
            let summary = try await service.lookup(query: query)
            return formatWikipediaSummary(summary)
        } catch let error as WikipediaError {
            if case .notFound = error {
                // Fall back to search
                do {
                    let results = try await service.search(query: query, limit: 3)
                    if results.isEmpty {
                        return "No Wikipedia articles found for '\(query)'"
                    }
                    // Try first search result
                    let summary = try await service.lookup(query: results[0].title)
                    return formatWikipediaSummary(summary)
                } catch {
                    return "No Wikipedia articles found for '\(query)'"
                }
            }
            return "Error looking up Wikipedia: \(error.localizedDescription)"
        } catch {
            return "Error looking up Wikipedia: \(error.localizedDescription)"
        }
    }

    private func formatWikipediaSummary(_ summary: WikipediaSummary) -> String {
        var output = "Wikipedia: \(summary.title)\n"

        if let description = summary.description {
            output += "\(description)\n"
        }

        output += "\n\(summary.extract)"

        if let imageUrl = summary.imageUrl {
            output += "\n\nImage available: \(imageUrl)"
        }

        if let url = summary.pageUrl {
            output += "\n\nSource: \(url)"
        }

        return output
    }

    private func executeRenderImage(_ args: [String: Any]) -> String {
        guard let url = args["url"] as? String else {
            return "Error: url parameter required"
        }

        let caption = args["caption"] as? String ?? "Image"

        // Return markdown-style image syntax that the UI will parse and render
        return "![[\(caption)]](\(url))"
    }

    private func executeShowMap(_ args: [String: Any]) async -> String {
        guard let place = args["place"] as? String else {
            return "Error: place parameter required"
        }

        let service = MapService()

        do {
            let results = try await service.search(query: place, limit: 1)
            if results.isEmpty {
                return "MAP_ERROR: No location found for '\(place)'"
            }

            let result = results[0]
            let name = result.displayName.components(separatedBy: ",").first ?? result.displayName

            // Return structured data that UI will parse from the trace
            // Format: MAP_RESULT:lat,lon,name
            return "MAP_RESULT:\(result.lat),\(result.lon),\(name)"
        } catch {
            return "MAP_ERROR: \(error.localizedDescription)"
        }
    }

    // MARK: - Semantic Search

    private func executeSemanticSearch(_ args: [String: Any]) async -> String {
        guard let query = args["query"] as? String else {
            return "Error: query parameter required"
        }

        let scope = args["scope"] as? String ?? "full_book"
        let limit = args["limit"] as? Int ?? 10
        let chapterIds = args["chapter_ids"] as? [String]

        // Check if vector index is available
        let bookId = context.bookId
        let vectorStore = VectorStore.shared
        let embeddingService = EmbeddingService.shared

        // Check if index exists
        let isIndexed = await vectorStore.isIndexed(bookId: bookId)
        guard isIndexed else {
            return "Semantic search not available for this book (no vector index). Use lexical_search instead."
        }

        do {
            // Generate query embedding
            let queryEmbedding = try await embeddingService.embed(text: query)

            // Determine scope
            var searchChapterIds: [String]? = nil
            if scope == "current_chapter" {
                searchChapterIds = [context.currentSpineItemId]
            } else if scope == "chapters", let ids = chapterIds {
                searchChapterIds = ids
            }

            // Search vector index
            let results = try await vectorStore.search(
                bookId: bookId,
                queryEmbedding: queryEmbedding,
                k: limit,
                chapterIds: searchChapterIds
            )

            if results.isEmpty {
                return "No semantically similar passages found for '\(query)'"
            }

            // Fetch chunk text for results
            var output = "Found \(results.count) semantically similar passage(s) for '\(query)':\n\n"

            for (index, result) in results.enumerated() {
                // Get chunk text from ChunkStore
                if let chunk = try? await ChunkStore.shared.getChunk(id: result.chunkId) {
                    let snippet = String(chunk.text.prefix(300))
                    let similarity = Int(result.score * 100)
                    output += "[\(index + 1)] (similarity: \(similarity)%)\n\(snippet)...\n\n"
                }
            }

            return output
        } catch {
            return "Semantic search failed: \(error.localizedDescription). Try using search_content instead."
        }
    }

    // MARK: - Concept Map Lookup

    private func executeConceptMapLookup(_ args: [String: Any]) async -> String {
        guard let query = args["query"] as? String else {
            return "Error: query parameter required"
        }

        let bookId = context.bookId

        do {
            // Load concept map
            guard let conceptMap = try await ConceptMapStore.shared.load(bookId: bookId) else {
                return "Concept map not available for this book. Use lexical_search to find information."
            }

            // Perform lookup
            let result = conceptMap.lookup(query: query)

            if result.isEmpty {
                return "No matches found in concept map for '\(query)'. Try a broader search term or use lexical_search."
            }

            var output = "Concept map matches for '\(query)':\n\n"

            // Report entities
            if !result.entities.isEmpty {
                output += "ENTITIES:\n"
                for entity in result.entities.prefix(5) {
                    let typeStr = entity.type?.rawValue ?? "unknown"
                    output += "- \(entity.text) (\(typeStr)): appears in \(entity.chapterIds.count) chapter(s)\n"
                    output += "  Chapters: \(entity.chapterIds.prefix(5).joined(separator: ", "))\n"
                }
                output += "\n"
            }

            // Report themes
            if !result.themes.isEmpty {
                output += "THEMES:\n"
                for theme in result.themes.prefix(3) {
                    output += "- \(theme.label)\n"
                    output += "  Keywords: \(theme.keywords.prefix(5).joined(separator: ", "))\n"
                    output += "  Chapters: \(theme.chapterIds.prefix(5).joined(separator: ", "))\n"
                }
                output += "\n"
            }

            // Report events
            if !result.events.isEmpty {
                output += "EVENTS:\n"
                for event in result.events.prefix(3) {
                    output += "- \(event.displayLabel)\n"
                    output += "  Chapters: \(event.chapterIds.joined(separator: ", "))\n"
                }
                output += "\n"
            }

            // Summary of relevant chapters
            output += "RELEVANT CHAPTERS: \(result.chapterIds.prefix(10).joined(separator: ", "))"
            if result.chapterIds.count > 10 {
                output += " (and \(result.chapterIds.count - 10) more)"
            }

            return output
        } catch {
            return "Concept map lookup failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Chapter Summary

    private func executeGetChapterSummary(_ args: [String: Any]) async -> String {
        let chapterId = args["chapter_id"] as? String ?? "current"

        guard let targetId = Self.resolveChapterId(chapterId, in: context) else {
            return "Unknown chapter_id '\(chapterId)'. Use get_book_structure and pass the id field."
        }

        // Find the chapter
        guard let section = context.sections.first(where: { $0.spineItemId == targetId }) else {
            return "Chapter not found: \(targetId)"
        }

        // Get chapter text
        guard let chapterText = context.chapterText(spineItemId: targetId) else {
            return "Could not retrieve chapter text for: \(targetId)"
        }

        do {
            let summary = try await ChapterSummaryService.shared.getSummary(
                bookId: context.bookId,
                chapterId: targetId,
                chapterTitle: section.title,
                chapterText: chapterText
            )

            var output = "Chapter Summary"
            if let title = section.title {
                output += ": \(title)"
            }
            output += "\n\n"

            output += summary.summary
            output += "\n\n"

            if !summary.keyPoints.isEmpty {
                output += "KEY POINTS:\n"
                for point in summary.keyPoints {
                    output += "- \(point)\n"
                }
                output += "\n"
            }

            if !summary.charactersMentioned.isEmpty {
                output += "CHARACTERS MENTIONED: \(summary.charactersMentioned.joined(separator: ", "))"
            }

            return output
        } catch {
            return "Failed to generate chapter summary: \(error.localizedDescription)"
        }
    }

    static func resolveChapterId(_ chapterId: String, in context: BookContext) -> String? {
        if chapterId == "current" {
            return context.currentSpineItemId
        }

        if context.sections.contains(where: { $0.spineItemId == chapterId }) {
            return chapterId
        }
        return nil
    }

    // MARK: - Chapter Full Text

    private func executeGetChapterFullText(_ args: [String: Any]) -> String {
        let chapterId = args["chapter_id"] as? String ?? "current"

        guard let targetId = Self.resolveChapterId(chapterId, in: context) else {
            return "Unknown chapter_id '\(chapterId)'. Use get_book_structure and pass the id field."
        }

        // Find the chapter for its title
        let section = context.sections.first(where: { $0.spineItemId == targetId })

        // Get chapter text
        guard let chapterText = context.chapterText(spineItemId: targetId) else {
            return "Could not retrieve chapter text for: \(targetId)"
        }

        var output = "Chapter"
        if let title = section?.displayLabel {
            output += ": \(title)"
        }
        output += "\n\n"
        output += chapterText

        return output
    }

    // MARK: - Book Synopsis

    private func executeGetBookSynopsis() async -> String {
        do {
            // Try to load concept map for richer synopsis
            let conceptMap = try? await ConceptMapStore.shared.load(bookId: context.bookId)

            let synopsis = try await BookSynopsisService.shared.getSynopsis(
                bookId: context.bookId,
                bookTitle: context.bookTitle,
                bookAuthor: context.bookAuthor,
                chapters: context.sections,
                conceptMap: conceptMap
            )

            var output = "Book Synopsis: \(synopsis.bookTitle)"
            if let author = synopsis.bookAuthor {
                output += " by \(author)"
            }
            output += "\n\n"

            output += synopsis.synopsis
            output += "\n\n"

            if !synopsis.mainCharacters.isEmpty {
                output += "MAIN CHARACTERS:\n"
                for character in synopsis.mainCharacters {
                    output += "- \(character.name): \(character.description)\n"
                }
                output += "\n"
            }

            if !synopsis.mainThemes.isEmpty {
                output += "MAIN THEMES:\n"
                for theme in synopsis.mainThemes {
                    output += "- \(theme)\n"
                }
            }

            return output
        } catch {
            return "Failed to generate book synopsis: \(error.localizedDescription)"
        }
    }
}
