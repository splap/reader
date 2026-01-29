import Foundation

// MARK: - Configuration

public enum OpenRouterConfig {
    /// Model definition with pricing (costs per million tokens)
    public struct Model {
        public let id: String
        public let name: String
        public let inputCost: Double // $ per 1M tokens
        public let outputCost: Double // $ per 1M tokens
        public let contextLength: Int // max tokens
    }

    /// Available models for selection (pricing from OpenRouter API)
    public static let availableModels: [Model] = [
        Model(id: "anthropic/claude-haiku-4.5", name: "Claude Haiku 4.5", inputCost: 1.00, outputCost: 5.00, contextLength: 200_000),
        Model(id: "google/gemini-2.5-flash", name: "Gemini 2.5 Flash", inputCost: 0.30, outputCost: 2.50, contextLength: 1_048_576),
        Model(id: "google/gemini-2.5-flash-lite", name: "Gemini 2.5 Flash Lite", inputCost: 0.10, outputCost: 0.40, contextLength: 1_048_576),
        Model(id: "google/gemini-3-flash-preview", name: "Gemini 3 Flash", inputCost: 0.50, outputCost: 3.00, contextLength: 1_048_576),
        Model(id: "moonshotai/kimi-k2.5", name: "Kimi K2.5", inputCost: 0.60, outputCost: 3.00, contextLength: 262_144),
        Model(id: "openai/gpt-4.1-mini", name: "GPT-4.1 Mini", inputCost: 0.40, outputCost: 1.60, contextLength: 1_047_576),
        Model(id: "openai/gpt-4.1-nano", name: "GPT-4.1 Nano", inputCost: 0.10, outputCost: 0.40, contextLength: 1_047_576),
        Model(id: "openai/gpt-5-mini", name: "GPT-5 Mini", inputCost: 0.25, outputCost: 2.00, contextLength: 400_000),
        Model(id: "x-ai/grok-4.1-fast", name: "Grok 4.1 Fast", inputCost: 0.20, outputCost: 0.50, contextLength: 2_000_000),
    ]

    /// Get the selected model from UserDefaults (set via Settings UI)
    /// Default: google/gemini-3-flash-preview
    public static var model: String {
        get {
            UserDefaults.standard.string(forKey: "OpenRouterModel") ?? "google/gemini-3-flash-preview"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "OpenRouterModel")
        }
    }

    /// Your OpenRouter API key (set via Settings UI)
    public static var apiKey: String? {
        UserDefaults.standard.string(forKey: "OpenRouterAPIKey")
    }

    /// Get display name for current model
    public static var modelDisplayName: String {
        availableModels.first { $0.id == model }?.name ?? model
    }

    /// Get the current model definition
    public static var currentModel: Model? {
        availableModels.first { $0.id == model }
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
            "OpenRouter API key not found. Please set it in UserDefaults with key 'OpenRouterAPIKey'"
        case .invalidResponse:
            "Invalid response from OpenRouter API"
        case let .httpError(statusCode, message):
            "HTTP \(statusCode): \(message)"
        }
    }
}
