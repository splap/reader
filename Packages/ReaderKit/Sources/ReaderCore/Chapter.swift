import Foundation

public struct Chapter {
    public let id: String
    public let attributedText: NSAttributedString
    public let title: String?

    public init(id: String, attributedText: NSAttributedString, title: String? = nil) {
        self.id = id
        self.attributedText = attributedText
        self.title = title
    }
}
