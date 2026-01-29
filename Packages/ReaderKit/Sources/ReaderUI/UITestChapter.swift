import Foundation
import ReaderCore

public enum UITestChapter {
    public static func makePositionTestChapter(pageCount: Int = 120) -> Chapter {
        let safeCount = max(1, pageCount)
        var body = ""
        for index in 1 ... safeCount {
            body += "<div style=\"break-after: column; -webkit-column-break-after: always;\">Page \(index)</div>"
        }
        let html = "<div id=\"pagination-container\">\(body)</div>"
        let section = HTMLSection(html: html, basePath: "", imageCache: [:], cssContent: nil)
        let attributed = NSAttributedString(string: "UI Test Position")
        return Chapter(
            id: "uitest-position",
            attributedText: attributed,
            htmlSections: [section],
            title: "UI Test Position"
        )
    }
}
