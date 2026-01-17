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
