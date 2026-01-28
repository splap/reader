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
    /// - Parameter modelURL: Optional URL to load model from (for testing). If nil, searches Bundle.main.
    /// - Returns: True if model is available, false otherwise
    @discardableResult
    public func loadModel(from modelURL: URL? = nil) async throws -> Bool {
        if model != nil { return true }
        if modelLoadFailed { return false }

        do {
            let loadURL: URL

            if let url = modelURL {
                // Explicit URL provided (testing) - compile to stable path if needed
                loadURL = try await stableModelURL(for: url)
            } else if let bundleURL = Bundle.main.url(forResource: "bge-small-en", withExtension: "mlmodelc") {
                // Pre-compiled in bundle - copy to stable path so CoreML cache doesn't
                // create a new 128MB entry every reinstall
                loadURL = try stableCopy(of: bundleURL)
            } else if let packageURL = Bundle.main.url(forResource: "bge-small-en", withExtension: "mlpackage") {
                // Uncompiled in bundle - compile to stable path
                loadURL = try await stableModelURL(for: packageURL)
            } else {
                Self.logger.warning("Embedding model not found in bundle")
                modelLoadFailed = true
                return false
            }

            model = try await MLModel.load(contentsOf: loadURL, configuration: modelConfig)
            Self.logger.info("Loaded embedding model from \(loadURL.path)")
            return true
        } catch {
            Self.logger.error("Failed to load embedding model: \(error.localizedDescription)")
            modelLoadFailed = true
            throw EmbeddingError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Directory for stable model storage. Using a fixed path prevents CoreML's
    /// internal e5bundlecache from creating a new 128MB optimized copy every app reinstall.
    private static var stableModelsDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("models", isDirectory: true)
    }

    /// Copies a pre-compiled .mlmodelc to a stable path outside the app container.
    private func stableCopy(of bundleURL: URL) throws -> URL {
        let fm = FileManager.default
        let dest = Self.stableModelsDir.appendingPathComponent(bundleURL.lastPathComponent)

        if fm.fileExists(atPath: dest.path) {
            return dest
        }

        try fm.createDirectory(at: Self.stableModelsDir, withIntermediateDirectories: true)
        try fm.copyItem(at: bundleURL, to: dest)
        Self.logger.info("Copied model to stable path: \(dest.path)")
        return dest
    }

    /// Returns a stable URL for a model, compiling from .mlpackage if needed.
    private func stableModelURL(for url: URL) async throws -> URL {
        if url.pathExtension == "mlmodelc" {
            return try stableCopy(of: url)
        }

        let fm = FileManager.default
        let dest = Self.stableModelsDir.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent).mlmodelc")

        if fm.fileExists(atPath: dest.path) {
            Self.logger.info("Using cached compiled model at \(dest.path)")
            return dest
        }

        try fm.createDirectory(at: Self.stableModelsDir, withIntermediateDirectories: true)

        Self.logger.info("Compiling model at \(url.path)")
        let tempCompiledURL = try await MLModel.compileModel(at: url)
        try fm.moveItem(at: tempCompiledURL, to: dest)
        Self.logger.info("Model compiled to stable path: \(dest.path)")
        return dest
    }

    /// Resets the model state (for testing)
    public func reset() {
        model = nil
        modelLoadFailed = false
    }

    /// Checks if the embedding model is available (must be called from actor context)
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

    /// Generates embeddings for multiple texts efficiently using concurrent processing
    /// - Parameter texts: The texts to embed
    /// - Returns: Array of 384-dimensional embedding vectors
    public func embedBatch(texts: [String]) async throws -> [[Float]] {
        if model == nil {
            try await loadModel()
        }
        guard let model = model else {
            throw EmbeddingError.modelNotAvailable
        }

        Self.logger.info("Generating embeddings for \(texts.count) texts")

        // Pre-tokenize all texts in parallel
        let tokenizedInputs: [(inputIds: [Int32], attentionMask: [Int32])] = await withTaskGroup(of: (Int, (inputIds: [Int32], attentionMask: [Int32])).self) { group in
            for (index, text) in texts.enumerated() {
                group.addTask {
                    let processedText = self.preprocessText(text)
                    return (index, self.tokenize(processedText))
                }
            }

            var results = [(inputIds: [Int32], attentionMask: [Int32])](repeating: ([], []), count: texts.count)
            for await (index, tokens) in group {
                results[index] = tokens
            }
            return results
        }

        // Process embeddings concurrently using TaskGroup
        // CoreML model inference is thread-safe
        let concurrency = min(8, ProcessInfo.processInfo.activeProcessorCount)

        return try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            var results = [[Float]](repeating: [], count: texts.count)

            // Add tasks in batches to control concurrency
            var nextIndex = 0

            // Seed initial batch of tasks
            for _ in 0..<min(concurrency, texts.count) {
                let index = nextIndex
                let tokens = tokenizedInputs[index]
                nextIndex += 1

                group.addTask {
                    let embedding = try await self.generateEmbeddingFromTokens(
                        inputIds: tokens.inputIds,
                        attentionMask: tokens.attentionMask,
                        model: model
                    )
                    return (index, embedding)
                }
            }

            // Process results and add new tasks
            for try await (index, embedding) in group {
                results[index] = embedding

                // Add next task if available
                if nextIndex < texts.count {
                    let index = nextIndex
                    let tokens = tokenizedInputs[index]
                    nextIndex += 1

                    group.addTask {
                        let embedding = try await self.generateEmbeddingFromTokens(
                            inputIds: tokens.inputIds,
                            attentionMask: tokens.attentionMask,
                            model: model
                        )
                        return (index, embedding)
                    }
                }

                // Progress logging for large batches
                let completed = results.filter { !$0.isEmpty }.count
                if texts.count > 100 && completed % 100 == 0 && completed > 0 {
                    Self.logger.debug("Embedded \(completed)/\(texts.count) texts")
                }
            }

            Self.logger.info("Generated \(results.count) embeddings")
            return results
        }
    }

    /// Generate embedding from pre-tokenized input (for concurrent processing)
    private nonisolated func generateEmbeddingFromTokens(
        inputIds: [Int32],
        attentionMask: [Int32],
        model: MLModel
    ) async throws -> [Float] {
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
        let input = try MLDictionaryFeatureProvider(dictionary: features)

        // Run inference (CoreML is thread-safe)
        let output = try await model.prediction(from: input)

        // Extract and normalize embedding
        let embedding = try extractEmbeddingSync(from: output)
        return normalizeL2(embedding)
    }

    /// Extract embedding synchronously (for use in nonisolated context)
    private nonisolated func extractEmbeddingSync(from output: MLFeatureProvider) throws -> [Float] {
        // Try common output names for sentence embeddings
        let possibleNames = ["sentence_embedding", "pooler_output", "last_hidden_state", "embeddings"]

        for name in possibleNames {
            if let featureValue = output.featureValue(for: name),
               let multiArray = featureValue.multiArrayValue {
                return extractFloatArraySync(from: multiArray)
            }
        }

        // If we have a single output, use that
        if let featureName = output.featureNames.first,
           let featureValue = output.featureValue(for: featureName),
           let multiArray = featureValue.multiArrayValue {
            return extractFloatArraySync(from: multiArray)
        }

        throw EmbeddingError.invalidOutput("Could not find embedding in model output")
    }

    /// Extract Float array synchronously
    private nonisolated func extractFloatArraySync(from multiArray: MLMultiArray) -> [Float] {
        let count = multiArray.count
        var result = [Float](repeating: 0, count: count)

        let shape = multiArray.shape.map { $0.intValue }

        if shape.count == 2 && shape[1] == Self.dimension {
            // Shape [1, 384] - direct embedding
            for i in 0..<Self.dimension {
                result[i] = multiArray[[0, i] as [NSNumber]].floatValue
            }
        } else if shape.count == 3 && shape[2] == Self.dimension {
            // Shape [1, seq_len, 384] - take [CLS] token embedding
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

    // MARK: - Private Helpers

    /// Preprocesses text for embedding generation (pure function)
    private nonisolated func preprocessText(_ text: String) -> String {
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

    /// Tokenize text using proper WordPiece tokenizer (pure function)
    private nonisolated func tokenize(_ text: String) -> (inputIds: [Int32], attentionMask: [Int32]) {
        // Use proper BERT tokenizer if available
        if let tokenizer = BertTokenizer.shared {
            return tokenizer.encode(text, maxLength: Self.maxTokens)
        }

        // Fallback to basic tokenization if tokenizer not loaded
        let maxLength = Self.maxTokens
        let words = text.lowercased().split(separator: " ").map(String.init)

        // CLS token = 101, SEP token = 102, PAD token = 0
        var inputIds: [Int32] = [101]  // [CLS]
        var attentionMask: [Int32] = [1]

        // Add word tokens (using [UNK] = 100 for unknown words)
        for _ in words.prefix(maxLength - 2) {
            inputIds.append(100)  // [UNK]
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

    /// L2 normalizes an embedding vector (pure function, safe to call from any context)
    private nonisolated func normalizeL2(_ vector: [Float]) -> [Float] {
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
