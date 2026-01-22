import Foundation

/// Represents a single entry in the book's table of contents
public struct TOCItem: Identifiable, Equatable {
    /// The spine item ID (used for navigation)
    public let id: String

    /// The chapter title from the NCX
    public let label: String

    /// The index of this section in htmlSections array
    public let sectionIndex: Int

    public init(id: String, label: String, sectionIndex: Int) {
        self.id = id
        self.label = label
        self.sectionIndex = sectionIndex
    }
}
