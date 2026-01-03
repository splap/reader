import UIKit
import ReaderCore

public final class LLMModalViewController: UIViewController {
    private let selection: SelectionPayload
    private let service = OpenRouterService()

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let selectedTextLabel = PaddedLabel()
    private let answerLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let followUpTextField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let contextLabel = PaddedLabel()
    private let responseTimeLabel = UILabel()

    private var isLoading = false {
        didSet {
            if isLoading {
                loadingIndicator.startAnimating()
                answerLabel.isHidden = true
                sendButton.isEnabled = false
            } else {
                loadingIndicator.stopAnimating()
                answerLabel.isHidden = false
                updateSendButtonState()
            }
        }
    }

    private var responseTime: TimeInterval?

    public init(selection: SelectionPayload) {
        self.selection = selection
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        title = "Ask LLM"

        setupViews()
        setupLayout()

        Task {
            await fetchInitialAnswer()
        }
    }

    private func setupViews() {
        // Scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // Content stack
        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        // Selected text section
        let selectedTextHeader = makeHeaderLabel("Selected Text")
        selectedTextLabel.numberOfLines = 0
        selectedTextLabel.text = selection.selectedText
        selectedTextLabel.font = .systemFont(ofSize: 16)
        selectedTextLabel.backgroundColor = UIColor.secondarySystemBackground
        selectedTextLabel.layer.cornerRadius = 8
        selectedTextLabel.clipsToBounds = true
        selectedTextLabel.textInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        let selectedTextStack = UIStackView(arrangedSubviews: [selectedTextHeader, selectedTextLabel])
        selectedTextStack.axis = .vertical
        selectedTextStack.spacing = 8

        // Answer section
        let answerHeader = makeHeaderLabel("Answer")
        answerLabel.numberOfLines = 0
        answerLabel.text = "Loading..."
        answerLabel.font = .systemFont(ofSize: 16)
        answerLabel.textColor = .secondaryLabel

        let answerStack = UIStackView(arrangedSubviews: [answerHeader, loadingIndicator, answerLabel])
        answerStack.axis = .vertical
        answerStack.spacing = 8

        // Follow-up section
        let followUpHeader = makeHeaderLabel("Follow-up")
        followUpTextField.placeholder = "Ask a follow-up question"
        followUpTextField.borderStyle = .roundedRect
        followUpTextField.addTarget(self, action: #selector(followUpTextChanged), for: .editingChanged)

        sendButton.setTitle("Send", for: .normal)
        sendButton.addTarget(self, action: #selector(sendFollowUp), for: .touchUpInside)
        sendButton.isEnabled = false

        let followUpInputStack = UIStackView(arrangedSubviews: [followUpTextField, sendButton])
        followUpInputStack.axis = .horizontal
        followUpInputStack.spacing = 12

        let followUpStack = UIStackView(arrangedSubviews: [followUpHeader, followUpInputStack])
        followUpStack.axis = .vertical
        followUpStack.spacing = 8

        // Context section
        let contextHeader = makeHeaderLabel("Context")
        contextLabel.numberOfLines = 0
        contextLabel.text = selection.contextText
        contextLabel.font = .systemFont(ofSize: 12)
        contextLabel.textColor = .secondaryLabel
        contextLabel.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.5)
        contextLabel.layer.cornerRadius = 8
        contextLabel.clipsToBounds = true
        contextLabel.textInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        let contextStack = UIStackView(arrangedSubviews: [contextHeader, contextLabel])
        contextStack.axis = .vertical
        contextStack.spacing = 8

        // Add all sections to content stack
        contentStack.addArrangedSubview(selectedTextStack)
        contentStack.addArrangedSubview(answerStack)
        contentStack.addArrangedSubview(followUpStack)
        contentStack.addArrangedSubview(contextStack)

        // Response time label
        responseTimeLabel.font = .systemFont(ofSize: 12)
        responseTimeLabel.textColor = .secondaryLabel
        responseTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(responseTimeLabel)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: responseTimeLabel.topAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -48),

            responseTimeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            responseTimeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            responseTimeLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            responseTimeLabel.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    private func makeHeaderLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        return label
    }

    @objc private func followUpTextChanged() {
        updateSendButtonState()
    }

    private func updateSendButtonState() {
        let text = followUpTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        sendButton.isEnabled = !text.isEmpty && !isLoading
    }

    @objc private func sendFollowUp() {
        Task {
            await sendFollowUpQuestion()
        }
    }

    private func fetchInitialAnswer() async {
        isLoading = true
        let startTime = Date()

        do {
            let answer = try await service.sendMessage(
                selection: selection,
                userQuestion: nil
            )
            await MainActor.run {
                answerLabel.text = answer
                answerLabel.textColor = .label
                responseTime = Date().timeIntervalSince(startTime)
                updateResponseTimeLabel()
            }
        } catch {
            await MainActor.run {
                answerLabel.text = error.localizedDescription
                answerLabel.textColor = .systemRed
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }

    private func sendFollowUpQuestion() async {
        let question = followUpTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !question.isEmpty else { return }

        isLoading = true
        let startTime = Date()

        do {
            let answer = try await service.sendMessage(
                selection: selection,
                userQuestion: question
            )
            await MainActor.run {
                answerLabel.text = answer
                answerLabel.textColor = .label
                followUpTextField.text = ""
                responseTime = Date().timeIntervalSince(startTime)
                updateResponseTimeLabel()
            }
        } catch {
            await MainActor.run {
                answerLabel.text = error.localizedDescription
                answerLabel.textColor = .systemRed
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }

    private func updateResponseTimeLabel() {
        if let time = responseTime {
            responseTimeLabel.text = "Response time: \(String(format: "%.2f", time))s"
        } else {
            responseTimeLabel.text = ""
        }
    }
}

// Helper class for label with padding
private class PaddedLabel: UILabel {
    var textInsets = UIEdgeInsets.zero {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }

    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.width += textInsets.left + textInsets.right
        size.height += textInsets.top + textInsets.bottom
        return size
    }
}
