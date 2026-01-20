import Foundation
import OSLog

/// Clusters chapters into thematic groups using agglomerative hierarchical clustering
public struct ThemeClusterer {
    private static let logger = Logger(subsystem: "com.splap.reader", category: "ThemeClusterer")

    /// Configuration for theme clustering
    public struct Config {
        /// Target number of theme clusters (soft target)
        public var targetThemes: Int = 50

        /// Minimum themes (hard floor)
        public var minThemes: Int = 25

        /// Maximum themes (hard cap from plan spec)
        public var maxThemes: Int = 200

        /// Distance threshold for stopping clustering
        /// Lower = more granular themes, Higher = broader themes
        public var distanceThreshold: Double = 0.7

        /// Weight for semantic similarity (vs TF-IDF)
        public var semanticWeight: Double = 0.7

        /// Keywords per theme
        public var keywordsPerTheme: Int = 10

        public init() {}
    }

    // MARK: - Public API

    /// Clusters chapters into themes
    /// - Parameters:
    ///   - chapters: The chapters to cluster
    ///   - tfidfResult: TF-IDF analysis results
    ///   - chapterEmbeddings: Optional per-chapter semantic centroids
    ///   - config: Clustering configuration
    /// - Returns: Array of theme clusters
    public static func cluster(
        chapters: [Chapter],
        tfidfResult: TFIDFAnalyzer.AnalysisResult,
        chapterEmbeddings: [String: [Float]]? = nil,
        config: Config = Config()
    ) -> [Theme] {
        guard chapters.count >= 2 else {
            // Single chapter = single theme
            if let chapter = chapters.first {
                return [createSingleChapterTheme(chapter: chapter, tfidfResult: tfidfResult)]
            }
            return []
        }

        logger.info("Clustering \(chapters.count) chapters into themes")

        // Step 1: Build feature vectors for each chapter
        let vocabulary = TFIDFAnalyzer.buildVocabulary(from: tfidfResult, maxTerms: 100)
        var chapterVectors: [String: ChapterVector] = [:]

        for chapter in chapters {
            let tfidfVector = TFIDFAnalyzer.vectorize(
                chapterId: chapter.id,
                result: tfidfResult,
                vocabulary: vocabulary
            )

            let semanticVector = chapterEmbeddings?[chapter.id]

            chapterVectors[chapter.id] = ChapterVector(
                chapterId: chapter.id,
                tfidfVector: tfidfVector,
                semanticVector: semanticVector
            )
        }

        // Step 2: Compute similarity matrix
        let chapterIds = chapters.map(\.id)
        let similarityMatrix = computeSimilarityMatrix(
            chapterIds: chapterIds,
            vectors: chapterVectors,
            semanticWeight: chapterEmbeddings != nil ? config.semanticWeight : 0.0
        )

        // Step 3: Agglomerative clustering
        let clusters = agglomerativeClustering(
            chapterIds: chapterIds,
            similarityMatrix: similarityMatrix,
            config: config
        )

        // Step 4: Create theme objects
        var themes: [Theme] = []

        for (index, clusterChapterIds) in clusters.enumerated() {
            let theme = createTheme(
                id: "theme_\(index)",
                chapterIds: clusterChapterIds,
                tfidfResult: tfidfResult,
                vocabulary: vocabulary,
                config: config
            )
            themes.append(theme)
        }

        // Sort by number of chapters (larger themes first)
        themes.sort { $0.chapterIds.count > $1.chapterIds.count }

        logger.info("Created \(themes.count) theme clusters")

        return themes
    }

    // MARK: - Internal Types

    /// Feature vector for a chapter
    private struct ChapterVector {
        let chapterId: String
        let tfidfVector: [Int: Double]  // Sparse TF-IDF vector
        let semanticVector: [Float]?     // Dense semantic embedding
    }

    // MARK: - Similarity Computation

    /// Computes pairwise similarity matrix between chapters
    private static func computeSimilarityMatrix(
        chapterIds: [String],
        vectors: [String: ChapterVector],
        semanticWeight: Double
    ) -> [[Double]] {
        let n = chapterIds.count
        var matrix = [[Double]](repeating: [Double](repeating: 0.0, count: n), count: n)

        for i in 0..<n {
            for j in i..<n {
                if i == j {
                    matrix[i][j] = 1.0
                } else {
                    guard let vec1 = vectors[chapterIds[i]],
                          let vec2 = vectors[chapterIds[j]] else {
                        continue
                    }

                    let similarity = computeSimilarity(vec1, vec2, semanticWeight: semanticWeight)
                    matrix[i][j] = similarity
                    matrix[j][i] = similarity
                }
            }
        }

        return matrix
    }

    /// Computes similarity between two chapter vectors
    private static func computeSimilarity(
        _ vec1: ChapterVector,
        _ vec2: ChapterVector,
        semanticWeight: Double
    ) -> Double {
        let tfidfWeight = 1.0 - semanticWeight

        // TF-IDF similarity (sparse cosine)
        let tfidfSim = sparseCosine(vec1.tfidfVector, vec2.tfidfVector)

        // Semantic similarity (dense cosine)
        var semanticSim = 0.0
        if let sem1 = vec1.semanticVector, let sem2 = vec2.semanticVector {
            semanticSim = denseCosine(sem1, sem2)
        }

        // Weighted blend
        if semanticWeight > 0 && vec1.semanticVector != nil {
            return semanticWeight * semanticSim + tfidfWeight * tfidfSim
        } else {
            return tfidfSim
        }
    }

    /// Cosine similarity for sparse vectors
    private static func sparseCosine(_ v1: [Int: Double], _ v2: [Int: Double]) -> Double {
        guard !v1.isEmpty && !v2.isEmpty else { return 0.0 }

        var dotProduct = 0.0
        var norm1 = 0.0
        var norm2 = 0.0

        // Compute dot product over shared keys
        let allKeys = Set(v1.keys).union(v2.keys)

        for key in allKeys {
            let val1 = v1[key] ?? 0.0
            let val2 = v2[key] ?? 0.0

            dotProduct += val1 * val2
            norm1 += val1 * val1
            norm2 += val2 * val2
        }

        let denominator = sqrt(norm1) * sqrt(norm2)
        return denominator > 0 ? dotProduct / denominator : 0.0
    }

    /// Cosine similarity for dense vectors
    private static func denseCosine(_ v1: [Float], _ v2: [Float]) -> Double {
        guard v1.count == v2.count && !v1.isEmpty else { return 0.0 }

        var dotProduct: Float = 0.0
        var norm1: Float = 0.0
        var norm2: Float = 0.0

        for i in 0..<v1.count {
            dotProduct += v1[i] * v2[i]
            norm1 += v1[i] * v1[i]
            norm2 += v2[i] * v2[i]
        }

        let denominator = sqrt(norm1) * sqrt(norm2)
        return denominator > 0 ? Double(dotProduct / denominator) : 0.0
    }

    // MARK: - Agglomerative Clustering

    /// Performs agglomerative hierarchical clustering
    private static func agglomerativeClustering(
        chapterIds: [String],
        similarityMatrix: [[Double]],
        config: Config
    ) -> [[String]] {
        let n = chapterIds.count

        // Initialize: each chapter is its own cluster
        var clusters: [[Int]] = (0..<n).map { [$0] }
        var clusterSimilarity = similarityMatrix

        // Merge until we reach target or threshold
        while clusters.count > config.minThemes {
            // Find most similar pair
            var bestSim = -1.0
            var bestI = -1
            var bestJ = -1

            for i in 0..<clusters.count {
                for j in (i + 1)..<clusters.count {
                    if clusterSimilarity[i][j] > bestSim {
                        bestSim = clusterSimilarity[i][j]
                        bestI = i
                        bestJ = j
                    }
                }
            }

            // Check stopping conditions
            let distance = 1.0 - bestSim
            if distance > config.distanceThreshold && clusters.count <= config.targetThemes {
                break
            }

            if clusters.count <= config.minThemes {
                break
            }

            // Merge clusters i and j
            let merged = clusters[bestI] + clusters[bestJ]

            // Update clusters list
            var newClusters = clusters
            newClusters.remove(at: max(bestI, bestJ))
            newClusters.remove(at: min(bestI, bestJ))
            newClusters.append(merged)

            // Update similarity matrix (average linkage)
            var newSimilarity = [[Double]](repeating: [Double](repeating: 0.0, count: newClusters.count), count: newClusters.count)

            // Map old indices to new
            var oldToNew: [Int: Int] = [:]
            var newIdx = 0
            for i in 0..<clusters.count {
                if i != bestI && i != bestJ {
                    oldToNew[i] = newIdx
                    newIdx += 1
                }
            }

            // Copy existing similarities
            for i in 0..<clusters.count {
                guard let ni = oldToNew[i] else { continue }
                for j in 0..<clusters.count {
                    guard let nj = oldToNew[j] else { continue }
                    newSimilarity[ni][nj] = clusterSimilarity[i][j]
                }
            }

            // Compute similarities for merged cluster (average linkage)
            let mergedIdx = newClusters.count - 1
            for i in 0..<clusters.count {
                guard let ni = oldToNew[i] else { continue }

                // Average similarity to merged cluster
                let simToI = (clusterSimilarity[bestI][i] * Double(clusters[bestI].count) +
                             clusterSimilarity[bestJ][i] * Double(clusters[bestJ].count)) /
                             Double(merged.count)

                newSimilarity[ni][mergedIdx] = simToI
                newSimilarity[mergedIdx][ni] = simToI
            }
            newSimilarity[mergedIdx][mergedIdx] = 1.0

            clusters = newClusters
            clusterSimilarity = newSimilarity
        }

        // Convert indices back to chapter IDs
        return clusters.map { indices in
            indices.map { chapterIds[$0] }
        }
    }

    // MARK: - Theme Creation

    /// Creates a theme from a cluster of chapters
    private static func createTheme(
        id: String,
        chapterIds: [String],
        tfidfResult: TFIDFAnalyzer.AnalysisResult,
        vocabulary: [String],
        config: Config
    ) -> Theme {
        // Aggregate keywords across cluster
        var keywordScores: [String: Double] = [:]

        for chapterId in chapterIds {
            if let keywords = tfidfResult.keywordsByChapter[chapterId] {
                for keyword in keywords {
                    keywordScores[keyword.term, default: 0] += keyword.tfidf
                }
            }
        }

        // Sort and select top keywords
        let sortedKeywords = keywordScores.sorted { $0.value > $1.value }
        let topKeywords = sortedKeywords.prefix(config.keywordsPerTheme).map(\.key)

        // Generate label from top keywords
        let label = generateThemeLabel(keywords: topKeywords)

        // Compute cohesion (average intra-cluster similarity)
        // Simplified: use number of chapters as proxy
        let cohesion = min(1.0, Double(chapterIds.count) / 5.0)

        return Theme(
            id: id,
            label: label,
            keywords: topKeywords,
            chapterIds: chapterIds,
            cohesion: cohesion
        )
    }

    /// Creates a theme for a single chapter
    private static func createSingleChapterTheme(
        chapter: Chapter,
        tfidfResult: TFIDFAnalyzer.AnalysisResult
    ) -> Theme {
        let keywords = tfidfResult.keywordsByChapter[chapter.id]?.prefix(10).map(\.term) ?? []
        let label = generateThemeLabel(keywords: Array(keywords))

        return Theme(
            id: "theme_0",
            label: label,
            keywords: Array(keywords),
            chapterIds: [chapter.id],
            cohesion: 1.0
        )
    }

    /// Generates a human-readable theme label from keywords
    private static func generateThemeLabel(keywords: [String]) -> String {
        guard !keywords.isEmpty else { return "Untitled Theme" }

        // Take top 2-3 keywords and capitalize
        let labelWords = keywords.prefix(3).map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }

        return labelWords.joined(separator: " & ")
    }
}
