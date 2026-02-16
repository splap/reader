import Foundation
import OSLog

// MARK: - Turn Model

/// A turn represents a single user prompt and the assistant's response as one unit.
/// This is the primary data model for the chat UI.
public struct Turn: Identifiable {
    public let id: UUID
    public let prompt: String
    public var answer: String
    public var state: TurnState
    public var context: String?
    public var trace: AgentExecutionTrace?

    public init(
        id: UUID = UUID(),
        prompt: String,
        answer: String = "",
        state: TurnState = .pending,
        context: String? = nil,
        trace: AgentExecutionTrace? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.answer = answer
        self.state = state
        self.context = context
        self.trace = trace
    }
}

/// The state of a turn's response
public enum TurnState {
    case pending // Waiting for response
    case streaming // Typewriter in progress
    case complete // Done
}

// MARK: - Turn <-> StoredMessage Conversion

public extension Turn {
    /// Creates a Turn from stored messages (for loading conversations)
    static func from(userMessage: StoredMessage, assistantMessage: StoredMessage?) -> Turn {
        Turn(
            prompt: userMessage.content,
            answer: assistantMessage?.content ?? "",
            state: assistantMessage != nil ? .complete : .pending,
            trace: assistantMessage?.executionTrace
        )
    }

    /// Converts this turn to stored messages (for saving conversations)
    func toStoredMessages() -> [StoredMessage] {
        var messages: [StoredMessage] = []
        messages.append(StoredMessage(role: .user, content: prompt))
        if !answer.isEmpty {
            messages.append(StoredMessage(role: .assistant, content: answer, executionTrace: trace))
        }
        return messages
    }
}

/// Converts an array of StoredMessages to Turns
public func turnsFromMessages(_ messages: [StoredMessage]) -> [Turn] {
    var turns: [Turn] = []
    var i = 0

    while i < messages.count {
        let msg = messages[i]

        if msg.role == .user {
            // Look ahead for assistant response
            let nextIndex = i + 1
            let assistantMsg = nextIndex < messages.count && messages[nextIndex].role == .assistant
                ? messages[nextIndex]
                : nil

            turns.append(Turn.from(userMessage: msg, assistantMessage: assistantMsg))

            // Skip assistant message if we consumed it
            i += assistantMsg != nil ? 2 : 1
        } else {
            // Skip system messages or orphaned assistant messages
            i += 1
        }
    }

    return turns
}

/// Converts an array of Turns to StoredMessages
public func messagesFromTurns(_ turns: [Turn]) -> [StoredMessage] {
    turns.flatMap { $0.toStoredMessages() }
}

// MARK: - Conversation Model

public struct Conversation: Codable, Identifiable {
    public let id: UUID
    public var title: String
    public let bookTitle: String
    public let bookAuthor: String?
    public var messages: [StoredMessage]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        bookTitle: String,
        bookAuthor: String?,
        messages: [StoredMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct StoredMessage: Codable {
    public enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    public let role: Role
    public let content: String
    public let timestamp: Date
    public let executionTrace: AgentExecutionTrace?

    public init(role: Role, content: String, timestamp: Date = Date(), executionTrace: AgentExecutionTrace? = nil) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.executionTrace = executionTrace
    }
}

// MARK: - Conversation Storage

public final class ConversationStorage {
    public static let shared = ConversationStorage()

    private static let logger = Log.logger(category: "conversations")
    private let userDefaults: UserDefaults
    private let key = "reader.conversations"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - CRUD Operations

    public func getAllConversations() -> [Conversation] {
        guard let data = userDefaults.data(forKey: key) else {
            return []
        }

        do {
            let conversations = try JSONDecoder().decode([Conversation].self, from: data)
            return conversations.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            Self.logger.error("Failed to decode conversations: \(error.localizedDescription)")
            return []
        }
    }

    public func getConversation(id: UUID) -> Conversation? {
        getAllConversations().first { $0.id == id }
    }

    public func saveConversation(_ conversation: Conversation) {
        var conversations = getAllConversations()

        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.append(conversation)
        }

        save(conversations)
    }

    public func deleteConversation(id: UUID) {
        var conversations = getAllConversations()
        conversations.removeAll { $0.id == id }
        save(conversations)
    }

    public func deleteAllConversations() {
        userDefaults.removeObject(forKey: key)
    }

    // MARK: - Private

    private func save(_ conversations: [Conversation]) {
        do {
            let data = try JSONEncoder().encode(conversations)
            userDefaults.set(data, forKey: key)
        } catch {
            Self.logger.error("Failed to encode conversations: \(error.localizedDescription)")
        }
    }
}
