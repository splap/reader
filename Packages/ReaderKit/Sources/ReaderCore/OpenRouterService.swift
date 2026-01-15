import Foundation

// MARK: - Configuration
public enum OpenRouterConfig {
    /// Available models for selection
    public static let availableModels: [(id: String, name: String)] = [
        ("openai/gpt-4.1-nano", "GPT-4.1 Nano"),
        ("openai/gpt-4.1-mini", "GPT-4.1 Mini"),
        ("openai/gpt-4.1", "GPT-4.1"),
        ("anthropic/claude-3.5-haiku", "Claude 3.5 Haiku"),
        ("anthropic/claude-sonnet-4", "Claude Sonnet 4"),
        ("google/gemini-2.5-flash-lite", "Gemini 2.5 Flash Lite"),
        ("google/gemini-2.5-pro", "Gemini 2.5 Pro")
    ]

    /// Get the selected model from UserDefaults (set via Settings UI)
    /// Default: openai/gpt-4.1-nano
    public static var model: String {
        get {
            return UserDefaults.standard.string(forKey: "OpenRouterModel") ?? "openai/gpt-4.1-nano"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "OpenRouterModel")
        }
    }

    /// Your OpenRouter API key (set via Settings UI)
    public static var apiKey: String? {
        return UserDefaults.standard.string(forKey: "OpenRouterAPIKey")
    }

    /// Get display name for current model
    public static var modelDisplayName: String {
        return availableModels.first { $0.id == model }?.name ?? model
    }
}

// MARK: - Service
public actor OpenRouterService {
    public init() {}

    public func sendMessage(
        selection: SelectionPayload,
        userQuestion: String? = nil
    ) async throws -> String {
        guard let apiKey = OpenRouterConfig.apiKey, !apiKey.isEmpty else {
            throw OpenRouterError.missingAPIKey
        }

        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // Build book metadata string
        var bookInfo = ""
        if let title = selection.bookTitle {
            bookInfo += "Book: \(title)"
            if let author = selection.bookAuthor {
                bookInfo += " by \(author)"
            }
            bookInfo += "\n"
        }
        if let chapter = selection.chapterTitle {
            bookInfo += "Chapter: \(chapter)\n"
        }

        // Build the prompt
        let systemPrompt = """
        You are a helpful reading assistant. The user has selected some text from a book and wants help understanding it.

        Be terse and concise in your responses. Get straight to the point.

        \(bookInfo.isEmpty ? "" : bookInfo)
        Surrounding context from the book:
        \(selection.contextText)
        """

        let userPrompt: String
        if let question = userQuestion, !question.isEmpty {
            userPrompt = """
            Selected text: "\(selection.selectedText)"

            Question: \(question)
            """
        } else {
            userPrompt = """
            Please explain or provide insights about this selected text:

            "\(selection.selectedText)"
            """
        }

        let body: [String: Any] = [
            "model": OpenRouterConfig.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
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

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenRouterError.invalidResponse
        }

        return content
    }
}

// MARK: - Errors
public enum OpenRouterError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpError(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenRouter API key not found. Please set it in UserDefaults with key 'OpenRouterAPIKey'"
        case .invalidResponse:
            return "Invalid response from OpenRouter API"
        case .httpError(let statusCode, let message):
            return "HTTP \(statusCode): \(message)"
        }
    }
}
