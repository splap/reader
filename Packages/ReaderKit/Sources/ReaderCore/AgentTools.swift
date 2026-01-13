import Foundation

// MARK: - Tool Registry

/// All available tools for the reader agent
public enum AgentTools {
    /// All tool definitions for the API request
    public static var allTools: [ToolDefinition] {
        return [
            getChapterTextTool,
            searchContentTool,
            getCharacterMentionsTool,
            getSurroundingContextTool,
            getBookStructureTool
        ]
    }

    // MARK: - Tool Definitions

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
}

// MARK: - Tool Executor

/// Executes tool calls against a BookContext
public struct ToolExecutor {
    private let context: BookContext

    public init(context: BookContext) {
        self.context = context
    }

    /// Execute a tool call and return the result as a string
    public func execute(_ toolCall: ToolCall) -> String {
        let args = toolCall.function.parseArguments() ?? [:]
        let name = toolCall.function.name

        switch name {
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
        default:
            return "Unknown tool: \(name)"
        }
    }

    // MARK: - Tool Implementations

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
            let title = section.title ?? "Section \(index + 1)"
            let marker = section.spineItemId == context.currentSpineItemId ? " [current]" : ""
            output += "\(index + 1). \(title)\(marker)\n"
        }

        return output
    }
}
