import OSLog
import ReaderCore
import SwiftUI
import UIKit

struct PageTextView: UIViewRepresentable {
    private static let logger = Logger(subsystem: "com.example.reader", category: "page-view")
    let page: Page
    let textStorage: NSTextStorage
    let layoutManager: NSLayoutManager
    let onSendToLLM: (SelectionPayload) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSendToLLM: onSendToLLM)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = PagingTextView(frame: .zero, textContainer: page.textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = false

        context.coordinator.textView = textView
        context.coordinator.textStorage = textStorage

        let editMenu = UIEditMenuInteraction(delegate: context.coordinator)
        textView.addInteraction(editMenu)

        attachTextSystemIfNeeded(textView)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.textStorage = textStorage
        attachTextSystemIfNeeded(uiView)
    }

    private func attachTextSystemIfNeeded(_ textView: UITextView) {
        if layoutManager.textStorage !== textStorage {
            textStorage.addLayoutManager(layoutManager)
        }
        if page.textContainer.layoutManager !== layoutManager {
            let targetIndex = min(page.containerIndex, layoutManager.textContainers.count)
            layoutManager.insertTextContainer(page.textContainer, at: targetIndex)
        }
        layoutManager.ensureLayout(for: page.textContainer)
#if DEBUG
        if textView.layoutManager !== layoutManager {
            Self.logger.error("page \(page.id, privacy: .public) textView layoutManager mismatch")
        }
        if textView.textStorage !== textStorage {
            Self.logger.error("page \(page.id, privacy: .public) textView textStorage identity mismatch")
        }
        if textView.textStorage.length != textStorage.length {
            Self.logger.error(
                "page \(page.id, privacy: .public) textStorage length mismatch view=\(textView.textStorage.length, privacy: .public) expected=\(textStorage.length, privacy: .public)"
            )
        }
#endif
    }

    final class Coordinator: NSObject, UIEditMenuInteractionDelegate {
        weak var textView: UITextView?
        var textStorage: NSTextStorage?
        let onSendToLLM: (SelectionPayload) -> Void

        init(onSendToLLM: @escaping (SelectionPayload) -> Void) {
            self.onSendToLLM = onSendToLLM
        }

        func editMenuInteraction(
            _ interaction: UIEditMenuInteraction,
            menuFor configuration: UIEditMenuConfiguration,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard let textView, let textStorage else { return nil }
            let selectedRange = textView.selectedRange
            guard selectedRange.location != NSNotFound, selectedRange.length > 0 else { return nil }

            let sendAction = UIAction(title: "Send to LLM") { [weak self] _ in
                guard let self, let textView = self.textView, let textStorage = self.textStorage else { return }
                let range = textView.selectedRange
                guard range.location != NSNotFound, range.length > 0 else { return }
                let payload = SelectionExtractor.payload(in: textStorage, range: range)
                self.onSendToLLM(payload)
            }

            return UIMenu(children: suggestedActions + [sendAction])
        }
    }
}

private final class PagingTextView: UITextView {
    override func layoutSubviews() {
        super.layoutSubviews()
        if textContainer.size != bounds.size {
            textContainer.size = bounds.size
        }
        layoutManager.ensureLayout(for: textContainer)
    }
}
