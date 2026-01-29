import Foundation

// MARK: - Agent Service Protocol

/// Protocol for agent services that handle LLM conversations
public protocol AgentServiceProtocol: Sendable {
    /// Send a chat message and get a response
    func chat(
        message: String,
        context: BookContext,
        history: [AgentMessage],
        selectionContext: String?,
        selectionBlockId: String?,
        selectionSpineItemId: String?
    ) async throws -> (response: AgentResponse, updatedHistory: [AgentMessage])
}

// MARK: - Message Types

/// Role in a conversation
public enum AgentRole: String, Codable {
    case system
    case user
    case assistant
    case tool
}

/// A message in the agent conversation
public struct AgentMessage: Codable {
    public let role: AgentRole
    public let content: String?
    public let toolCalls: [ToolCall]?
    public let toolCallId: String?
    /// For tool result messages, the name of the function that was called
    public let functionName: String?

    public init(
        role: AgentRole,
        content: String?,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        functionName: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.functionName = functionName
    }

    /// Convert to dictionary for API request
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["role": role.rawValue]

        if let content {
            dict["content"] = content
        }

        if let toolCallId {
            dict["tool_call_id"] = toolCallId
        }

        if let toolCalls, !toolCalls.isEmpty {
            dict["tool_calls"] = toolCalls.map { $0.toDictionary() }
        }

        return dict
    }
}

// MARK: - Tool Call Types

/// A tool call requested by the LLM
public struct ToolCall: Codable {
    public let id: String
    public let type: String
    public let function: FunctionCall

    public init(id: String, type: String = "function", function: FunctionCall) {
        self.id = id
        self.type = type
        self.function = function
    }

    func toDictionary() -> [String: Any] {
        [
            "id": id,
            "type": type,
            "function": [
                "name": function.name,
                "arguments": function.arguments,
            ],
        ]
    }
}

/// Function details within a tool call
public struct FunctionCall: Codable {
    public let name: String
    public let arguments: String

    public init(name: String, arguments: String) {
        self.name = name
        self.arguments = arguments
    }

    /// Parse arguments as JSON dictionary
    public func parseArguments() -> [String: Any]? {
        guard let data = arguments.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// MARK: - Tool Definition Types

/// A tool definition for the OpenRouter API
public struct ToolDefinition {
    public let type: String
    public let function: FunctionDefinition

    public init(function: FunctionDefinition) {
        type = "function"
        self.function = function
    }

    func toDictionary() -> [String: Any] {
        [
            "type": type,
            "function": function.toDictionary(),
        ]
    }
}

/// Function definition with JSON schema parameters
public struct FunctionDefinition {
    public let name: String
    public let description: String
    public let parameters: JSONSchema

    public init(name: String, description: String, parameters: JSONSchema) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    func toDictionary() -> [String: Any] {
        [
            "name": name,
            "description": description,
            "parameters": parameters.toDictionary(),
        ]
    }
}

/// Simple JSON Schema representation for tool parameters
public struct JSONSchema {
    public let type: String
    public let properties: [String: PropertySchema]
    public let required: [String]

    public init(
        type: String = "object",
        properties: [String: PropertySchema],
        required: [String] = []
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }

    func toDictionary() -> [String: Any] {
        var propsDict: [String: Any] = [:]
        for (key, prop) in properties {
            propsDict[key] = prop.toDictionary()
        }

        return [
            "type": type,
            "properties": propsDict,
            "required": required,
        ]
    }
}

/// Property schema for a single parameter
public struct PropertySchema {
    public let type: String
    public let description: String
    public let enumValues: [String]?
    public let itemsType: String?
    public let itemsDescription: String?
    public let itemsEnumValues: [String]?

    public init(
        type: String,
        description: String,
        enumValues: [String]? = nil,
        itemsType: String? = nil,
        itemsDescription: String? = nil,
        itemsEnumValues: [String]? = nil
    ) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
        self.itemsType = itemsType
        self.itemsDescription = itemsDescription
        self.itemsEnumValues = itemsEnumValues
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type,
            "description": description,
        ]
        if let enumValues {
            dict["enum"] = enumValues
        }
        if let itemsType {
            var itemsDict: [String: Any] = ["type": itemsType]
            if let itemsDescription {
                itemsDict["description"] = itemsDescription
            }
            if let itemsEnumValues {
                itemsDict["enum"] = itemsEnumValues
            }
            dict["items"] = itemsDict
        }
        return dict
    }
}

// MARK: - Search Result

/// Result from searching book content
public struct SearchResult {
    public let blockId: String
    public let spineItemId: String
    public let text: String
    public let matchRange: Range<String.Index>?

    public init(blockId: String, spineItemId: String, text: String, matchRange: Range<String.Index>? = nil) {
        self.blockId = blockId
        self.spineItemId = spineItemId
        self.text = text
        self.matchRange = matchRange
    }
}

// MARK: - Agent Response

/// Response from the agent, including any tool calls made
public struct AgentResponse {
    public let content: String
    public let toolCallsMade: [String]
    public let executionTrace: AgentExecutionTrace?

    public init(content: String, toolCallsMade: [String] = [], executionTrace: AgentExecutionTrace? = nil) {
        self.content = content
        self.toolCallsMade = toolCallsMade
        self.executionTrace = executionTrace
    }
}

// MARK: - Execution Trace

/// Captures complete execution context for debugging
public struct AgentExecutionTrace: Codable {
    public let bookContext: TraceBookContext
    public let toolExecutions: [ToolExecution]
    public let timeline: [TimelineStep]
    public let timestamp: Date

    public init(bookContext: TraceBookContext, toolExecutions: [ToolExecution], timeline: [TimelineStep] = [], timestamp: Date) {
        self.bookContext = bookContext
        self.toolExecutions = toolExecutions
        self.timeline = timeline
        self.timestamp = timestamp
    }

    /// Total execution time across all steps
    public var totalExecutionTime: TimeInterval {
        timeline.reduce(0) { $0 + $1.executionTime }
    }
}

/// Book context at the time of agent execution
public struct TraceBookContext: Codable {
    public let title: String
    public let author: String?
    public let currentChapter: String?
    public let position: String
    public let surroundingText: String?

    public init(title: String, author: String?, currentChapter: String?, position: String, surroundingText: String?) {
        self.title = title
        self.author = author
        self.currentChapter = currentChapter
        self.position = position
        self.surroundingText = surroundingText
    }
}

/// Details of a single tool execution
public struct ToolExecution: Codable {
    public let toolCallId: String
    public let functionName: String
    public let arguments: String
    public let result: String
    public let executionTime: TimeInterval
    public let success: Bool
    public let error: String?

    public init(toolCallId: String, functionName: String, arguments: String, result: String, executionTime: TimeInterval, success: Bool, error: String? = nil) {
        self.toolCallId = toolCallId
        self.functionName = functionName
        self.arguments = arguments
        self.result = result
        self.executionTime = executionTime
        self.success = success
        self.error = error
    }
}

/// Details of a single LLM call
public struct LLMExecution: Codable {
    public let model: String
    public let executionTime: TimeInterval
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let requestedTools: [String]?

    public init(
        model: String,
        executionTime: TimeInterval,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        requestedTools: [String]? = nil
    ) {
        self.model = model
        self.executionTime = executionTime
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.requestedTools = requestedTools
    }
}

/// A step in the execution timeline
public enum TimelineStep: Codable {
    case user(String) // User message content
    case llm(LLMExecution)
    case tool(ToolExecution)
    case assistant(String) // Final assistant response

    public var executionTime: TimeInterval {
        switch self {
        case .user, .assistant: 0
        case let .llm(exec): exec.executionTime
        case let .tool(exec): exec.executionTime
        }
    }
}
