import Foundation
import UIKit

public struct Page: Identifiable {
    public let id: Int
    public let range: NSRange  // Range in the original full text

    // Each page has its own complete text system
    public let textStorage: NSTextStorage  // Contains only this page's text
    public let layoutManager: NSLayoutManager
    public let textContainer: NSTextContainer

    public init(
        id: Int,
        range: NSRange,
        textStorage: NSTextStorage,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) {
        self.id = id
        self.range = range
        self.textStorage = textStorage
        self.layoutManager = layoutManager
        self.textContainer = textContainer
    }

    public func actualCharacterRange() -> NSRange {
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        return layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    }
}
