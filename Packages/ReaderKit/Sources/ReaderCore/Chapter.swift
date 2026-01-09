import Foundation

public struct HTMLSection {
    public let html: String
    public let basePath: String
    public let imageCache: [String: Data]
    public let cssContent: String?

    public init(html: String, basePath: String, imageCache: [String: Data] = [:], cssContent: String? = nil) {
        self.html = html
        self.basePath = basePath
        self.imageCache = imageCache
        self.cssContent = cssContent
    }
}

public struct Chapter {
    public let id: String
    public let attributedText: NSAttributedString
    public let htmlSections: [HTMLSection]
    public let title: String?

    public init(id: String, attributedText: NSAttributedString, htmlSections: [HTMLSection] = [], title: String? = nil) {
        self.id = id
        self.attributedText = attributedText
        self.htmlSections = htmlSections
        self.title = title
    }
}
