import Foundation

// MARK: - Reader Agent Service

/// Agent service that handles LLM conversations with tool calling
public actor ReaderAgentService: AgentServiceProtocol {
    private static let logger = Log.logger(category: "ReaderAgentService")

    /// Maximum number of tool-calling rounds to prevent infinite loops
    private let maxToolRounds = 10

    /// Router for question classification
    private let router = BookChatRouter()

    public init() {}

    /// Send a chat message and get a response, potentially with tool calls
    /// Returns the response and updated conversation history
    /// - Parameters:
    ///   - message: The user's message
    ///   - context: Book context for tool execution
    ///   - history: Conversation history
    ///   - selectionContext: Optional surrounding text from user's text selection (500 chars around selection)
    ///   - selectionBlockId: Optional block ID where the selection was made
    ///   - selectionSpineItemId: Optional spine item ID where the selection was made
    public func chat(
        message: String,
        context: BookContext,
        history: [AgentMessage],
        selectionContext: String? = nil,
        selectionBlockId: String? = nil,
        selectionSpineItemId: String? = nil
    ) async throws -> (response: AgentResponse, updatedHistory: [AgentMessage]) {
        var history = history
        guard let apiKey = OpenRouterConfig.apiKey, !apiKey.isEmpty else {
            throw OpenRouterError.missingAPIKey
        }

        // Step 1: Route the question
        let conceptMap = try? await ConceptMapStore.shared.load(bookId: context.bookId)
        let routingResult = await router.route(
            question: message,
            bookTitle: context.bookTitle,
            bookAuthor: context.bookAuthor,
            conceptMap: conceptMap
        )

        Self.logger.debug("Routed question: \(routingResult.route.rawValue) (confidence: \(routingResult.confidence))")

        // Step 2: Build system prompt with routing context
        let systemPrompt = buildSystemPrompt(
            context: context,
            selectionContext: selectionContext,
            selectionBlockId: selectionBlockId,
            routingResult: routingResult
        )

        // Capture book context for trace
        let traceBookContext = buildTraceBookContext(
            context: context,
            selectionContext: selectionContext,
            selectionBlockId: selectionBlockId,
            selectionSpineItemId: selectionSpineItemId
        )

        // Add user message to history
        history.append(AgentMessage(role: .user, content: message))

        // Tool executor for this context
        let executor = ToolExecutor(context: context)

        // Initialize tool budget for guardrails
        var toolBudget = ExecutionGuardrails.ToolBudget()

        // Track tool calls made during this conversation
        var toolCallsMade: [String] = []
        var toolExecutions: [ToolExecution] = []
        var timeline: [TimelineStep] = [.user(message)] // Start timeline with user message

        // Agent loop: keep calling until no more tool calls
        var rounds = 0
        while rounds < maxToolRounds {
            rounds += 1

            // Make API request
            let llmStartTime = Date()
            let response = try await callOpenRouter(
                systemPrompt: systemPrompt,
                history: history,
                apiKey: apiKey,
                routingResult: routingResult
            )
            let llmDuration = Date().timeIntervalSince(llmStartTime)
            Self.logger.info("LLM call completed in \(String(format: "%.2f", llmDuration))s (model: \(OpenRouterConfig.model))")

            // Check for tool calls
            if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                // Record LLM call that requested tools
                let llmExec = LLMExecution(
                    model: OpenRouterConfig.model,
                    executionTime: llmDuration,
                    inputTokens: response.inputTokens,
                    outputTokens: response.outputTokens,
                    requestedTools: toolCalls.map(\.function.name)
                )
                timeline.append(.llm(llmExec))

                // Add assistant message with tool calls to history
                history.append(AgentMessage(
                    role: .assistant,
                    content: response.content,
                    toolCalls: toolCalls
                ))

                // Execute each tool (respecting budget) and add results
                for call in toolCalls {
                    // Check tool budget
                    guard toolBudget.useToolCall() else {
                        Self.logger.warning("Tool budget exhausted, skipping: \(call.function.name)")
                        history.append(AgentMessage(
                            role: .tool,
                            content: "Tool budget exceeded. Maximum \(ExecutionGuardrails.maxToolCalls) tool calls per question.",
                            toolCallId: call.id,
                            functionName: call.function.name
                        ))
                        continue
                    }

                    toolCallsMade.append(call.function.name)

                    // Capture timing and result
                    let startTime = Date()
                    let result = await executor.execute(call)
                    let executionTime = Date().timeIntervalSince(startTime)
                    Self.logger.info("Tool call \(call.function.name) completed in \(String(format: "%.2f", executionTime))s")

                    // Track evidence for book questions
                    if routingResult.route == .book || routingResult.route == .ambiguous {
                        let searchTools = ["lexical_search", "semantic_search", "book_concept_map_lookup"]
                        if searchTools.contains(call.function.name), !result.contains("No matches"), !result.contains("not found") {
                            toolBudget.recordEvidence(count: 1)
                        }
                    }

                    // Record tool execution for trace and timeline
                    let toolExec = ToolExecution(
                        toolCallId: call.id,
                        functionName: call.function.name,
                        arguments: call.function.arguments,
                        result: result,
                        executionTime: executionTime,
                        success: true,
                        error: nil
                    )
                    toolExecutions.append(toolExec)
                    timeline.append(.tool(toolExec))

                    history.append(AgentMessage(
                        role: .tool,
                        content: result,
                        toolCallId: call.id,
                        functionName: call.function.name
                    ))
                }

                // Continue loop to get final response
                continue
            }

            // No tool calls - we have a final response
            if let content = response.content {
                // Record final LLM call
                let llmExec = LLMExecution(
                    model: OpenRouterConfig.model,
                    executionTime: llmDuration,
                    inputTokens: response.inputTokens,
                    outputTokens: response.outputTokens,
                    requestedTools: nil
                )
                timeline.append(.llm(llmExec))

                // Evidence check for book questions
                let finalContent = content
                if routingResult.route == .book, !toolBudget.hasEvidence, toolCallsMade.isEmpty {
                    Self.logger.debug("No evidence retrieved for book question")
                }

                history.append(AgentMessage(role: .assistant, content: finalContent))

                // Add assistant response to timeline
                timeline.append(.assistant(finalContent))

                // Build execution trace
                let trace = AgentExecutionTrace(
                    bookContext: traceBookContext,
                    toolExecutions: toolExecutions,
                    timeline: timeline,
                    timestamp: Date()
                )

                return (
                    response: AgentResponse(content: finalContent, toolCallsMade: toolCallsMade, executionTrace: trace),
                    updatedHistory: history
                )
            } else {
                throw ReaderAgentError.emptyResponse
            }
        }

        throw ReaderAgentError.maxToolRoundsExceeded
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(
        context: BookContext,
        selectionContext: String?,
        selectionBlockId: String?,
        routingResult: RoutingResult? = nil
    ) -> String {
        var prompt = """
        You are a helpful assistant. The user is currently reading a book and may ask questions about it, \
        but they may also ask general knowledge questions unrelated to the book.
        """

        // Add routing-specific guidance
        if let routing = routingResult {
            switch routing.route {
            case .book:
                prompt += """


                ROUTING: This question appears to be about the book (confidence: \(Int(routing.confidence * 100))%).

                CRITICAL: You do NOT have the book text in your context. You MUST use tools to retrieve it.
                - If the user asks for specific chapters, quotes, or exact text: use get_chapter_full_text
                - If the user asks about themes or wants to find passages: use semantic_search or lexical_search
                - For chapter overviews: use get_chapter_summary

                IMPORTANT: Do not make claims about the book without retrieving evidence first.
                If you cannot find relevant information, say so rather than guessing.
                When calling get_chapter_summary, always use the chapter id from get_book_structure (id: ...).
                """

                if !routing.suggestedChapterIds.isEmpty {
                    prompt += "\nSuggested chapters to search: \(routing.suggestedChapterIds.prefix(5).joined(separator: ", "))"
                }

            case .notBook:
                prompt += """


                ROUTING: This question appears to be general knowledge, not about the book.
                Answer directly from your knowledge. You may still use tools if helpful.
                """

            case .ambiguous:
                prompt += """


                ROUTING: It's unclear if this question is about the book or general knowledge.
                Consider using book_concept_map_lookup first to check if the topic appears in the book.
                If the topic is in the book, search for relevant passages. Otherwise, answer from general knowledge.
                """
            }
        } else {
            prompt += """


            For questions about the book, you have tools to search and read content. Use them when needed.
            For general questions, answer directly from your knowledge.
            """
        }

        prompt += """


        Don't assume every question is about the book - use your judgment.
        When quoting from the book, be accurate.

        TOOL BUDGET: You have a maximum of \(ExecutionGuardrails.maxToolCalls) tool calls per question. Use them wisely.

        IMAGE DISPLAY: When you have an image URL (e.g., from Wikipedia) and showing it would help answer \
        the user's question (like "what does X look like?"), include it in your response using this format: \
        ![caption](url). The image will be displayed inline. Only include images when they add value.
        """

        prompt += "\n\nCurrent book: \(context.bookTitle)"
        if let author = context.bookAuthor {
            prompt += " by \(author)"
        }

        // Add current chapter/section info
        let currentSection = context.sections.first { $0.spineItemId == context.currentSpineItemId }
        if let section = currentSection, let title = section.title {
            prompt += "\nCurrent chapter: \(title)"
        }

        // If user selected text, include the surrounding context from their selection
        // This takes priority over block-based position context
        if let selectionContext {
            prompt += """


            The user has highlighted text in the book. Here is the surrounding context from around their selection:
            \(selectionContext)
            """

            // If we have the block ID, tell the LLM it can use tools for more context
            if let blockId = selectionBlockId {
                prompt += "\n\nTo get more context around this selection, you can use get_surrounding_context with block_id: \"\(blockId)\""
            }
        } else if let blockId = context.currentBlockId {
            // Fall back to block-based context from reading position
            let surroundingBlocks = context.blocksAround(blockId: blockId, count: 3)
            if !surroundingBlocks.isEmpty {
                let contextText = surroundingBlocks.map(\.textContent).joined(separator: "\n\n")
                prompt += """


                Current reading position (visible text on screen):
                \(contextText)
                """
            }
        }

        return prompt
    }

    private func buildPositionString(_ context: BookContext) -> String {
        // Find current section
        let currentSection = context.sections.first { $0.spineItemId == context.currentSpineItemId }

        if let section = currentSection, let title = section.title {
            return "In \(title)"
        } else if context.currentBlockId != nil {
            return "Current position"
        } else {
            return "Beginning of book"
        }
    }

    private func buildSurroundingText(_ context: BookContext) -> String? {
        guard let blockId = context.currentBlockId else {
            return nil
        }

        let blocks = context.blocksAround(blockId: blockId, count: 3)
        guard !blocks.isEmpty else {
            return nil
        }

        let text = blocks.map(\.textContent).joined(separator: " ")

        // Limit to approximately 100 words
        let words = text.split(separator: " ")
        if words.count > 100 {
            return words.prefix(100).joined(separator: " ") + "..."
        }

        return text
    }

    /// Build trace book context with proper position info from selection or reading position
    private func buildTraceBookContext(
        context: BookContext,
        selectionContext: String?,
        selectionBlockId: String?,
        selectionSpineItemId: String?
    ) -> TraceBookContext {
        // If we have selection position info, use it to build better position string
        if let blockId = selectionBlockId, let spineItemId = selectionSpineItemId {
            // Find the section for this spine item
            if let section = context.sections.first(where: { $0.spineItemId == spineItemId }) {
                // Get the block to find its ordinal
                let blocks = context.blocksAround(blockId: blockId, count: 0)
                if let block = blocks.first {
                    let percentage = section.blockCount > 0
                        ? Int(round(Double(block.ordinal + 1) / Double(section.blockCount) * 100))
                        : 0
                    let chapterTitle = section.title ?? "Chapter"
                    let position = "\(chapterTitle) (\(percentage)% through)"

                    return TraceBookContext(
                        title: context.bookTitle,
                        author: context.bookAuthor,
                        currentChapter: section.title,
                        position: position,
                        surroundingText: selectionContext
                    )
                }
            }

            // Fallback if we couldn't look up the block
            let section = context.sections.first { $0.spineItemId == selectionSpineItemId }
            return TraceBookContext(
                title: context.bookTitle,
                author: context.bookAuthor,
                currentChapter: section?.title,
                position: section?.title ?? "Selected text",
                surroundingText: selectionContext
            )
        }

        // Fall back to reader's current position
        let currentSection = context.sections.first { $0.spineItemId == context.currentSpineItemId }
        return TraceBookContext(
            title: context.bookTitle,
            author: context.bookAuthor,
            currentChapter: currentSection?.title,
            position: buildPositionString(context),
            surroundingText: selectionContext ?? buildSurroundingText(context)
        )
    }

    // MARK: - API Call

    private func callOpenRouter(
        systemPrompt: String,
        history: [AgentMessage],
        apiKey: String,
        routingResult _: RoutingResult? = nil
    ) async throws -> LLMResponse {
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // Build messages array
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
        ]

        for msg in history {
            messages.append(msg.toDictionary())
        }

        // Build tools array - for NOT_BOOK routing, we can optionally exclude book tools
        // but we keep all tools available for flexibility
        let tools = AgentTools.allTools.map { $0.toDictionary() }

        let body: [String: Any] = [
            "model": OpenRouterConfig.model,
            "messages": messages,
            "tools": tools,
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

        return try parseResponse(data)
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> LLMResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any]
        else {
            throw OpenRouterError.invalidResponse
        }

        let content = message["content"] as? String

        // Parse tool calls if present
        var toolCalls: [ToolCall]? = nil
        if let toolCallsArray = message["tool_calls"] as? [[String: Any]] {
            toolCalls = toolCallsArray.compactMap { parseToolCall($0) }
        }

        // Parse token usage
        var inputTokens: Int?
        var outputTokens: Int?
        if let usage = json["usage"] as? [String: Any] {
            inputTokens = usage["prompt_tokens"] as? Int
            outputTokens = usage["completion_tokens"] as? Int
        }

        return LLMResponse(content: content, toolCalls: toolCalls, inputTokens: inputTokens, outputTokens: outputTokens)
    }

    private func parseToolCall(_ dict: [String: Any]) -> ToolCall? {
        guard let id = dict["id"] as? String,
              let type = dict["type"] as? String,
              let function = dict["function"] as? [String: Any],
              let name = function["name"] as? String,
              let arguments = function["arguments"] as? String
        else {
            return nil
        }

        return ToolCall(
            id: id,
            type: type,
            function: FunctionCall(name: name, arguments: arguments)
        )
    }
}

// MARK: - Helper Types

private struct LLMResponse {
    let content: String?
    let toolCalls: [ToolCall]?
    let inputTokens: Int?
    let outputTokens: Int?
}

// MARK: - Errors

public enum ReaderAgentError: LocalizedError {
    case emptyResponse
    case maxToolRoundsExceeded

    public var errorDescription: String? {
        switch self {
        case .emptyResponse:
            "Received empty response from LLM"
        case .maxToolRoundsExceeded:
            "Maximum tool calling rounds exceeded"
        }
    }
}
