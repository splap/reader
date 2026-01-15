import Foundation

// MARK: - Map Service

/// Service for looking up places and generating maps using OpenStreetMap
public actor MapService {
    public init() {}

    /// Search for places by name or query
    public func search(query: String, limit: Int = 5) async throws -> [MapPlace] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw MapError.invalidQuery
        }

        let urlString = "https://nominatim.openstreetmap.org/search?q=\(encodedQuery)&format=json&addressdetails=1&limit=\(limit)"
        guard let url = URL(string: urlString) else {
            throw MapError.invalidQuery
        }

        var request = URLRequest(url: url)
        request.setValue("ReaderApp/1.0 (iOS reading app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MapError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw MapError.httpError(statusCode: httpResponse.statusCode)
        }

        // Don't use convertFromSnakeCase - we have manual CodingKeys
        let results = try JSONDecoder().decode([NominatimResult].self, from: data)

        return results.map { $0.toMapPlace() }
    }

    /// Geocode an address to coordinates
    public func geocode(address: String) async throws -> MapPlace? {
        let results = try await search(query: address, limit: 1)
        return results.first
    }

    /// Reverse geocode coordinates to a place
    public func reverseGeocode(lat: Double, lon: Double) async throws -> MapPlace? {
        let urlString = "https://nominatim.openstreetmap.org/reverse?lat=\(lat)&lon=\(lon)&format=json&addressdetails=1"
        guard let url = URL(string: urlString) else {
            throw MapError.invalidQuery
        }

        var request = URLRequest(url: url)
        request.setValue("ReaderApp/1.0 (iOS reading app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MapError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw MapError.httpError(statusCode: httpResponse.statusCode)
        }

        // Don't use convertFromSnakeCase - we have manual CodingKeys
        let result = try JSONDecoder().decode(NominatimResult.self, from: data)

        return result.toMapPlace()
    }

}

// MARK: - Response Types

/// A place result from the map service
public struct MapPlace: Codable, Sendable {
    public let displayName: String
    public let lat: Double
    public let lon: Double
    public let type: String
    public let category: String
    public let address: MapAddress?
    public let importance: Double

    /// Get a formatted short address
    public var shortAddress: String {
        var parts: [String] = []
        if let road = address?.road { parts.append(road) }
        if let city = address?.city ?? address?.town ?? address?.village { parts.append(city) }
        if let state = address?.state { parts.append(state) }
        if let country = address?.country { parts.append(country) }
        return parts.isEmpty ? displayName : parts.joined(separator: ", ")
    }
}

/// Address components from Nominatim
public struct MapAddress: Codable, Sendable {
    public let road: String?
    public let houseNumber: String?
    public let city: String?
    public let town: String?
    public let village: String?
    public let state: String?
    public let country: String?
    public let postcode: String?
}

// MARK: - Internal Types

/// Raw response from Nominatim API
struct NominatimResult: Codable {
    let placeId: Int
    let licence: String?
    let osmType: String?
    let osmId: Int?
    let lat: String
    let lon: String
    let displayName: String
    let type: String
    let category: String?
    let importance: Double?
    let address: NominatimAddress?

    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case licence
        case osmType = "osm_type"
        case osmId = "osm_id"
        case lat
        case lon
        case displayName = "display_name"
        case type
        case category = "class"
        case importance
        case address
    }

    func toMapPlace() -> MapPlace {
        MapPlace(
            displayName: displayName,
            lat: Double(lat) ?? 0,
            lon: Double(lon) ?? 0,
            type: type,
            category: category ?? "unknown",
            address: address?.toMapAddress(),
            importance: importance ?? 0
        )
    }
}

struct NominatimAddress: Codable {
    let road: String?
    let houseNumber: String?
    let city: String?
    let town: String?
    let village: String?
    let state: String?
    let country: String?
    let postcode: String?

    enum CodingKeys: String, CodingKey {
        case road
        case houseNumber = "house_number"
        case city
        case town
        case village
        case state
        case country
        case postcode
    }

    func toMapAddress() -> MapAddress {
        MapAddress(
            road: road,
            houseNumber: houseNumber,
            city: city,
            town: town,
            village: village,
            state: state,
            country: country,
            postcode: postcode
        )
    }
}

// MARK: - Errors

public enum MapError: LocalizedError {
    case invalidQuery
    case invalidResponse
    case notFound(query: String)
    case httpError(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Invalid map query"
        case .invalidResponse:
            return "Invalid response from map service"
        case .notFound(let query):
            return "No location found for '\(query)'"
        case .httpError(let statusCode):
            return "Map service returned HTTP \(statusCode)"
        }
    }
}
