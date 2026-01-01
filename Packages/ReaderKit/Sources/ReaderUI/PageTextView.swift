import ReaderCore
import SwiftUI
import UIKit

struct PageTextView: UIViewRepresentable {
    let page: Page
    let textStorage: NSTextStorage
    let onSendToLLM: (SelectionPayload) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSendToLLM: onSendToLLM)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(frame: .zero, textContainer: page.textContainer)
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

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.textStorage = textStorage
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
