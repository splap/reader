import Foundation
import UIKit

public struct Page: Identifiable {
    public let id: Int
    public let containerIndex: Int
    public let range: NSRange
    public let textContainer: NSTextContainer

    public init(id: Int, containerIndex: Int, range: NSRange, textContainer: NSTextContainer) {
        self.id = id
        self.containerIndex = containerIndex
        self.range = range
        self.textContainer = textContainer
    }
}
