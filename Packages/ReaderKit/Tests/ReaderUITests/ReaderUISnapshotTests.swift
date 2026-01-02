import ReaderCore
@testable import ReaderUI
import SwiftUI
import UIKit
import XCTest

@MainActor
final class ReaderUISnapshotTests: XCTestCase {
    func testPageTextViewSnapshot() {
        let chapter = makeChapter()
        let engine = TextEngine(chapter: chapter)
        let pageSize = CGSize(width: 1024, height: 768)
        let insets = UIEdgeInsets(top: 32, left: 24, bottom: 32, right: 24)

        let result = engine.paginate(pageSize: pageSize, insets: insets, fontScale: 1.0)
        guard let page = result.pages.first else {
            XCTFail("No pages generated for snapshot")
            return
        }

        let view = PageSnapshotView(
            page: page,
            textStorage: result.textStorage,
            layoutManager: result.layoutManager,
            insets: insets,
            pageSize: pageSize
        )

        SnapshotTestHelper.assertSnapshot(view, size: pageSize, name: "PageTextView")
    }

    private func makeChapter() -> Chapter {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold)
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16)
        ]
        let italicAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 16)
        ]

        let text = NSMutableAttributedString(string: "Sample Chapter\n", attributes: titleAttributes)
        text.append(NSAttributedString(
            string: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ",
            attributes: bodyAttributes
        ))
        text.append(NSAttributedString(
            string: "Donec sed odio dui.",
            attributes: italicAttributes
        ))
        text.append(NSAttributedString(
            string: "\n\n" + String(repeating: "Vestibulum id ligula porta felis euismod semper. ", count: 40),
            attributes: bodyAttributes
        ))

        return Chapter(id: "snapshot", attributedText: text, title: "Sample Chapter")
    }
}

private struct PageSnapshotView: View {
    let page: Page
    let textStorage: NSTextStorage
    let layoutManager: NSLayoutManager
    let insets: UIEdgeInsets
    let pageSize: CGSize

    var body: some View {
        let availableSize = CGSize(
            width: pageSize.width - insets.left - insets.right,
            height: pageSize.height - insets.top - insets.bottom
        )

        ZStack(alignment: .topLeading) {
            Color.white
            PageTextView(
                page: page,
                textStorage: textStorage,
                layoutManager: layoutManager,
                onSendToLLM: { _ in }
            )
                .frame(width: availableSize.width, height: availableSize.height, alignment: .topLeading)
                .padding(EdgeInsets(
                    top: insets.top,
                    leading: insets.left,
                    bottom: insets.bottom,
                    trailing: insets.right
                ))
        }
    }
}
