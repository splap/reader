import XCTest
@testable import ReaderCore

final class EmbeddingServiceTests: XCTestCase {
    /// Path to the mlpackage in the source tree (for testing without bundling)
    private static var modelURL: URL? {
        // First check if model is in the test bundle (if properly configured)
        if let bundleURL = Bundle(for: EmbeddingServiceTests.self).url(forResource: "bge-small-en", withExtension: "mlpackage") {
            return bundleURL
        }

        // Fall back to source tree paths
        // #filePath gives absolute path at compile time:
        // .../reader2/Packages/ReaderKit/Tests/ReaderCoreTests/ReaderCoreTests.swift
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // -> ReaderCoreTests
            .deletingLastPathComponent() // -> Tests
            .deletingLastPathComponent() // -> ReaderKit
            .deletingLastPathComponent() // -> Packages
            .deletingLastPathComponent() // -> reader2 (project root)

        return sourceRoot.appendingPathComponent("App/Resources/bge-small-en.mlpackage")
    }

    override func setUp() async throws {
        // Reset embedding service state before each test
        await EmbeddingService.shared.reset()
    }

    func testModelLoads() async throws {
        guard let modelURL = Self.modelURL else {
            throw XCTSkip("Embedding model not found - run scripts/build first")
        }

        let service = EmbeddingService.shared
        let loaded = try await service.loadModel(from: modelURL)
        XCTAssertTrue(loaded, "Model should load successfully")
        let isAvailable = await service.isAvailable()
        XCTAssertTrue(isAvailable, "Model should be available after loading")
    }

    func testSingleEmbeddingGeneration() async throws {
        guard let modelURL = Self.modelURL else {
            throw XCTSkip("Embedding model not found - run scripts/build first")
        }

        let service = EmbeddingService.shared
        try await service.loadModel(from: modelURL)

        let text = "The quick brown fox jumps over the lazy dog."
        let embedding = try await service.embed(text: text)

        // Verify embedding dimensions
        XCTAssertEqual(embedding.count, EmbeddingService.dimension, "Embedding should be 384-dimensional")

        // Verify normalization (L2 norm should be ~1.0)
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(norm, 1.0, accuracy: 0.01, "Embedding should be L2 normalized")
    }

    func testBatchEmbeddingGeneration() async throws {
        guard let modelURL = Self.modelURL else {
            throw XCTSkip("Embedding model not found - run scripts/build first")
        }

        let service = EmbeddingService.shared
        try await service.loadModel(from: modelURL)

        let texts = [
            "The quick brown fox jumps over the lazy dog.",
            "Pack my box with five dozen liquor jugs.",
            "How vexingly quick daft zebras jump!"
        ]

        let embeddings = try await service.embedBatch(texts: texts)

        XCTAssertEqual(embeddings.count, texts.count, "Should generate one embedding per text")

        for (index, embedding) in embeddings.enumerated() {
            XCTAssertEqual(embedding.count, EmbeddingService.dimension, "Embedding \(index) should be 384-dimensional")
        }
    }

    func testEmbeddingPerformance() async throws {
        guard let modelURL = Self.modelURL else {
            throw XCTSkip("Embedding model not found - run scripts/build first")
        }

        let service = EmbeddingService.shared
        try await service.loadModel(from: modelURL)

        // Generate realistic book-like chunks (similar to what Chunker produces)
        let chunkCount = 100
        let texts = (0..<chunkCount).map { i in
            // ~800 tokens worth of text per chunk (similar to real chunks)
            String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 50)
                + "Chunk \(i) unique identifier."
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let embeddings = try await service.embedBatch(texts: texts)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertEqual(embeddings.count, chunkCount)

        let perChunkMs = (elapsed * 1000) / Double(chunkCount)
        print("Embedding performance: \(chunkCount) chunks in \(String(format: "%.2f", elapsed))s (\(String(format: "%.1f", perChunkMs))ms per chunk)")

        // Performance assertion
        // - Simulator without Neural Engine: ~150ms per chunk is expected
        // - Real device with Neural Engine: should be 10-50ms per chunk
        // Using 200ms as threshold to catch major regressions while allowing simulator overhead
        XCTAssertLessThan(perChunkMs, 200, "Embedding generation is too slow: \(perChunkMs)ms per chunk")
    }

    func testSimilarTextsHaveSimilarEmbeddings() async throws {
        guard let modelURL = Self.modelURL else {
            throw XCTSkip("Embedding model not found - run scripts/build first")
        }

        let service = EmbeddingService.shared
        try await service.loadModel(from: modelURL)

        let text1 = "The cat sat on the mat."
        let text2 = "A cat was sitting on a mat."
        let text3 = "Quantum physics describes the behavior of subatomic particles."

        let embeddings = try await service.embedBatch(texts: [text1, text2, text3])

        // Cosine similarity (embeddings are already normalized, so dot product = cosine similarity)
        func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
            zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        }

        let sim12 = cosineSimilarity(embeddings[0], embeddings[1])
        let sim13 = cosineSimilarity(embeddings[0], embeddings[2])

        print("Similarity (cat sentences): \(sim12)")
        print("Similarity (cat vs physics): \(sim13)")

        // Similar sentences should have higher similarity than unrelated ones
        XCTAssertGreaterThan(sim12, sim13, "Similar texts should have higher cosine similarity")
        XCTAssertGreaterThan(sim12, 0.5, "Similar texts should have similarity > 0.5")
    }
}
