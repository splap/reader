import Foundation

public struct SelectionPayload: Equatable {
    public let selectedText: String
    public let contextText: String
    public let range: NSRange
    public let bookTitle: String?
    public let bookAuthor: String?
    public let chapterTitle: String?

    public init(
        selectedText: String,
        contextText: String,
        range: NSRange,
        bookTitle: String? = nil,
        bookAuthor: String? = nil,
        chapterTitle: String? = nil
    ) {
        self.selectedText = selectedText
        self.contextText = contextText
        self.range = range
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.chapterTitle = chapterTitle
    }
}
