import Foundation

public enum SelectionExtractor {
    public static func payload(
        in attributedText: NSAttributedString,
        range: NSRange,
        contextLength: Int = 500
    ) -> SelectionPayload {
        let fullLength = attributedText.length
        guard fullLength > 0 else {
            return SelectionPayload(selectedText: "", contextText: "", range: NSRange(location: 0, length: 0))
        }

        let clampedLocation = max(0, min(range.location, fullLength))
        let clampedLength = max(0, min(range.length, fullLength - clampedLocation))
        let clampedRange = NSRange(location: clampedLocation, length: clampedLength)

        let selectedText = attributedText.attributedSubstring(from: clampedRange).string

        let contextStart = max(0, clampedRange.location - contextLength)
        let contextEnd = min(fullLength, clampedRange.location + clampedRange.length + contextLength)
        let contextRange = NSRange(location: contextStart, length: max(0, contextEnd - contextStart))
        let contextText = attributedText.attributedSubstring(from: contextRange).string

        return SelectionPayload(selectedText: selectedText, contextText: contextText, range: clampedRange)
    }
}
