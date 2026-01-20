import Foundation

// MARK: - Configuration
public enum OpenRouterConfig {
    /// Model definition with pricing (costs per million tokens)
    public struct Model {
        public let id: String
        public let name: String
        public let inputCost: Double   // $ per 1M tokens
        public let outputCost: Double  // $ per 1M tokens
    }

    /// Available models for selection
    public static let availableModels: [Model] = [
        Model(id: "anthropic/claude-haiku-4.5", name: "Claude Haiku 4.5", inputCost: 1.00, outputCost: 5.00),
        Model(id: "google/gemini-2.5-flash", name: "Gemini 2.5 Flash", inputCost: 0.30, outputCost: 2.50),
        Model(id: "google/gemini-2.5-flash-lite", name: "Gemini 2.5 Flash Lite", inputCost: 0.10, outputCost: 0.40),
        Model(id: "google/gemini-3-flash-preview", name: "Gemini 3 Flash", inputCost: 0.50, outputCost: 3.00),
        Model(id: "openai/gpt-4.1-mini", name: "GPT-4.1 Mini", inputCost: 2.00, outputCost: 8.00),
        Model(id: "openai/gpt-4.1-nano", name: "GPT-4.1 Nano", inputCost: 0.10, outputCost: 0.40),
        Model(id: "x-ai/grok-4.1-fast", name: "Grok 4.1 Fast", inputCost: 0.20, outputCost: 0.50)
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

    /// Get the current model definition
    public static var currentModel: Model? {
        return availableModels.first { $0.id == model }
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
