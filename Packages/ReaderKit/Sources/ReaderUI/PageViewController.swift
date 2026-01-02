import UIKit
import ReaderCore
import OSLog

final class PageViewController: UIViewController {
    private let page: Page
    let pageIndex: Int  // Accessible for UIPageViewController navigation
    private let onSendToLLM: (SelectionPayload) -> Void
    private var textView: UITextView!
    private var coordinator: EditMenuCoordinator!

    #if DEBUG
    private var debugOverlay: PageRangeOverlayView?
    #endif

    init(page: Page, pageIndex: Int, onSendToLLM: @escaping (SelectionPayload) -> Void) {
        self.page = page
        self.pageIndex = pageIndex
        self.onSendToLLM = onSendToLLM
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        // Create UITextView using the page's text container
        let containerSize = page.textContainer.size
        let frame = CGRect(origin: .zero, size: containerSize)
        textView = PagingTextView(frame: frame, textContainer: page.textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = false

        // Setup edit menu for "Send to LLM"
        coordinator = EditMenuCoordinator(onSendToLLM: onSendToLLM)
        coordinator.textView = textView
        coordinator.textStorage = page.textStorage

        let editMenu = UIEditMenuInteraction(delegate: coordinator)
        textView.addInteraction(editMenu)

        view.addSubview(textView)

        #if DEBUG
        debugOverlay = PageRangeOverlayView(pageIndex: pageIndex, page: page)
        if let overlay = debugOverlay {
            view.addSubview(overlay)
        }
        #endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Position text view with insets
        let insets = UIEdgeInsets(top: 48, left: 48, bottom: 48, right: 48)
        textView.frame.origin = CGPoint(x: insets.left, y: insets.top)

        #if DEBUG
        if let overlay = debugOverlay {
            overlay.sizeToFit()
            overlay.frame.origin = CGPoint(
                x: view.bounds.width - overlay.bounds.width - 8,
                y: 8
            )
        }
        #endif
    }
}

// MARK: - Edit Menu Coordinator

final class EditMenuCoordinator: NSObject, UIEditMenuInteractionDelegate {
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

// MARK: - Paging Text View

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

// MARK: - Debug Overlay

#if DEBUG
private final class PageRangeOverlayView: UIView {
    private let pageIndex: Int
    private let page: Page
    private let stackView = UIStackView()
    private var actualRange: NSRange = NSRange(location: 0, length: 0)

    init(pageIndex: Int, page: Page) {
        self.pageIndex = pageIndex
        self.page = page
        super.init(frame: .zero)
        setupView()
        updateActualRange()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = UIColor.black.withAlphaComponent(0.65)
        layer.cornerRadius = 6

        stackView.axis = .vertical
        stackView.alignment = .trailing
        stackView.spacing = 2

        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])

        updateLabels()
    }

    private func updateLabels() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let planned = page.range
        let isEmpty = actualRange.length == 0

        stackView.addArrangedSubview(makeLabel("page \(pageIndex)"))
        stackView.addArrangedSubview(makeLabel("planned \(planned.location) + \(planned.length)"))

        let actualLabel = makeLabel("actual \(actualRange.location) + \(actualRange.length)")
        actualLabel.textColor = isEmpty ? .red : .green
        stackView.addArrangedSubview(actualLabel)
    }

    private func makeLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 10)
        return label
    }

    private func updateActualRange() {
        actualRange = page.actualCharacterRange()
        updateLabels()
    }
}
#endif
