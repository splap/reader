import Foundation

// MARK: - Tool Registry

/// All available tools for the reader agent
public enum AgentTools {
    /// All tool definitions for the API request
    public static var allTools: [ToolDefinition] {
        return [
            getCurrentPositionTool,
            getChapterTextTool,
            searchContentTool,
            getCharacterMentionsTool,
            getSurroundingContextTool,
            getBookStructureTool,
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
            description: "Get detailed information about the reader's current position in the book, including chapter name and progress through the chapter.",
            parameters: JSONSchema(
                properties: [:],
                required: []
            )
        )
    )

    /// Get the full text content of a chapter/section
    static let getChapterTextTool = ToolDefinition(
        function: FunctionDefinition(
            name: "get_chapter_text",
            description: "Get the full text content of a chapter or section. Use this to read and understand what's in a specific part of the book.",
            parameters: JSONSchema(
                properties: [
                    "spine_item_id": PropertySchema(
                        type: "string",
                        description: "The spine item ID of the chapter to retrieve. Use 'current' for the chapter the reader is currently viewing."
                    )
                ],
                required: ["spine_item_id"]
            )
        )
    )

    /// Search for text in the current chapter
    static let searchContentTool = ToolDefinition(
        function: FunctionDefinition(
            name: "search_content",
            description: "Search for passages containing specific text or concepts in the book content. Returns matching passages with their locations.",
            parameters: JSONSchema(
                properties: [
                    "query": PropertySchema(
                        type: "string",
                        description: "The text or concept to search for"
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

    /// Find all mentions of a character or entity
    static let getCharacterMentionsTool = ToolDefinition(
        function: FunctionDefinition(
            name: "get_character_mentions",
            description: "Find all passages that mention a specific character, person, or entity. Useful for understanding a character's role or tracking their appearances.",
            parameters: JSONSchema(
                properties: [
                    "name": PropertySchema(
                        type: "string",
                        description: "The name of the character or entity to find"
                    ),
                    "scope": PropertySchema(
                        type: "string",
                        description: "Where to search: 'current_chapter' or 'full_book'",
                        enumValues: ["current_chapter", "full_book"]
                    )
                ],
                required: ["name"]
            )
        )
    )

    /// Get blocks around the current reading position
    static let getSurroundingContextTool = ToolDefinition(
        function: FunctionDefinition(
            name: "get_surrounding_context",
            description: "Get the text blocks surrounding a specific position in the book. Useful for understanding the context around a selection or position.",
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
            description: "Get the book's structure including title, author, and list of chapters/sections. Useful for understanding the book's organization.",
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
                Display an image to the user in the chat. Use this when:
                - The user asks what someone or something looks like
                - A visual would help explain or illustrate your answer
                - You have an image URL from Wikipedia or another source
                The image will be displayed inline in the conversation. Use sparingly - only when visuals genuinely add value.
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
                Display a map showing a place, landmark, or location. Use this when the user wants to see where something is located. The map will be displayed inline in the conversation.
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
        case "get_chapter_text":
            return executeGetChapterText(args)
        case "search_content":
            return executeSearchContent(args)
        case "get_character_mentions":
            return executeGetCharacterMentions(args)
        case "get_surrounding_context":
            return executeGetSurroundingContext(args)
        case "get_book_structure":
            return executeGetBookStructure()
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

    private func executeGetChapterText(_ args: [String: Any]) -> String {
        let spineItemId = args["spine_item_id"] as? String ?? "current"

        let targetId: String
        if spineItemId == "current" {
            targetId = context.currentSpineItemId
        } else {
            targetId = spineItemId
        }

        if let text = context.chapterText(spineItemId: targetId) {
            return text
        } else {
            return "Chapter not found: \(targetId)"
        }
    }

    private func executeSearchContent(_ args: [String: Any]) -> String {
        guard let query = args["query"] as? String else {
            return "Error: query parameter required"
        }

        let scope = args["scope"] as? String ?? "current_chapter"
        let results: [SearchResult]

        if scope == "full_book" {
            results = context.searchBook(query: query)
        } else {
            results = context.searchChapter(query: query)
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

    private func executeGetCharacterMentions(_ args: [String: Any]) -> String {
        guard let name = args["name"] as? String else {
            return "Error: name parameter required"
        }

        let scope = args["scope"] as? String ?? "current_chapter"
        let results: [SearchResult]

        if scope == "full_book" {
            results = context.searchBook(query: name)
        } else {
            results = context.searchChapter(query: name)
        }

        if results.isEmpty {
            return "No mentions found for '\(name)'"
        }

        var output = "Found \(results.count) mention(s) of '\(name)':\n\n"
        for (index, result) in results.prefix(15).enumerated() {
            output += "[\(index + 1)] \(result.text)\n\n"
        }

        if results.count > 15 {
            output += "... and \(results.count - 15) more mentions"
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
            output += "\(index + 1). \(label)\(marker)\n"
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
}
