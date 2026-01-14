import Foundation

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

    public init(role: Role, content: String, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

// MARK: - Conversation Storage

public final class ConversationStorage {
    public static let shared = ConversationStorage()

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
            print("Failed to decode conversations: \(error)")
            return []
        }
    }

    public func getConversation(id: UUID) -> Conversation? {
        return getAllConversations().first { $0.id == id }
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
            print("Failed to encode conversations: \(error)")
        }
    }
}
