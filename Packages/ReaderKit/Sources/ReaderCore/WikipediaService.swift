import Foundation

// MARK: - Wikipedia Service

/// Service for looking up information on Wikipedia
public actor WikipediaService {
    public init() {}

    /// Look up a Wikipedia article summary by title
    public func lookup(query: String) async throws -> WikipediaSummary {
        // URL-encode the query for the path
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw WikipediaError.invalidQuery
        }

        let urlString = "https://en.wikipedia.org/api/rest_v1/page/summary/\(encodedQuery)"
        guard let url = URL(string: urlString) else {
            throw WikipediaError.invalidQuery
        }

        var request = URLRequest(url: url)
        request.setValue("ReaderApp/1.0 (iOS reading app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WikipediaError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            throw WikipediaError.notFound(query: query)
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw WikipediaError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(WikipediaSummary.self, from: data)
    }

    /// Search Wikipedia for articles matching a query
    public func search(query: String, limit: Int = 5) async throws -> [WikipediaSearchResult] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw WikipediaError.invalidQuery
        }

        let urlString = "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=\(encodedQuery)&srlimit=\(limit)&format=json"
        guard let url = URL(string: urlString) else {
            throw WikipediaError.invalidQuery
        }

        var request = URLRequest(url: url)
        request.setValue("ReaderApp/1.0 (iOS reading app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WikipediaError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw WikipediaError.httpError(statusCode: httpResponse.statusCode)
        }

        let searchResponse = try JSONDecoder().decode(WikipediaSearchResponse.self, from: data)
        return searchResponse.query.search
    }
}

// MARK: - Response Types

/// Summary of a Wikipedia article
public struct WikipediaSummary: Codable {
    public let title: String
    public let description: String?
    public let extract: String
    public let contentUrls: ContentUrls?
    public let thumbnail: ImageInfo?
    public let originalimage: ImageInfo?

    public struct ContentUrls: Codable {
        public let desktop: PageUrl?

        public struct PageUrl: Codable {
            public let page: String?
        }
    }

    public struct ImageInfo: Codable {
        public let source: String
        public let width: Int
        public let height: Int
    }

    /// Get the Wikipedia URL for this article
    public var pageUrl: String? {
        contentUrls?.desktop?.page
    }

    /// Get the best available image URL (prefer thumbnail for faster loading)
    public var imageUrl: String? {
        thumbnail?.source ?? originalimage?.source
    }
}

/// Search response wrapper
struct WikipediaSearchResponse: Codable {
    let query: SearchQuery

    struct SearchQuery: Codable {
        let search: [WikipediaSearchResult]
    }
}

/// A single search result from Wikipedia
public struct WikipediaSearchResult: Codable {
    public let title: String
    public let snippet: String
    public let pageid: Int
}

// MARK: - Errors

public enum WikipediaError: LocalizedError {
    case invalidQuery
    case invalidResponse
    case notFound(query: String)
    case httpError(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidQuery:
            "Invalid Wikipedia query"
        case .invalidResponse:
            "Invalid response from Wikipedia"
        case let .notFound(query):
            "No Wikipedia article found for '\(query)'"
        case let .httpError(statusCode):
            "Wikipedia returned HTTP \(statusCode)"
        }
    }
}
