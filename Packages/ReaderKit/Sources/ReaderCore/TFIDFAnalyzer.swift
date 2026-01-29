import Foundation
import OSLog

/// Analyzes text using TF-IDF to extract important keywords per chapter
public enum TFIDFAnalyzer {
    private static let logger = Logger(subsystem: "com.splap.reader", category: "TFIDFAnalyzer")

    /// A keyword with its TF-IDF score and supporting metrics
    public struct KeywordScore: Codable, Equatable {
        /// The keyword term (lowercase)
        public let term: String

        /// TF-IDF score (higher = more important)
        public let tfidf: Double

        /// Term frequency in this chapter
        public let tf: Int

        /// Document frequency (chapters containing this term)
        public let df: Int

        public init(term: String, tfidf: Double, tf: Int, df: Int) {
            self.term = term
            self.tfidf = tfidf
            self.tf = tf
            self.df = df
        }
    }

    /// Results of TF-IDF analysis for a book
    public struct AnalysisResult {
        /// Keywords per chapter, keyed by chapter ID
        public let keywordsByChapter: [String: [KeywordScore]]

        /// Global IDF values for all terms
        public let globalIDF: [String: Double]

        /// Total number of chapters analyzed
        public let chapterCount: Int
    }

    /// Maximum keywords to return per chapter
    public static let maxKeywordsPerChapter = 50

    /// Minimum term frequency to consider
    public static let minTermFrequency = 2

    /// Minimum term length
    public static let minTermLength = 3

    // MARK: - Public API

    /// Analyzes chapters to extract TF-IDF keywords
    /// - Parameter chapters: The chapters to analyze
    /// - Returns: Analysis result with keywords per chapter
    public static func analyze(chapters: [Chapter]) -> AnalysisResult {
        guard !chapters.isEmpty else {
            return AnalysisResult(keywordsByChapter: [:], globalIDF: [:], chapterCount: 0)
        }

        logger.info("Analyzing \(chapters.count) chapters for TF-IDF keywords")

        // Step 1: Tokenize each chapter and compute term frequencies
        var chapterTermFreqs: [String: [String: Int]] = [:]
        var documentFrequency: [String: Int] = [:] // How many chapters contain each term

        for chapter in chapters {
            let text = extractText(from: chapter)
            let tokens = tokenize(text)
            let termFreq = computeTermFrequency(tokens)

            chapterTermFreqs[chapter.id] = termFreq

            // Update document frequency
            for term in termFreq.keys {
                documentFrequency[term, default: 0] += 1
            }
        }

        let totalChapters = chapters.count

        // Step 2: Compute IDF for each term
        var idf: [String: Double] = [:]
        for (term, df) in documentFrequency {
            // IDF = log(N / df) where N = total documents, df = docs containing term
            idf[term] = log(Double(totalChapters) / Double(df))
        }

        // Step 3: Compute TF-IDF for each chapter and extract top keywords
        var keywordsByChapter: [String: [KeywordScore]] = [:]

        for chapter in chapters {
            guard let termFreq = chapterTermFreqs[chapter.id] else { continue }

            var keywords: [KeywordScore] = []

            for (term, tf) in termFreq {
                // Skip low-frequency and short terms
                guard tf >= minTermFrequency, term.count >= minTermLength else { continue }

                // Skip stopwords
                guard !stopwords.contains(term) else { continue }

                let termIdf = idf[term] ?? 0
                let tfidfScore = Double(tf) * termIdf
                let df = documentFrequency[term] ?? 1

                keywords.append(KeywordScore(term: term, tfidf: tfidfScore, tf: tf, df: df))
            }

            // Sort by TF-IDF score and take top N
            keywords.sort { $0.tfidf > $1.tfidf }
            keywordsByChapter[chapter.id] = Array(keywords.prefix(maxKeywordsPerChapter))
        }

        logger.info("TF-IDF analysis complete: \(idf.count) unique terms")

        return AnalysisResult(
            keywordsByChapter: keywordsByChapter,
            globalIDF: idf,
            chapterCount: totalChapters
        )
    }

    /// Computes a sparse TF-IDF vector for a chapter
    /// - Parameters:
    ///   - chapterId: The chapter to vectorize
    ///   - result: The analysis result containing IDF values
    ///   - vocabulary: The vocabulary to use (top N terms by IDF)
    /// - Returns: Sparse vector as dictionary of term index to TF-IDF value
    public static func vectorize(
        chapterId: String,
        result: AnalysisResult,
        vocabulary: [String]
    ) -> [Int: Double] {
        guard let keywords = result.keywordsByChapter[chapterId] else {
            return [:]
        }

        let termToIndex = Dictionary(uniqueKeysWithValues: vocabulary.enumerated().map { ($1, $0) })

        var vector: [Int: Double] = [:]
        for keyword in keywords {
            if let index = termToIndex[keyword.term] {
                vector[index] = keyword.tfidf
            }
        }

        return vector
    }

    /// Creates a vocabulary from top terms across all chapters
    /// - Parameters:
    ///   - result: The analysis result
    ///   - maxTerms: Maximum vocabulary size
    /// - Returns: Array of terms ordered by global importance
    public static func buildVocabulary(from result: AnalysisResult, maxTerms: Int = 100) -> [String] {
        // Score each term by sum of TF-IDF across chapters where it appears
        var termScores: [String: Double] = [:]

        for (_, keywords) in result.keywordsByChapter {
            for keyword in keywords {
                termScores[keyword.term, default: 0] += keyword.tfidf
            }
        }

        // Sort by total score and return top terms
        let sortedTerms = termScores.sorted { $0.value > $1.value }
        return sortedTerms.prefix(maxTerms).map(\.key)
    }

    // MARK: - Private Helpers

    /// Extracts plain text from a chapter
    private static func extractText(from chapter: Chapter) -> String {
        chapter.htmlSections.flatMap(\.blocks).map(\.textContent).joined(separator: " ")
    }

    /// Tokenizes text into lowercase words
    private static func tokenize(_ text: String) -> [String] {
        // Split on non-alphanumeric characters
        let pattern = #"[a-zA-Z]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text.lowercased().split(separator: " ").map(String.init)
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        return matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range]).lowercased()
        }
    }

    /// Computes term frequency for a list of tokens
    private static func computeTermFrequency(_ tokens: [String]) -> [String: Int] {
        var freq: [String: Int] = [:]
        for token in tokens {
            freq[token, default: 0] += 1
        }
        return freq
    }

    /// Common English stopwords to filter out
    private static let stopwords: Set<String> = [
        // Articles
        "a", "an", "the",
        // Pronouns
        "i", "me", "my", "myself", "we", "our", "ours", "ourselves", "you", "your", "yours",
        "yourself", "yourselves", "he", "him", "his", "himself", "she", "her", "hers",
        "herself", "it", "its", "itself", "they", "them", "their", "theirs", "themselves",
        "what", "which", "who", "whom", "this", "that", "these", "those",
        // Verbs
        "am", "is", "are", "was", "were", "be", "been", "being", "have", "has", "had",
        "having", "do", "does", "did", "doing", "would", "should", "could", "ought",
        "will", "shall", "can", "may", "might", "must",
        // Prepositions
        "about", "above", "after", "again", "against", "all", "and", "any", "as", "at",
        "because", "before", "below", "between", "both", "but", "by", "down", "during",
        "each", "few", "for", "from", "further", "here", "how", "if", "in", "into",
        "more", "most", "no", "nor", "not", "of", "off", "on", "once", "only", "or",
        "other", "out", "over", "own", "same", "so", "some", "such", "than", "that",
        "then", "there", "through", "to", "too", "under", "until", "up", "very",
        "when", "where", "while", "why", "with",
        // Common verbs
        "said", "say", "says", "saying", "get", "got", "go", "goes", "going", "went",
        "come", "came", "coming", "take", "took", "taking", "make", "made", "making",
        "know", "knew", "knowing", "think", "thought", "thinking", "see", "saw", "seeing",
        "want", "wanted", "wanting", "look", "looked", "looking", "use", "used", "using",
        "find", "found", "finding", "give", "gave", "giving", "tell", "told", "telling",
        // Other common words
        "just", "also", "now", "even", "well", "back", "still", "way", "like", "much",
        "new", "one", "two", "first", "last", "long", "great", "little", "old", "right",
        "big", "high", "different", "small", "large", "next", "early", "young", "important",
        "good", "bad", "best", "worst", "better", "worse",
        // Time words
        "day", "days", "time", "times", "year", "years", "week", "weeks", "month", "months",
        "today", "tomorrow", "yesterday", "always", "never", "sometimes", "often",
        // Place holders
        "thing", "things", "something", "nothing", "anything", "everything",
        "someone", "anyone", "everyone", "nobody", "somebody", "anybody", "everybody",
        // Conjunctions
        "however", "therefore", "although", "though", "unless", "whether", "either",
        "neither", "yet", "anyway", "besides", "hence", "thus", "meanwhile",
    ]
}

// MARK: - Bigram Support

public extension TFIDFAnalyzer {
    /// A bigram (two-word phrase) with its score
    struct BigramScore: Codable, Equatable {
        public let bigram: String
        public let tfidf: Double
        public let tf: Int
        public let df: Int

        public init(bigram: String, tfidf: Double, tf: Int, df: Int) {
            self.bigram = bigram
            self.tfidf = tfidf
            self.tf = tf
            self.df = df
        }
    }

    /// Extracts significant bigrams from chapters
    /// - Parameter chapters: The chapters to analyze
    /// - Returns: Bigrams per chapter, keyed by chapter ID
    static func extractBigrams(chapters: [Chapter]) -> [String: [BigramScore]] {
        guard !chapters.isEmpty else { return [:] }

        var chapterBigramFreqs: [String: [String: Int]] = [:]
        var documentFrequency: [String: Int] = [:]

        for chapter in chapters {
            let text = extractText(from: chapter)
            let tokens = tokenize(text).filter { !stopwords.contains($0) && $0.count >= minTermLength }
            let bigramFreq = computeBigramFrequency(tokens)

            chapterBigramFreqs[chapter.id] = bigramFreq

            for bigram in bigramFreq.keys {
                documentFrequency[bigram, default: 0] += 1
            }
        }

        let totalChapters = chapters.count
        var bigramsByChapter: [String: [BigramScore]] = [:]

        for chapter in chapters {
            guard let bigramFreq = chapterBigramFreqs[chapter.id] else { continue }

            var bigrams: [BigramScore] = []

            for (bigram, tf) in bigramFreq {
                guard tf >= 2 else { continue }

                let idf = log(Double(totalChapters) / Double(documentFrequency[bigram] ?? 1))
                let tfidfScore = Double(tf) * idf
                let df = documentFrequency[bigram] ?? 1

                bigrams.append(BigramScore(bigram: bigram, tfidf: tfidfScore, tf: tf, df: df))
            }

            bigrams.sort { $0.tfidf > $1.tfidf }
            bigramsByChapter[chapter.id] = Array(bigrams.prefix(30))
        }

        return bigramsByChapter
    }

    /// Computes bigram frequencies from tokens
    private static func computeBigramFrequency(_ tokens: [String]) -> [String: Int] {
        guard tokens.count >= 2 else { return [:] }

        var freq: [String: Int] = [:]
        for i in 0 ..< (tokens.count - 1) {
            let bigram = "\(tokens[i]) \(tokens[i + 1])"
            freq[bigram, default: 0] += 1
        }
        return freq
    }
}
