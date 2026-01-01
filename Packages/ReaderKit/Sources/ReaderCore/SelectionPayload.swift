import Foundation

public struct SelectionPayload: Equatable {
    public let selectedText: String
    public let contextText: String
    public let range: NSRange

    public init(selectedText: String, contextText: String, range: NSRange) {
        self.selectedText = selectedText
        self.contextText = contextText
        self.range = range
    }
}
