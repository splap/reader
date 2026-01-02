import Foundation

public struct Book: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public let title: String
    public let filePath: String  // Relative to Books directory
    public let importDate: Date
    public var lastOpenedDate: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        filePath: String,
        importDate: Date = Date(),
        lastOpenedDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.filePath = filePath
        self.importDate = importDate
        self.lastOpenedDate = lastOpenedDate
    }
}
