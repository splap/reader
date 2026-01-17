import Foundation
import CoreML
import OSLog

/// Service for generating text embeddings using Core ML
/// Uses bge-small-en-v1.5 model (384-dimensional embeddings)
public actor EmbeddingService {
    private static let logger = Logger(subsystem: "com.splap.reader", category: "EmbeddingService")

    /// Shared instance
    public static let shared = EmbeddingService()

    /// The embedding dimension for bge-small-en-v1.5
    public static let dimension = 384

    /// Maximum input tokens (BERT-based models typically max at 512)
    public static let maxTokens = 512

    /// The loaded Core ML model
    private var model: MLModel?

    /// Whether the model failed to load (to avoid repeated attempts)
    private var modelLoadFailed = false

    /// Model configuration for performance
    private let modelConfig: MLModelConfiguration = {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine  // Use Neural Engine when available
        return config
    }()

    private init() {}

    // MARK: - Model Loading

    /// Loads the embedding model if not already loaded
    /// - Returns: True if model is available, false otherwise
    @discardableResult
    public func loadModel() async throws -> Bool {
        if model != nil { return true }
        if modelLoadFailed { return false }

        do {
            // Look for the model in the app bundle
            guard let modelURL = Bundle.main.url(forResource: "bge-small-en", withExtension: "mlmodelc") else {
                // Try .mlpackage format
                if let packageURL = Bundle.main.url(forResource: "bge-small-en", withExtension: "mlpackage") {
                    model = try await MLModel.load(contentsOf: packageURL, configuration: modelConfig)
                    Self.logger.info("Loaded embedding model from mlpackage")
                    return true
                }

                Self.logger.warning("Embedding model not found in bundle")
                modelLoadFailed = true
                return false
            }

            model = try await MLModel.load(contentsOf: modelURL, configuration: modelConfig)
            Self.logger.info("Loaded embedding model successfully")
            return true
        } catch {
            Self.logger.error("Failed to load embedding model: \(error.localizedDescription, privacy: .public)")
            modelLoadFailed = true
            throw EmbeddingError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Checks if the embedding model is available
    public func isAvailable() -> Bool {
        model != nil
    }

    // MARK: - Embedding Generation

    /// Generates an embedding for a single text
    /// - Parameter text: The text to embed
    /// - Returns: 384-dimensional embedding vector
    public func embed(text: String) async throws -> [Float] {
        if model == nil {
            try await loadModel()
        }
        guard model != nil else {
            throw EmbeddingError.modelNotAvailable
        }

        let processedText = preprocessText(text)
        return try await generateEmbedding(for: processedText)
    }

    /// Generates embeddings for multiple texts efficiently
    /// - Parameter texts: The texts to embed
    /// - Returns: Array of 384-dimensional embedding vectors
    public func embedBatch(texts: [String]) async throws -> [[Float]] {
        if model == nil {
            try await loadModel()
        }
        guard model != nil else {
            throw EmbeddingError.modelNotAvailable
        }

        Self.logger.info("Generating embeddings for \(texts.count, privacy: .public) texts")

        var embeddings: [[Float]] = []
        embeddings.reserveCapacity(texts.count)

        // Process in batches to manage memory
        let batchSize = 32
        for batchStart in stride(from: 0, to: texts.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, texts.count)
            let batch = Array(texts[batchStart..<batchEnd])

            for text in batch {
                let processedText = preprocessText(text)
                let embedding = try await generateEmbedding(for: processedText)
                embeddings.append(embedding)
            }

            // Progress logging for large batches
            if texts.count > 100 && batchEnd % 100 == 0 {
                Self.logger.debug("Embedded \(batchEnd, privacy: .public)/\(texts.count, privacy: .public) texts")
            }
        }

        Self.logger.info("Generated \(embeddings.count, privacy: .public) embeddings")
        return embeddings
    }

    // MARK: - Private Helpers

    /// Preprocesses text for embedding generation
    private func preprocessText(_ text: String) -> String {
        // BGE models work best with a query prefix for retrieval
        // For passages, we use the text as-is
        // Truncate to approximate token limit (rough estimate: 4 chars per token)
        let maxChars = Self.maxTokens * 4
        if text.count > maxChars {
            return String(text.prefix(maxChars))
        }
        return text
    }

    /// Generates embedding using the Core ML model
    private func generateEmbedding(for text: String) async throws -> [Float] {
        guard let model = model else {
            throw EmbeddingError.modelNotAvailable
        }

        // Create input for the model
        // Note: The exact input format depends on how the model was converted
        // This is a placeholder - actual implementation depends on model structure
        let input = try createModelInput(text: text)

        // Run inference
        let output = try await model.prediction(from: input)

        // Extract embedding from output
        let embedding = try extractEmbedding(from: output)

        // Normalize the embedding (L2 normalization for cosine similarity)
        return normalizeL2(embedding)
    }

    /// Creates model input from text
    /// Note: This implementation depends on the specific model conversion
    private func createModelInput(text: String) throws -> MLFeatureProvider {
        // Tokenize text into input IDs
        let tokens = tokenize(text)

        // Create input arrays
        let inputIds = tokens.inputIds
        let attentionMask = tokens.attentionMask

        // Create MLMultiArray for input_ids
        let inputIdsArray = try MLMultiArray(shape: [1, NSNumber(value: inputIds.count)], dataType: .int32)
        for (i, id) in inputIds.enumerated() {
            inputIdsArray[i] = NSNumber(value: id)
        }

        // Create MLMultiArray for attention_mask
        let attentionMaskArray = try MLMultiArray(shape: [1, NSNumber(value: attentionMask.count)], dataType: .int32)
        for (i, mask) in attentionMask.enumerated() {
            attentionMaskArray[i] = NSNumber(value: mask)
        }

        // Create feature provider
        let features: [String: MLFeatureValue] = [
            "input_ids": MLFeatureValue(multiArray: inputIdsArray),
            "attention_mask": MLFeatureValue(multiArray: attentionMaskArray)
        ]

        return try MLDictionaryFeatureProvider(dictionary: features)
    }

    /// Simple tokenizer for BERT-style models
    /// Note: For production, this should use the actual WordPiece tokenizer
    private func tokenize(_ text: String) -> (inputIds: [Int32], attentionMask: [Int32]) {
        // This is a simplified tokenizer
        // In production, we'd use the proper WordPiece vocabulary
        // For now, we use a basic word-level tokenization with padding

        let maxLength = Self.maxTokens
        let words = text.lowercased().split(separator: " ").map(String.init)

        // CLS token = 101, SEP token = 102, PAD token = 0
        var inputIds: [Int32] = [101]  // [CLS]
        var attentionMask: [Int32] = [1]

        // Add word tokens (using simple hash for now - placeholder)
        for word in words.prefix(maxLength - 2) {
            // Simple hash to token ID (placeholder - real implementation needs vocabulary)
            let tokenId = Int32(abs(word.hashValue % 30000) + 1000)
            inputIds.append(tokenId)
            attentionMask.append(1)
        }

        inputIds.append(102)  // [SEP]
        attentionMask.append(1)

        // Pad to maxLength
        while inputIds.count < maxLength {
            inputIds.append(0)  // [PAD]
            attentionMask.append(0)
        }

        return (inputIds, attentionMask)
    }

    /// Extracts embedding vector from model output
    private func extractEmbedding(from output: MLFeatureProvider) throws -> [Float] {
        // Try common output names for sentence embeddings
        let possibleNames = ["sentence_embedding", "pooler_output", "last_hidden_state", "embeddings"]

        for name in possibleNames {
            if let featureValue = output.featureValue(for: name),
               let multiArray = featureValue.multiArrayValue {
                return extractFloatArray(from: multiArray)
            }
        }

        // If we have a single output, use that
        if let featureName = output.featureNames.first,
           let featureValue = output.featureValue(for: featureName),
           let multiArray = featureValue.multiArrayValue {
            return extractFloatArray(from: multiArray)
        }

        throw EmbeddingError.invalidOutput("Could not find embedding in model output")
    }

    /// Extracts Float array from MLMultiArray
    private func extractFloatArray(from multiArray: MLMultiArray) -> [Float] {
        let count = multiArray.count
        var result = [Float](repeating: 0, count: count)

        // Handle different shapes - we want the embedding vector
        // Common shapes: [1, 384], [1, seq_len, 384]
        let shape = multiArray.shape.map { $0.intValue }

        if shape.count == 2 && shape[1] == Self.dimension {
            // Shape [1, 384] - direct embedding
            for i in 0..<Self.dimension {
                result[i] = multiArray[[0, i] as [NSNumber]].floatValue
            }
        } else if shape.count == 3 && shape[2] == Self.dimension {
            // Shape [1, seq_len, 384] - take [CLS] token embedding (first position)
            for i in 0..<Self.dimension {
                result[i] = multiArray[[0, 0, i] as [NSNumber]].floatValue
            }
        } else {
            // Fallback: take first `dimension` values
            let extractCount = min(count, Self.dimension)
            for i in 0..<extractCount {
                result[i] = multiArray[i].floatValue
            }
        }

        return Array(result.prefix(Self.dimension))
    }

    /// L2 normalizes an embedding vector
    private func normalizeL2(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}

/// Errors that can occur in EmbeddingService operations
public enum EmbeddingError: Error, LocalizedError {
    case modelNotAvailable
    case modelLoadFailed(String)
    case tokenizationFailed(String)
    case invalidOutput(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotAvailable:
            return "Embedding model is not available"
        case .modelLoadFailed(let reason):
            return "Failed to load embedding model: \(reason)"
        case .tokenizationFailed(let reason):
            return "Tokenization failed: \(reason)"
        case .invalidOutput(let reason):
            return "Invalid model output: \(reason)"
        }
    }
}
