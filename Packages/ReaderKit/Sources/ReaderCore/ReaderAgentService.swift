import Foundation

// MARK: - Reader Agent Service

/// Agent service that handles LLM conversations with tool calling
public actor ReaderAgentService {
    /// Maximum number of tool-calling rounds to prevent infinite loops
    private let maxToolRounds = 10

    public init() {}

    /// Send a chat message and get a response, potentially with tool calls
    /// Returns the response and updated conversation history
    public func chat(
        message: String,
        context: BookContext,
        history: [AgentMessage]
    ) async throws -> (response: AgentResponse, updatedHistory: [AgentMessage]) {
        var history = history
        guard let apiKey = OpenRouterConfig.apiKey, !apiKey.isEmpty else {
            throw OpenRouterError.missingAPIKey
        }

        // Build system prompt with book context
        let systemPrompt = buildSystemPrompt(context: context)

        // Capture book context for trace
        let currentSection = context.sections.first { $0.spineItemId == context.currentSpineItemId }
        let traceBookContext = TraceBookContext(
            title: context.bookTitle,
            author: context.bookAuthor,
            currentChapter: currentSection?.title,
            position: buildPositionString(context),
            surroundingText: buildSurroundingText(context)
        )

        // Add user message to history
        history.append(AgentMessage(role: .user, content: message))

        // Tool executor for this context
        let executor = ToolExecutor(context: context)

        // Track tool calls made during this conversation
        var toolCallsMade: [String] = []
        var toolExecutions: [ToolExecution] = []

        // Agent loop: keep calling until no more tool calls
        var rounds = 0
        while rounds < maxToolRounds {
            rounds += 1

            // Make API request
            let response = try await callOpenRouter(
                systemPrompt: systemPrompt,
                history: history,
                apiKey: apiKey
            )

            // Check for tool calls
            if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                // Add assistant message with tool calls to history
                history.append(AgentMessage(
                    role: .assistant,
                    content: response.content,
                    toolCalls: toolCalls
                ))

                // Execute each tool and add results
                for call in toolCalls {
                    toolCallsMade.append(call.function.name)

                    // Capture timing and result
                    let startTime = Date()
                    let result = executor.execute(call)
                    let executionTime = Date().timeIntervalSince(startTime)

                    // Record tool execution for trace
                    toolExecutions.append(ToolExecution(
                        toolCallId: call.id,
                        functionName: call.function.name,
                        arguments: call.function.arguments,
                        result: result,
                        executionTime: executionTime,
                        success: true,
                        error: nil
                    ))

                    history.append(AgentMessage(
                        role: .tool,
                        content: result,
                        toolCallId: call.id
                    ))
                }

                // Continue loop to get final response
                continue
            }

            // No tool calls - we have a final response
            if let content = response.content {
                history.append(AgentMessage(role: .assistant, content: content))

                // Build execution trace
                let trace = AgentExecutionTrace(
                    bookContext: traceBookContext,
                    toolExecutions: toolExecutions,
                    timestamp: Date()
                )

                return (
                    response: AgentResponse(content: content, toolCallsMade: toolCallsMade, executionTrace: trace),
                    updatedHistory: history
                )
            } else {
                throw ReaderAgentError.emptyResponse
            }
        }

        throw ReaderAgentError.maxToolRoundsExceeded
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(context: BookContext) -> String {
        var prompt = """
        You are a helpful reading assistant. You help users understand and explore books they're reading.

        You have access to tools that let you read chapter content, search for text, and find character mentions.
        Use these tools when needed to provide accurate, grounded responses.

        Be concise and direct. When quoting from the book, be accurate.
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

        // Add context around current reading position
        if let blockId = context.currentBlockId {
            let surroundingBlocks = context.blocksAround(blockId: blockId, count: 3)
            if !surroundingBlocks.isEmpty {
                let contextText = surroundingBlocks.map { $0.textContent }.joined(separator: "\n\n")
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

        let text = blocks.map { $0.textContent }.joined(separator: " ")

        // Limit to approximately 100 words
        let words = text.split(separator: " ")
        if words.count > 100 {
            return words.prefix(100).joined(separator: " ") + "..."
        }

        return text
    }

    // MARK: - API Call

    private func callOpenRouter(
        systemPrompt: String,
        history: [AgentMessage],
        apiKey: String
    ) async throws -> LLMResponse {
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // Build messages array
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for msg in history {
            messages.append(msg.toDictionary())
        }

        // Build tools array
        let tools = AgentTools.allTools.map { $0.toDictionary() }

        let body: [String: Any] = [
            "model": OpenRouterConfig.model,
            "messages": messages,
            "tools": tools
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

        return try parseResponse(data)
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> LLMResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw OpenRouterError.invalidResponse
        }

        let content = message["content"] as? String

        // Parse tool calls if present
        var toolCalls: [ToolCall]? = nil
        if let toolCallsArray = message["tool_calls"] as? [[String: Any]] {
            toolCalls = toolCallsArray.compactMap { parseToolCall($0) }
        }

        return LLMResponse(content: content, toolCalls: toolCalls)
    }

    private func parseToolCall(_ dict: [String: Any]) -> ToolCall? {
        guard let id = dict["id"] as? String,
              let type = dict["type"] as? String,
              let function = dict["function"] as? [String: Any],
              let name = function["name"] as? String,
              let arguments = function["arguments"] as? String else {
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
}

// MARK: - Errors

public enum ReaderAgentError: LocalizedError {
    case emptyResponse
    case maxToolRoundsExceeded

    public var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Received empty response from LLM"
        case .maxToolRoundsExceeded:
            return "Maximum tool calling rounds exceeded"
        }
    }
}
