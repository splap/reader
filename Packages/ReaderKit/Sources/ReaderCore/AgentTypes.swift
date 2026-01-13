import Foundation

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

    public init(
        role: AgentRole,
        content: String?,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }

    /// Convert to dictionary for API request
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["role": role.rawValue]

        if let content = content {
            dict["content"] = content
        }

        if let toolCallId = toolCallId {
            dict["tool_call_id"] = toolCallId
        }

        if let toolCalls = toolCalls, !toolCalls.isEmpty {
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
        return [
            "id": id,
            "type": type,
            "function": [
                "name": function.name,
                "arguments": function.arguments
            ]
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
        self.type = "function"
        self.function = function
    }

    func toDictionary() -> [String: Any] {
        return [
            "type": type,
            "function": function.toDictionary()
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
        return [
            "name": name,
            "description": description,
            "parameters": parameters.toDictionary()
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
            "required": required
        ]
    }
}

/// Property schema for a single parameter
public struct PropertySchema {
    public let type: String
    public let description: String
    public let enumValues: [String]?

    public init(type: String, description: String, enumValues: [String]? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "type": type,
            "description": description
        ]
        if let enumValues = enumValues {
            dict["enum"] = enumValues
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

    public init(content: String, toolCallsMade: [String] = []) {
        self.content = content
        self.toolCallsMade = toolCallsMade
    }
}
