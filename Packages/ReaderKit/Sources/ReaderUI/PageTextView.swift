import OSLog
import ReaderCore
import SwiftUI
import UIKit

struct PageTextView: UIViewRepresentable {
    private static let logger = Logger(subsystem: "com.example.reader", category: "page-view")
    let page: Page
    let onSendToLLM: (SelectionPayload) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSendToLLM: onSendToLLM)
    }

    func makeUIView(context: Context) -> UITextView {
        let containerSize = page.textContainer.size
        let frame = CGRect(origin: .zero, size: containerSize)
        let textView = PagingTextView(frame: frame, textContainer: page.textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = false

        context.coordinator.textView = textView
        context.coordinator.textStorage = page.textStorage

        let editMenu = UIEditMenuInteraction(delegate: context.coordinator)
        textView.addInteraction(editMenu)

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.textStorage = page.textStorage
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

final class PagingTextView: UITextView {
    private static let logger = Logger(subsystem: "com.example.reader", category: "page-view")

    override func layoutSubviews() {
        super.layoutSubviews()
#if DEBUG
        let boundsSize = self.bounds.size
        let containerSize = self.textContainer.size
        Self.logger.debug("PagingTextView layoutSubviews bounds=\(boundsSize.width, privacy: .public)x\(boundsSize.height, privacy: .public) containerSize=\(containerSize.width, privacy: .public)x\(containerSize.height, privacy: .public)")
#endif
        // CRITICAL: Do NOT call ensureLayout or modify textContainer.size here!
        // The layout was completed during pagination. Re-layout causes container 0 to consume all text.
    }
}
