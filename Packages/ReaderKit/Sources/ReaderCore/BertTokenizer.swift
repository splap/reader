import Foundation
import OSLog

/// BERT/WordPiece tokenizer for BGE embedding model
public final class BertTokenizer {
    private static let logger = Logger(subsystem: "com.splap.reader", category: "BertTokenizer")

    /// Vocabulary mapping from token string to ID
    private let vocab: [String: Int]

    /// Reverse mapping from ID to token string
    private let idToToken: [Int: String]

    /// Special token IDs
    public let clsTokenId: Int
    public let sepTokenId: Int
    public let padTokenId: Int
    public let unkTokenId: Int

    /// Maximum sequence length
    public let maxLength: Int

    /// Whether to lowercase input
    private let doLowerCase: Bool

    /// Shared instance loaded from bundle
    public static let shared: BertTokenizer? = {
        // Try to load from bundle
        guard let url = Bundle.main.url(forResource: "bge-tokenizer", withExtension: "json") else {
            // Try loading from source tree for tests
            let sourcePaths = [
                URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent() // ReaderCore
                    .deletingLastPathComponent() // Sources
                    .deletingLastPathComponent() // ReaderKit
                    .deletingLastPathComponent() // Packages
                    .appendingPathComponent("App/Resources/bge-tokenizer.json"),
                URL(fileURLWithPath: "/Users/jamesmichels/src/reader_parent/reader2/App/Resources/bge-tokenizer.json"),
            ]

            for path in sourcePaths {
                if FileManager.default.fileExists(atPath: path.path) {
                    return try? BertTokenizer(vocabURL: path)
                }
            }

            logger.warning("Tokenizer vocabulary not found in bundle or source tree")
            return nil
        }
        return try? BertTokenizer(vocabURL: url)
    }()

    /// Initialize from a vocabulary JSON file
    public init(vocabURL: URL) throws {
        let data = try Data(contentsOf: vocabURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Parse vocabulary
        guard let vocabDict = json["vocab"] as? [String: Int] else {
            throw TokenizerError.invalidVocabulary
        }
        self.vocab = vocabDict

        // Create reverse mapping
        var reverseVocab: [Int: String] = [:]
        for (token, id) in vocabDict {
            reverseVocab[id] = token
        }
        self.idToToken = reverseVocab

        // Parse special tokens
        guard let specialTokens = json["special_tokens"] as? [String: Any] else {
            throw TokenizerError.missingSpecialTokens
        }

        self.clsTokenId = specialTokens["cls_token_id"] as? Int ?? 101
        self.sepTokenId = specialTokens["sep_token_id"] as? Int ?? 102
        self.padTokenId = specialTokens["pad_token_id"] as? Int ?? 0
        self.unkTokenId = specialTokens["unk_token_id"] as? Int ?? 100

        // Parse config
        self.maxLength = json["model_max_length"] as? Int ?? 512
        self.doLowerCase = json["do_lower_case"] as? Bool ?? true

        Self.logger.info("Loaded tokenizer with \(self.vocab.count, privacy: .public) tokens")
    }

    /// Tokenize text into token IDs with attention mask
    public func encode(
        _ text: String,
        maxLength: Int? = nil,
        addSpecialTokens: Bool = true
    ) -> (inputIds: [Int32], attentionMask: [Int32]) {
        let maxLen = maxLength ?? self.maxLength

        // Preprocess text
        var processedText = text
        if doLowerCase {
            processedText = text.lowercased()
        }

        // Tokenize using WordPiece
        let tokens = wordPieceTokenize(processedText)

        // Convert to IDs
        var inputIds: [Int32] = []
        var attentionMask: [Int32] = []

        // Add [CLS] token
        if addSpecialTokens {
            inputIds.append(Int32(clsTokenId))
            attentionMask.append(1)
        }

        // Add word tokens (leave room for [SEP])
        let maxTokens = addSpecialTokens ? maxLen - 2 : maxLen
        for token in tokens.prefix(maxTokens) {
            let tokenId = vocab[token] ?? unkTokenId
            inputIds.append(Int32(tokenId))
            attentionMask.append(1)
        }

        // Add [SEP] token
        if addSpecialTokens {
            inputIds.append(Int32(sepTokenId))
            attentionMask.append(1)
        }

        // Pad to maxLength
        while inputIds.count < maxLen {
            inputIds.append(Int32(padTokenId))
            attentionMask.append(0)
        }

        return (inputIds, attentionMask)
    }

    /// WordPiece tokenization algorithm
    private func wordPieceTokenize(_ text: String) -> [String] {
        var tokens: [String] = []

        // Basic tokenization: split on whitespace and punctuation
        let words = basicTokenize(text)

        for word in words {
            // Try to find the word in vocabulary
            if vocab[word] != nil {
                tokens.append(word)
                continue
            }

            // WordPiece: break into subwords
            var subTokens: [String] = []
            var start = word.startIndex
            var isBad = false

            while start < word.endIndex {
                var end = word.endIndex
                var curSubstr: String? = nil

                while start < end {
                    var substr = String(word[start..<end])
                    if start > word.startIndex {
                        substr = "##" + substr
                    }

                    if vocab[substr] != nil {
                        curSubstr = substr
                        break
                    }

                    // Try shorter substring
                    end = word.index(before: end)
                }

                if let found = curSubstr {
                    subTokens.append(found)
                    start = end
                } else {
                    // Character not in vocab, mark as bad
                    isBad = true
                    break
                }
            }

            if isBad {
                tokens.append("[UNK]")
            } else {
                tokens.append(contentsOf: subTokens)
            }
        }

        return tokens
    }

    /// Basic tokenization: split on whitespace and punctuation
    private func basicTokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var currentToken = ""

        for char in text {
            if char.isWhitespace {
                if !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                }
            } else if isPunctuation(char) {
                if !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                }
                tokens.append(String(char))
            } else {
                currentToken.append(char)
            }
        }

        if !currentToken.isEmpty {
            tokens.append(currentToken)
        }

        return tokens
    }

    /// Check if character is punctuation
    private func isPunctuation(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let category = CharacterSet.punctuationCharacters
        return category.contains(scalar) || "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".contains(char)
    }
}

/// Tokenizer errors
public enum TokenizerError: Error, LocalizedError {
    case invalidVocabulary
    case missingSpecialTokens
    case vocabFileNotFound

    public var errorDescription: String? {
        switch self {
        case .invalidVocabulary:
            return "Invalid vocabulary format in tokenizer file"
        case .missingSpecialTokens:
            return "Missing special tokens in tokenizer file"
        case .vocabFileNotFound:
            return "Tokenizer vocabulary file not found"
        }
    }
}
