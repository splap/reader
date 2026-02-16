import MapKit
import OSLog
import ReaderCore
import UIKit

/// Chat interface for conversing with the LLM about a book
public final class BookChatViewController: UIViewController {
    private static let logger = Log.logger(category: "chat")
    private let context: BookContext
    private let agentService: any AgentServiceProtocol
    private let initialSelection: SelectionPayload?
    private let conversationId: UUID?
    private let fontManager = FontScaleManager.shared

    private var conversation: Conversation
    private var conversationHistory: [AgentMessage] = []
    private var isLoading = false

    // MARK: - Turn-Based Data Model

    private var turns: [Turn] = []
    private var turnTraces: [UUID: AgentExecutionTrace] = [:]
    private var dataSource: UITableViewDiffableDataSource<Section, Turn.ID>!

    private enum Section {
        case main
    }

    // MARK: - Typewriter Effect Properties

    private var typewriterTimer: Timer?
    private var typewriterTurnId: UUID?
    private var typewriterFullContent: String?
    private var typewriterCharIndex: Int = 0
    private var typewriterLastLayoutUpdate: Date = .distantPast
    private var typewriterStartTime: Date = .distantPast
    private var typewriterLastLoggedIndex: Int = 0

    // Organic timing configuration
    private struct TypewriterTiming {
        let tickInterval: TimeInterval
        let charsPerTickBase: Int
        let charsPerTickJitter: Int
        let pauseAtPeriod: TimeInterval
        let pauseAtNewline: TimeInterval
        let layoutUpdateInterval: TimeInterval

        static let normal = TypewriterTiming(
            tickInterval: 0.012,
            charsPerTickBase: 6,
            charsPerTickJitter: 4,
            pauseAtPeriod: 0.025,
            pauseAtNewline: 0.040,
            layoutUpdateInterval: 0.15
        )

        static let slow = TypewriterTiming(
            tickInterval: 0.030,
            charsPerTickBase: 3,
            charsPerTickJitter: 1,
            pauseAtPeriod: 0.060,
            pauseAtNewline: 0.100,
            layoutUpdateInterval: 0.20
        )
    }

    private let typewriterConfig: TypewriterTiming

    // MARK: - UI Components

    private let tableView = UITableView()
    private let inputContainer = UIView()

    // Occlusion bands
    private let topBlurView = UIVisualEffectView(effect: nil)
    private let bottomBlurView = UIVisualEffectView(effect: nil)

    // DEBUG: Visual guides
    private let topViewportLine = UIView()
    private let bottomViewportLine = UIView()

    var topContentInset: CGFloat = 0 {
        didSet { updateTableViewInsets() }
    }

    var bottomContentInset: CGFloat = 0 {
        didSet {
            baseBottomContentInset = bottomContentInset
            updateTableViewInsets()
        }
    }

    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let buttonRow = UIView()
    private let modelButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let scrollToBottomButton = UIButton(type: .system)

    private var inputContainerBottomConstraint: NSLayoutConstraint?
    private var textViewHeightConstraint: NSLayoutConstraint?

    private let minTextViewHeight: CGFloat = 36
    private let maxTextViewHeight: CGFloat = 200
    private let buttonRowHeight: CGFloat = 44
    private let contentBelowTolerance: CGFloat = 24
    private var baseBottomContentInset: CGFloat = 0
    private let viewportPadding: CGFloat = 24

    private var topGuideConstraint: NSLayoutConstraint?
    private var topBlurHeightConstraint: NSLayoutConstraint?
    private var bottomBlurTopConstraint: NSLayoutConstraint?

    // MARK: - Initialization

    public var currentConversationId: UUID? { conversationId }

    public init(context: BookContext, selection: SelectionPayload? = nil, conversationId: UUID? = nil) {
        self.context = context
        initialSelection = selection
        self.conversationId = conversationId

        // Conditional stub injection for UI testing
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--uitesting-stub-chat-long") {
            agentService = StubAgentService(mode: .long)
        } else if args.contains("--uitesting-stub-chat-short") {
            agentService = StubAgentService(mode: .short)
        } else if args.contains("--uitesting-stub-chat-extralong") {
            agentService = StubAgentService(mode: .extraLong)
        } else if args.contains("--uitesting-stub-chat-error") {
            agentService = StubAgentService(mode: .error)
        } else {
            agentService = ReaderAgentService()
        }

        if args.contains("--uitesting-slow-typewriter") {
            typewriterConfig = .slow
        } else {
            typewriterConfig = .normal
        }

        // Load existing conversation or create new one
        if let convId = conversationId,
           let existingConv = ConversationStorage.shared.getConversation(id: convId)
        {
            conversation = existingConv
        } else {
            conversation = Conversation(
                title: "New Chat",
                bookTitle: context.bookTitle,
                bookAuthor: context.bookAuthor,
                messages: []
            )
        }

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()
        Self.logger.debug("Chat UI opened for book: \(context.bookTitle)")
        setupUI()
        setupViewportGuides()
        setupDataSource()
        setupFontScaleObserver()
        loadConversation()
        updateTableViewInsets()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.layoutIfNeeded()
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateViewportGuides()
        updateBottomInsetForInputContainer()
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
        stopTypewriterEffect()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground

        // Table view
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.keyboardDismissMode = .interactive
        tableView.register(TurnCell.self, forCellReuseIdentifier: "TurnCell")
        tableView.accessibilityIdentifier = "chat-message-list"
        tableView.backgroundColor = .clear
        view.addSubview(tableView)

        // Blur overlays
        topBlurView.translatesAutoresizingMaskIntoConstraints = false
        topBlurView.isUserInteractionEnabled = false
        topBlurView.effect = nil
        topBlurView.backgroundColor = .black
        topBlurView.contentView.backgroundColor = .black
        view.addSubview(topBlurView)

        bottomBlurView.translatesAutoresizingMaskIntoConstraints = false
        bottomBlurView.isUserInteractionEnabled = false
        bottomBlurView.effect = nil
        bottomBlurView.backgroundColor = .black
        bottomBlurView.contentView.backgroundColor = .black
        view.addSubview(bottomBlurView)

        // Input container
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.backgroundColor = .secondarySystemBackground
        inputContainer.layer.cornerRadius = 16
        inputContainer.clipsToBounds = true
        view.addSubview(inputContainer)

        // Text view
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.font = fontManager.bodyFont
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.accessibilityIdentifier = "chat-input-textview"
        inputContainer.addSubview(textView)

        // Placeholder
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = "Ask about the book..."
        placeholderLabel.font = fontManager.bodyFont
        placeholderLabel.textColor = .placeholderText
        inputContainer.addSubview(placeholderLabel)

        // Button row
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.backgroundColor = .clear
        inputContainer.addSubview(buttonRow)

        // Model selector button
        modelButton.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.plain()
        config.title = OpenRouterConfig.modelDisplayName
        config.baseForegroundColor = .secondaryLabel
        config.image = UIImage(systemName: "chevron.down")
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 10, weight: .regular, scale: .small)
        config.imagePlacement = .trailing
        config.imagePadding = 4
        modelButton.configuration = config
        modelButton.addTarget(self, action: #selector(showModelPicker), for: .touchUpInside)
        buttonRow.addSubview(modelButton)

        // Send button
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        sendButton.tintColor = .systemBlue
        sendButton.contentHorizontalAlignment = .fill
        sendButton.contentVerticalAlignment = .fill
        sendButton.addTarget(self, action: #selector(sendMessage), for: .touchUpInside)
        sendButton.accessibilityIdentifier = "chat-send-button"
        buttonRow.addSubview(sendButton)

        // Loading indicator
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.style = .large
        loadingIndicator.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        buttonRow.addSubview(loadingIndicator)

        // Scroll-to-bottom button
        scrollToBottomButton.translatesAutoresizingMaskIntoConstraints = false
        scrollToBottomButton.isHidden = true
        scrollToBottomButton.alpha = 0
        scrollToBottomButton.accessibilityIdentifier = "scroll-to-bottom-button"
        scrollToBottomButton.addTarget(self, action: #selector(scrollToBottomTapped), for: .touchUpInside)
        setupScrollToBottomButton()
        view.addSubview(scrollToBottomButton)

        // Layout
        let bottomConstraint = inputContainer.bottomAnchor.constraint(
            equalTo: view.keyboardLayoutGuide.topAnchor, constant: -14
        )
        inputContainerBottomConstraint = bottomConstraint

        let textViewHeight = textView.heightAnchor.constraint(equalToConstant: minTextViewHeight)
        textViewHeightConstraint = textViewHeight

        let topBlurHeight = topBlurView.heightAnchor.constraint(equalToConstant: 100)
        topBlurHeightConstraint = topBlurHeight

        let bottomBlurTop = bottomBlurView.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: -viewportPadding)
        bottomBlurTopConstraint = bottomBlurTop

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            topBlurView.topAnchor.constraint(equalTo: view.topAnchor),
            topBlurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBlurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBlurHeight,

            bottomBlurTop,
            bottomBlurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBlurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBlurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            bottomConstraint,

            textView.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -12),
            textViewHeight,

            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 6),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 4),

            buttonRow.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 4),
            buttonRow.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -8),
            buttonRow.heightAnchor.constraint(equalToConstant: 44),

            modelButton.leadingAnchor.constraint(equalTo: buttonRow.leadingAnchor, constant: 12),
            modelButton.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),

            sendButton.trailingAnchor.constraint(equalTo: buttonRow.trailingAnchor, constant: -8),
            sendButton.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 44),
            sendButton.heightAnchor.constraint(equalToConstant: 44),

            loadingIndicator.centerXAnchor.constraint(equalTo: sendButton.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),

            scrollToBottomButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scrollToBottomButton.bottomAnchor.constraint(equalTo: inputContainer.topAnchor, constant: -8),
            scrollToBottomButton.widthAnchor.constraint(equalToConstant: 44),
            scrollToBottomButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setupScrollToBottomButton() {
        let blurEffect = UIBlurEffect(style: .systemThinMaterial)
        let glassBackground = UIVisualEffectView(effect: blurEffect)
        glassBackground.translatesAutoresizingMaskIntoConstraints = false
        glassBackground.layer.cornerRadius = 22
        glassBackground.clipsToBounds = true
        glassBackground.isUserInteractionEnabled = false
        glassBackground.layer.borderWidth = 0.5
        glassBackground.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor

        let vibrancyEffect = UIVibrancyEffect(blurEffect: blurEffect, style: .label)
        let vibrancyView = UIVisualEffectView(effect: vibrancyEffect)
        vibrancyView.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        vibrancyView.contentView.addSubview(iconView)

        glassBackground.contentView.addSubview(vibrancyView)
        scrollToBottomButton.addSubview(glassBackground)

        NSLayoutConstraint.activate([
            glassBackground.topAnchor.constraint(equalTo: scrollToBottomButton.topAnchor),
            glassBackground.leadingAnchor.constraint(equalTo: scrollToBottomButton.leadingAnchor),
            glassBackground.trailingAnchor.constraint(equalTo: scrollToBottomButton.trailingAnchor),
            glassBackground.bottomAnchor.constraint(equalTo: scrollToBottomButton.bottomAnchor),

            vibrancyView.topAnchor.constraint(equalTo: glassBackground.contentView.topAnchor),
            vibrancyView.leadingAnchor.constraint(equalTo: glassBackground.contentView.leadingAnchor),
            vibrancyView.trailingAnchor.constraint(equalTo: glassBackground.contentView.trailingAnchor),
            vibrancyView.bottomAnchor.constraint(equalTo: glassBackground.contentView.bottomAnchor),

            iconView.centerXAnchor.constraint(equalTo: vibrancyView.contentView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: vibrancyView.contentView.centerYAnchor),
        ])
    }

    private func setupViewportGuides() {
        topViewportLine.translatesAutoresizingMaskIntoConstraints = false
        topViewportLine.backgroundColor = .systemRed
        topViewportLine.isUserInteractionEnabled = false
        view.addSubview(topViewportLine)

        bottomViewportLine.translatesAutoresizingMaskIntoConstraints = false
        bottomViewportLine.backgroundColor = .systemRed
        bottomViewportLine.isUserInteractionEnabled = false
        view.addSubview(bottomViewportLine)

        NSLayoutConstraint.activate([
            topViewportLine.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topViewportLine.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topViewportLine.heightAnchor.constraint(equalToConstant: 2),

            bottomViewportLine.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomViewportLine.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomViewportLine.heightAnchor.constraint(equalToConstant: 2),
            bottomViewportLine.bottomAnchor.constraint(equalTo: inputContainer.topAnchor, constant: -viewportPadding),
        ])
    }

    private func updateViewportGuides() {
        let topInset = tableView.adjustedContentInset.top
        let extraTopPadding: CGFloat = 16
        let topViewportY = topInset + extraTopPadding

        topBlurHeightConstraint?.constant = topViewportY

        topGuideConstraint?.isActive = false
        topGuideConstraint = topViewportLine.topAnchor.constraint(equalTo: view.topAnchor, constant: topViewportY)
        topGuideConstraint?.isActive = true

        view.bringSubviewToFront(topBlurView)
        view.bringSubviewToFront(bottomBlurView)
        view.bringSubviewToFront(inputContainer)
        view.bringSubviewToFront(scrollToBottomButton)
        view.bringSubviewToFront(topViewportLine)
        view.bringSubviewToFront(bottomViewportLine)
    }

    private func updateTableViewInsets() {
        tableView.contentInset.top = topContentInset
        tableView.contentInset.bottom = baseBottomContentInset
        tableView.verticalScrollIndicatorInsets.top = topContentInset
        tableView.verticalScrollIndicatorInsets.bottom = baseBottomContentInset
    }

    /// Keep bottom inset in sync with input container position so viewport geometry
    /// correctly reflects the visible area above the input container.
    private func updateBottomInsetForInputContainer() {
        let inputOcclusion = view.bounds.height - inputContainer.frame.minY + viewportPadding
        let newBottom = max(baseBottomContentInset, inputOcclusion)
        if tableView.contentInset.bottom != newBottom {
            tableView.contentInset.bottom = newBottom
            tableView.verticalScrollIndicatorInsets.bottom = newBottom
        }
    }

    private func setupDataSource() {
        dataSource = UITableViewDiffableDataSource<Section, Turn.ID>(tableView: tableView) { [weak self] tableView, indexPath, turnId in
            guard let self,
                  let cell = tableView.dequeueReusableCell(withIdentifier: "TurnCell", for: indexPath) as? TurnCell,
                  let turn = self.turns.first(where: { $0.id == turnId })
            else {
                return UITableViewCell()
            }

            let isActive = turn.state == .pending || turn.state == .streaming
            let viewportHeight = self.viewportHeight
            cell.configure(with: turn, viewportHeight: viewportHeight, isActive: isActive)

            // Set up context menu callbacks
            cell.onCopyPrompt = { UIPasteboard.general.string = turn.prompt }
            cell.onCopyAnswer = { UIPasteboard.general.string = turn.answer }

            if let trace = self.turnTraces[turn.id] {
                cell.onShowExecutionDetails = { [weak self] in
                    self?.showExecutionDetails(for: turn.id)
                }
                cell.onCopyDebugTranscript = { [weak self] in
                    UIPasteboard.general.string = self?.buildDebugTranscript() ?? ""
                }
            } else {
                cell.onShowExecutionDetails = nil
                cell.onCopyDebugTranscript = nil
            }

            return cell
        }
    }

    private func setupFontScaleObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fontScaleDidChange),
            name: FontScaleManager.fontScaleDidChangeNotification,
            object: nil
        )
    }

    @objc private func fontScaleDidChange() {
        textView.font = fontManager.bodyFont
        placeholderLabel.font = fontManager.bodyFont
        modelButton.titleLabel?.font = fontManager.captionFont
        updateTextViewHeight()
        applySnapshot(animatingDifferences: false)
    }

    // MARK: - Conversation Loading

    private func loadConversation() {
        if conversationId != nil, !conversation.messages.isEmpty {
            // Load existing conversation as turns
            turns = turnsFromMessages(conversation.messages)

            // Restore traces from turns (turnsFromMessages already pairs them correctly)
            for turn in turns {
                if let trace = turn.trace {
                    turnTraces[turn.id] = trace
                }
            }

            // Rebuild conversation history for agent
            for turn in turns {
                conversationHistory.append(AgentMessage(role: .user, content: turn.prompt))
                if !turn.answer.isEmpty {
                    conversationHistory.append(AgentMessage(role: .assistant, content: turn.answer, toolCalls: nil))
                }
            }

            applySnapshot(animatingDifferences: false)
        } else if let selection = initialSelection {
            // Pre-fill input with selection
            let cleanedSelection = selection.selectedText.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
            let formattedText = "selection: \"\(cleanedSelection)\"\n\n"
            textView.text = formattedText
            placeholderLabel.isHidden = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.view.layoutIfNeeded()
                self.updateTextViewHeight()
                self.textView.becomeFirstResponder()
                let endPosition = self.textView.endOfDocument
                self.textView.selectedTextRange = self.textView.textRange(from: endPosition, to: endPosition)
            }
        }
    }

    // MARK: - Data Source Updates

    private func applySnapshot(animatingDifferences: Bool = false) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Turn.ID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(turns.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    }

    // MARK: - Actions

    func saveConversation() {
        saveAndSummarizeConversation()
    }

    func buildDebugTranscript() -> String {
        var transcript = "=== DEBUG TRANSCRIPT ===\n"
        transcript += "Book: \(context.bookTitle)"
        if let author = context.bookAuthor {
            transcript += " by \(author)"
        }
        transcript += "\nGenerated: \(Date())\n"
        transcript += "Turns: \(turns.count), Traces: \(turnTraces.count)\n"
        transcript += "========================\n\n"

        var stepIndex = 0
        for turn in turns {
            guard let trace = turnTraces[turn.id] else { continue }

            for step in trace.timeline {
                transcript += formatTimelineStep(step, index: stepIndex)
                stepIndex += 1
            }
        }

        transcript += "\n=== END (\(stepIndex) steps) ===\n"
        return transcript
    }

    private func logTranscript() {
        let transcript = buildDebugTranscript()
        let chunkSize = 800
        var offset = transcript.startIndex
        var chunkNum = 1
        while offset < transcript.endIndex {
            let end = transcript.index(offset, offsetBy: chunkSize, limitedBy: transcript.endIndex) ?? transcript.endIndex
            let chunk = String(transcript[offset ..< end])
            Self.logger.info("TRACE[\(chunkNum)]: \(chunk)")
            offset = end
            chunkNum += 1
        }
    }

    private func formatTimelineStep(_ step: TimelineStep, index: Int) -> String {
        switch step {
        case let .user(content):
            let preview = content.count > 100 ? String(content.prefix(100)) + "..." : content
            return "[\(index)] USER: \(preview)\n\n"

        case let .llm(exec):
            var line = "[\(index)] LLM (\(exec.model)) - \(String(format: "%.2f", exec.executionTime))s"
            if let inp = exec.inputTokens, let out = exec.outputTokens {
                line += ", \(inp) in / \(out) out"
            }
            line += "\n"

            if let tools = exec.requestedTools, !tools.isEmpty {
                for tool in tools {
                    line += "    -> \(tool)\n"
                }
            } else {
                line += "    [final response]\n"
            }
            return line + "\n"

        case let .tool(exec):
            var line = "[\(index)] TOOL \(exec.functionName) - \(String(format: "%.3f", exec.executionTime))s\n"
            let argsPreview = exec.arguments.replacingOccurrences(of: "\n", with: " ")
            line += "    args: \(argsPreview)\n"
            let maxResultLen = 4000
            let resultText = exec.result.count > maxResultLen
                ? String(exec.result.prefix(maxResultLen)) + "..."
                : exec.result
            let indentedResult = resultText
                .components(separatedBy: "\n")
                .joined(separator: "\n            ")
            line += "    result: \(indentedResult)\n"
            return line + "\n"

        case let .assistant(content):
            let preview = content.count > 200 ? String(content.prefix(200)) + "..." : content
            return "[\(index)] ASSISTANT:\n\(preview)\n\n"
        }
    }

    private func showExecutionDetails(for turnId: UUID) {
        // TODO: Implement execution details panel
        Self.logger.info("Show execution details for turn \(turnId)")
    }

    private func saveAndSummarizeConversation() {
        let storedMessages = messagesFromTurns(turns)

        guard storedMessages.count > 1 else { return }

        conversation.messages = storedMessages
        conversation.updatedAt = Date()

        if conversation.title == "New Chat" {
            summarizeConversation()
        } else {
            ConversationStorage.shared.saveConversation(conversation)
        }
    }

    private func summarizeConversation() {
        let conversationText = turns.prefix(3).map { turn in
            "User: \(turn.prompt)\nAssistant: \(turn.answer)"
        }.joined(separator: "\n")

        let summaryPrompt = """
        Generate a short title (3-5 words max) for this conversation:

        \(conversationText)

        Respond with ONLY the title, nothing else.
        """

        Task {
            do {
                let result = try await agentService.chat(
                    message: summaryPrompt,
                    context: context,
                    history: [],
                    selectionContext: nil,
                    selectionBlockId: nil,
                    selectionSpineItemId: nil
                )

                await MainActor.run {
                    let title = result.response.content
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .prefix(50)
                    self.conversation.title = String(title)
                    ConversationStorage.shared.saveConversation(self.conversation)
                }
            } catch {
                await MainActor.run {
                    if let firstTurn = self.turns.first {
                        let title = firstTurn.prompt.prefix(30)
                        self.conversation.title = String(title) + "..."
                    }
                    ConversationStorage.shared.saveConversation(self.conversation)
                }
            }
        }
    }

    @objc private func showModelPicker() {
        let picker = ModelPickerViewController(
            selectedModelId: OpenRouterConfig.model,
            onSelect: { [weak self] model in
                OpenRouterConfig.model = model.id
                self?.modelButton.configuration?.title = model.name
            }
        )
        picker.modalPresentationStyle = .popover
        picker.preferredContentSize = CGSize(width: 350, height: 400)

        if let popover = picker.popoverPresentationController {
            popover.sourceView = modelButton
            popover.sourceRect = modelButton.bounds
            popover.permittedArrowDirections = [.down, .up]
            popover.delegate = self
        }

        present(picker, animated: true)
    }

    @objc private func sendMessage() {
        guard let text = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              !isLoading
        else {
            return
        }

        stopTypewriterEffect()

        // Create new turn
        let turn = Turn(prompt: text, state: .pending)
        turns.append(turn)

        let turnIndex = turns.count - 1
        Self.logger.info("SCROLL[send]: created turn \(turn.id), index \(turnIndex)")

        // Clear input, update layout, apply snapshot, and scroll - all atomically
        UIView.performWithoutAnimation {
            // Clear input and update height synchronously
            textView.text = ""
            placeholderLabel.isHidden = false
            let size = CGSize(width: textView.frame.width, height: .infinity)
            let estimatedSize = textView.sizeThatFits(size)
            let newHeight = min(estimatedSize.height, maxTextViewHeight)
            textViewHeightConstraint?.constant = max(minTextViewHeight, newHeight)
            textView.isScrollEnabled = estimatedSize.height > maxTextViewHeight

            // Layout entire view hierarchy to finalize positions
            view.layoutIfNeeded()

            // Apply snapshot and scroll
            applySnapshot(animatingDifferences: false)
            tableView.layoutIfNeeded()
            let indexPath = IndexPath(row: turnIndex, section: 0)
            scrollRowToViewportTop(indexPath)
        }

        setLoading(true)

        // Send to agent
        Task {
            do {
                let result = try await agentService.chat(
                    message: text,
                    context: context,
                    history: conversationHistory,
                    selectionContext: initialSelection?.contextText,
                    selectionBlockId: initialSelection?.blockId,
                    selectionSpineItemId: initialSelection?.spineItemId
                )

                await MainActor.run {
                    self.conversationHistory = result.updatedHistory

                    // Store trace
                    if let trace = result.response.executionTrace {
                        self.turnTraces[turn.id] = trace
                    }

                    // Log transcript
                    self.logTranscript()

                    setLoading(false)

                    // Start typewriter
                    startTypewriterEffect(turnId: turn.id, fullContent: result.response.content)
                }
            } catch {
                await MainActor.run {
                    // Update turn with error
                    if let index = self.turns.firstIndex(where: { $0.id == turn.id }) {
                        self.turns[index].answer = "Error: \(error.localizedDescription)"
                        self.turns[index].state = .complete
                        applySnapshot(animatingDifferences: false)
                    }
                    setLoading(false)
                }
            }
        }
    }

    private func setLoading(_ loading: Bool) {
        isLoading = loading
        sendButton.isHidden = loading
        textView.isEditable = !loading

        if loading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
            textView.becomeFirstResponder()
        }
    }

    private func updateTextViewHeight() {
        let size = CGSize(width: textView.frame.width, height: .infinity)
        let estimatedSize = textView.sizeThatFits(size)
        let newHeight = min(estimatedSize.height, maxTextViewHeight)
        textViewHeightConstraint?.constant = max(minTextViewHeight, newHeight)
        textView.isScrollEnabled = estimatedSize.height > maxTextViewHeight

        UIView.animate(withDuration: 0.1) {
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Viewport Geometry

    private var viewportHeight: CGFloat {
        viewportGeometry.visibleHeight
    }

    private var viewportGeometry: ChatViewportGeometry {
        ChatViewportGeometry(scrollView: tableView)
    }

    private func scrollRowToViewportTop(_ indexPath: IndexPath) {
        guard indexPath.row < turns.count else { return }

        // Step 1: Force cell to load by scrolling to it first
        tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
        tableView.layoutIfNeeded()

        // Step 2: Now calculate precise offset to place row at viewport top
        let cellRect = tableView.rectForRow(at: indexPath)
        let geometry = viewportGeometry
        tableView.contentOffset = geometry.offsetToShowAtTop(cellRect.origin.y)
    }

    @objc private func scrollToBottomTapped() {
        let geometry = viewportGeometry
        let targetOffset = geometry.offsetToShowBottom

        UIView.animate(withDuration: 0.3) {
            self.tableView.setContentOffset(targetOffset, animated: false)
        } completion: { _ in
            self.updateScrollToBottomButtonVisibility()
        }
    }

    private func updateScrollToBottomButtonVisibility() {
        let geometry = viewportGeometry
        let distance = max(0, geometry.distanceToBottom)
        let shouldShow = distance > contentBelowTolerance
        let isCurrentlyVisible = scrollToBottomButton.alpha > 0

        if shouldShow != isCurrentlyVisible {
            scrollToBottomButton.isHidden = false
            UIView.animate(withDuration: 0.2) {
                self.scrollToBottomButton.alpha = shouldShow ? 1 : 0
            } completion: { _ in
                if !shouldShow {
                    self.scrollToBottomButton.isHidden = true
                }
            }
        }
    }

    // MARK: - Typewriter Effect

    private func startTypewriterEffect(turnId: UUID, fullContent: String) {
        stopTypewriterEffect()

        guard let index = turns.firstIndex(where: { $0.id == turnId }) else { return }

        turns[index].state = .streaming
        turns[index].answer = ""
        typewriterTurnId = turnId
        typewriterFullContent = fullContent
        typewriterCharIndex = 0
        typewriterStartTime = Date()

        Self.logger.info("TYPEWRITER: Starting, \(fullContent.count) chars total")

        // Preserve scroll position when updating snapshot - prevents visual shift
        let scrollPositionBefore = tableView.contentOffset
        UIView.performWithoutAnimation {
            applySnapshot(animatingDifferences: false)
            tableView.layoutIfNeeded()
            tableView.setContentOffset(scrollPositionBefore, animated: false)
        }
        updateScrollToBottomButtonVisibility()

        scheduleNextTypewriterTick(delay: typewriterConfig.tickInterval)
    }

    private func scheduleNextTypewriterTick(delay: TimeInterval) {
        typewriterTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.typewriterTick()
        }
    }

    private func typewriterTick() {
        guard let turnId = typewriterTurnId,
              let fullContent = typewriterFullContent,
              let index = turns.firstIndex(where: { $0.id == turnId }),
              typewriterCharIndex < fullContent.count
        else {
            finishTypewriterEffect()
            return
        }

        // Calculate batch size with jitter
        let jitter = Int.random(in: -typewriterConfig.charsPerTickJitter ... typewriterConfig.charsPerTickJitter)
        let batchSize = max(1, typewriterConfig.charsPerTickBase + jitter)
        let remainingChars = fullContent.count - typewriterCharIndex
        let charsToAdd = min(batchSize, remainingChars)

        typewriterCharIndex += charsToAdd
        let endIndex = fullContent.index(fullContent.startIndex, offsetBy: typewriterCharIndex)
        let newContent = String(fullContent[..<endIndex])
        turns[index].answer = newContent

        // Sample logging
        if typewriterCharIndex - typewriterLastLoggedIndex >= 200 {
            let elapsed = Date().timeIntervalSince(typewriterStartTime)
            let rate = Double(typewriterCharIndex) / elapsed
            Self.logger.info("TYPEWRITER: \(typewriterCharIndex)/\(fullContent.count) chars in \(String(format: "%.2f", elapsed))s (\(Int(rate)) chars/sec)")
            typewriterLastLoggedIndex = typewriterCharIndex
        }

        // Update the cell through the data source. reconfigureItems updates content
        // without triggering height recalculation (fast). Periodically use reloadItems
        // to force height recalculation as the cell content grows beyond viewport.
        let now = Date()
        let needsHeightUpdate = now.timeIntervalSince(typewriterLastLayoutUpdate) >= typewriterConfig.layoutUpdateInterval

        var snapshot = dataSource.snapshot()
        if needsHeightUpdate {
            snapshot.reloadItems([turnId])
            typewriterLastLayoutUpdate = now
        } else {
            snapshot.reconfigureItems([turnId])
        }

        let offsetBefore = tableView.contentOffset
        UIView.performWithoutAnimation {
            dataSource.apply(snapshot, animatingDifferences: false)
            if needsHeightUpdate {
                tableView.layoutIfNeeded()
                tableView.setContentOffset(offsetBefore, animated: false)
            }
        }

        if needsHeightUpdate {
            updateScrollToBottomButtonVisibility()
        }

        // Calculate next delay
        var nextDelay = typewriterConfig.tickInterval
        let lastChar = fullContent[fullContent.index(before: endIndex)]
        if lastChar == "." || lastChar == "!" || lastChar == "?" {
            nextDelay += typewriterConfig.pauseAtPeriod
        } else if lastChar == "\n" {
            nextDelay += typewriterConfig.pauseAtNewline
        }

        scheduleNextTypewriterTick(delay: nextDelay)
    }

    private func finishTypewriterEffect() {
        guard let turnId = typewriterTurnId,
              let fullContent = typewriterFullContent,
              let index = turns.firstIndex(where: { $0.id == turnId })
        else {
            stopTypewriterEffect()
            return
        }

        let elapsed = Date().timeIntervalSince(typewriterStartTime)
        let rate = elapsed > 0 ? Double(fullContent.count) / elapsed : 0
        Self.logger.info("TYPEWRITER: Finished \(fullContent.count) chars in \(String(format: "%.2f", elapsed))s (\(Int(rate)) chars/sec)")

        turns[index].answer = fullContent
        turns[index].state = .complete

        let scrollPositionBefore = tableView.contentOffset

        // Force height recalculation using reloadData (safe with diffable data source)
        // The diffable data source will re-create the snapshot from current state
        UIView.performWithoutAnimation {
            // Re-apply snapshot to update cell
            var snapshot = NSDiffableDataSourceSnapshot<Section, Turn.ID>()
            snapshot.appendSections([.main])
            snapshot.appendItems(turns.map(\.id))
            dataSource.applySnapshotUsingReloadData(snapshot)

            tableView.layoutIfNeeded()
            tableView.setContentOffset(scrollPositionBefore, animated: false)
        }

        updateScrollToBottomButtonVisibility()
        stopTypewriterEffect()
    }

    private func stopTypewriterEffect() {
        typewriterTimer?.invalidate()
        typewriterTimer = nil
        typewriterTurnId = nil
        typewriterFullContent = nil
        typewriterCharIndex = 0
        typewriterLastLayoutUpdate = .distantPast
        typewriterStartTime = .distantPast
        typewriterLastLoggedIndex = 0
    }
}

// MARK: - UITableViewDelegate

extension BookChatViewController: UITableViewDelegate {
    public func tableView(_: UITableView, heightForRowAt _: IndexPath) -> CGFloat {
        // Use automatic dimension - the TurnCell's spacer constraint handles minimum height
        // For active turns: spacerHeight = max(0, viewportHeight - contentHeight)
        // This ensures the cell fills viewport initially and grows when content exceeds it
        UITableView.automaticDimension
    }

    public func tableView(_: UITableView, estimatedHeightForRowAt _: IndexPath) -> CGFloat {
        100
    }

    public func scrollViewDidScroll(_: UIScrollView) {
        updateScrollToBottomButtonVisibility()
    }
}

// MARK: - UITextViewDelegate

extension BookChatViewController: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        updateTextViewHeight()
    }

    public func textView(_: UITextView, shouldChangeTextIn _: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            sendMessage()
            return false
        }
        return true
    }
}

// MARK: - UIPopoverPresentationControllerDelegate

extension BookChatViewController: UIPopoverPresentationControllerDelegate {
    public func adaptivePresentationStyle(for _: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }
}

// MARK: - TurnCell

private final class TurnCell: UITableViewCell {
    private let fontManager = FontScaleManager.shared

    // Content views
    private let contentStack = UIStackView()
    private let promptBubble = UIView()
    private let promptTextView = UITextView()
    private let answerBubble = UIView()
    private let answerTextView = UITextView()

    // Constraints - minimum height for active cells (fills viewport)
    private var minHeightConstraint: NSLayoutConstraint?

    // State
    private var currentViewportHeight: CGFloat = 0
    private var isActiveCell = false
    private var currentPromptText: String?

    // Callbacks
    var onCopyPrompt: (() -> Void)?
    var onCopyAnswer: (() -> Void)?
    var onShowExecutionDetails: (() -> Void)?
    var onCopyDebugTranscript: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onCopyPrompt = nil
        onCopyAnswer = nil
        onShowExecutionDetails = nil
        onCopyDebugTranscript = nil
        promptTextView.attributedText = nil
        answerTextView.attributedText = nil
        currentPromptText = nil
        isActiveCell = false
        minHeightConstraint?.isActive = false
    }

    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none

        // Content stack (vertical)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.alignment = .fill
        contentView.addSubview(contentStack)

        // Prompt bubble (user message - right aligned)
        promptBubble.translatesAutoresizingMaskIntoConstraints = false
        promptBubble.backgroundColor = .systemBlue
        promptBubble.layer.cornerRadius = 12
        promptBubble.clipsToBounds = true

        promptTextView.isEditable = false
        promptTextView.isScrollEnabled = false
        promptTextView.textContainerInset = UIEdgeInsets(top: 12, left: 14, bottom: 16, right: 14)
        promptTextView.textContainer.lineFragmentPadding = 0
        promptTextView.backgroundColor = .clear
        promptBubble.addSubview(promptTextView)
        promptTextView.translatesAutoresizingMaskIntoConstraints = false

        // Wrapper for right alignment
        let promptWrapper = UIView()
        promptWrapper.translatesAutoresizingMaskIntoConstraints = false
        promptWrapper.addSubview(promptBubble)
        contentStack.addArrangedSubview(promptWrapper)

        // Answer bubble (assistant message - left aligned)
        answerBubble.translatesAutoresizingMaskIntoConstraints = false
        answerBubble.backgroundColor = .clear
        answerBubble.layer.cornerRadius = 12
        answerBubble.clipsToBounds = true

        answerTextView.isEditable = false
        answerTextView.isScrollEnabled = false
        answerTextView.textContainerInset = UIEdgeInsets(top: 12, left: 14, bottom: 16, right: 14)
        answerTextView.textContainer.lineFragmentPadding = 0
        answerTextView.backgroundColor = .clear
        answerTextView.accessibilityIdentifier = "turn-answer"
        answerBubble.addSubview(answerTextView)
        answerTextView.translatesAutoresizingMaskIntoConstraints = false

        // Wrapper for left alignment
        let answerWrapper = UIView()
        answerWrapper.translatesAutoresizingMaskIntoConstraints = false
        answerWrapper.addSubview(answerBubble)
        contentStack.addArrangedSubview(answerWrapper)

        // Minimum height constraint for active cells (fills viewport)
        // This is inactive by default and activated when the cell is for an active turn
        let minHeight = contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0)
        minHeight.isActive = false
        minHeightConstraint = minHeight

        NSLayoutConstraint.activate([
            // Use 16pt top padding to ensure prompt isn't clipped at viewport edge
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            // Use lessThanOrEqualTo so content stays at top, doesn't stretch to fill cell
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),

            // Prompt bubble - right aligned with min width
            promptBubble.topAnchor.constraint(equalTo: promptWrapper.topAnchor),
            promptBubble.bottomAnchor.constraint(equalTo: promptWrapper.bottomAnchor),
            promptBubble.trailingAnchor.constraint(equalTo: promptWrapper.trailingAnchor),
            promptBubble.leadingAnchor.constraint(greaterThanOrEqualTo: promptWrapper.leadingAnchor, constant: 40),

            promptTextView.topAnchor.constraint(equalTo: promptBubble.topAnchor),
            promptTextView.leadingAnchor.constraint(equalTo: promptBubble.leadingAnchor),
            promptTextView.trailingAnchor.constraint(equalTo: promptBubble.trailingAnchor),
            promptTextView.bottomAnchor.constraint(equalTo: promptBubble.bottomAnchor),

            // Answer bubble - left aligned with min width
            answerBubble.topAnchor.constraint(equalTo: answerWrapper.topAnchor),
            answerBubble.bottomAnchor.constraint(equalTo: answerWrapper.bottomAnchor),
            answerBubble.leadingAnchor.constraint(equalTo: answerWrapper.leadingAnchor),
            answerBubble.trailingAnchor.constraint(lessThanOrEqualTo: answerWrapper.trailingAnchor, constant: -40),

            answerTextView.topAnchor.constraint(equalTo: answerBubble.topAnchor),
            answerTextView.leadingAnchor.constraint(equalTo: answerBubble.leadingAnchor),
            answerTextView.trailingAnchor.constraint(equalTo: answerBubble.trailingAnchor),
            answerTextView.bottomAnchor.constraint(equalTo: answerBubble.bottomAnchor),
        ])

        // Context menu for bubbles
        let promptContextMenu = UIContextMenuInteraction(delegate: self)
        promptBubble.addInteraction(promptContextMenu)

        let answerContextMenu = UIContextMenuInteraction(delegate: self)
        answerBubble.addInteraction(answerContextMenu)
    }

    func configure(with turn: Turn, viewportHeight: CGFloat, isActive: Bool) {
        currentViewportHeight = viewportHeight
        isActiveCell = isActive

        // Prompt - skip re-render if unchanged (avoids wasteful markdown parsing during typewriter)
        if turn.prompt != currentPromptText {
            currentPromptText = turn.prompt
            promptTextView.attributedText = renderMarkdown(turn.prompt, font: fontManager.bodyFont, color: .white)
        }

        // Answer (may be empty during pending/streaming)
        if turn.answer.isEmpty {
            answerBubble.isHidden = true
        } else {
            answerBubble.isHidden = false
            answerTextView.attributedText = renderMarkdown(turn.answer, font: fontManager.bodyFont, color: .label)
        }

        // Active cells fill the viewport using a minimum height constraint
        // No dynamic calculation needed - Auto Layout handles it
        if isActive {
            minHeightConstraint?.constant = viewportHeight
            minHeightConstraint?.isActive = true
        } else {
            minHeightConstraint?.isActive = false
        }
    }

    func updateTypewriterAnswer(_ text: String) {
        answerBubble.isHidden = text.isEmpty
        answerTextView.attributedText = renderMarkdown(text, font: fontManager.bodyFont, color: .label)
        // No spacer recalculation needed - minHeightConstraint handles viewport fill
        // Content grows naturally and cell expands when it exceeds viewport
    }

    private func renderMarkdown(_ text: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let processedText = preprocessHeaders(text)

        if let attributed = try? AttributedString(markdown: processedText, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            let mutable = NSMutableAttributedString(attributed)
            let fullRange = NSRange(location: 0, length: mutable.length)
            mutable.addAttribute(.font, value: font, range: fullRange)
            mutable.addAttribute(.foregroundColor, value: color, range: fullRange)

            mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
                guard let existingFont = value as? UIFont else { return }
                let traits = existingFont.fontDescriptor.symbolicTraits

                if traits.contains(.traitBold), traits.contains(.traitItalic) {
                    if let boldItalicDescriptor = font.fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) {
                        mutable.addAttribute(.font, value: UIFont(descriptor: boldItalicDescriptor, size: font.pointSize), range: range)
                    }
                } else if traits.contains(.traitBold) {
                    if let boldDescriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) {
                        mutable.addAttribute(.font, value: UIFont(descriptor: boldDescriptor, size: font.pointSize), range: range)
                    }
                } else if traits.contains(.traitItalic) {
                    if let italicDescriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
                        mutable.addAttribute(.font, value: UIFont(descriptor: italicDescriptor, size: font.pointSize), range: range)
                    }
                }
            }

            mutable.enumerateAttribute(.inlinePresentationIntent, in: fullRange, options: []) { value, range, _ in
                guard let intent = value as? InlinePresentationIntent, intent.contains(.code) else { return }
                let monoFont = UIFont.monospacedSystemFont(ofSize: font.pointSize * 0.9, weight: .regular)
                mutable.addAttribute(.font, value: monoFont, range: range)
                mutable.addAttribute(.backgroundColor, value: UIColor.systemFill, range: range)
            }

            return mutable
        }

        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
    }

    private func preprocessHeaders(_ text: String) -> String {
        var result = text
        let headerPattern = #"(?m)^(#{1,6})\s+(.+)$"#
        if let regex = try? NSRegularExpression(pattern: headerPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "**$2**")
        }
        return result
    }
}

// MARK: - TurnCell Context Menu

extension TurnCell: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation _: CGPoint
    ) -> UIContextMenuConfiguration? {
        let isPromptBubble = interaction.view === promptBubble

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }

            var actions: [UIAction] = []

            if isPromptBubble {
                let copyAction = UIAction(
                    title: "Copy",
                    image: UIImage(systemName: "doc.on.doc")
                ) { [weak self] _ in
                    self?.onCopyPrompt?()
                }
                actions.append(copyAction)
            } else {
                let copyAction = UIAction(
                    title: "Copy",
                    image: UIImage(systemName: "doc.on.doc")
                ) { [weak self] _ in
                    self?.onCopyAnswer?()
                }
                actions.append(copyAction)

                if let showDetails = onShowExecutionDetails {
                    let detailsAction = UIAction(
                        title: "Execution Details",
                        image: UIImage(systemName: "text.alignleft")
                    ) { _ in
                        showDetails()
                    }
                    actions.append(detailsAction)
                }

                if let copyTranscript = onCopyDebugTranscript {
                    let transcriptAction = UIAction(
                        title: "Copy Debug Transcript",
                        image: UIImage(systemName: "doc.on.clipboard")
                    ) { _ in
                        copyTranscript()
                    }
                    actions.append(transcriptAction)
                }
            }

            return UIMenu(title: "", children: actions)
        }
    }
}

// MARK: - Chat Viewport Geometry

private struct ChatViewportGeometry {
    let scrollView: UIScrollView

    private var inset: UIEdgeInsets { scrollView.adjustedContentInset }

    /// Visible height between adjusted insets (keyboard included)
    var visibleHeight: CGFloat {
        scrollView.bounds.height - inset.top - inset.bottom
    }

    /// The Y coordinate in content space where visible content starts
    var visibleTopAnchor: CGFloat {
        scrollView.contentOffset.y + inset.top
    }

    /// The Y coordinate in content space where visible content ends
    var visibleBottomAnchor: CGFloat {
        scrollView.contentOffset.y + scrollView.bounds.height - inset.bottom
    }

    /// The Y coordinate of the last content in content space
    var contentBottom: CGFloat {
        scrollView.contentSize.height
    }

    /// How far content extends below visible bottom anchor
    var distanceToBottom: CGFloat {
        contentBottom - visibleBottomAnchor
    }

    /// Scroll offset to align content bottom with visible bottom anchor
    var offsetToShowBottom: CGPoint {
        let targetOffset = contentBottom - scrollView.bounds.height + inset.bottom
        return CGPoint(x: 0, y: max(-inset.top, targetOffset))
    }

    /// Scroll offset to position a content Y coordinate at the visible top anchor
    func offsetToShowAtTop(_ contentY: CGFloat) -> CGPoint {
        CGPoint(x: 0, y: contentY - inset.top)
    }
}

// MARK: - Model Picker View Controller

private final class ModelPickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let models = OpenRouterConfig.availableModels
    private var selectedModelId: String
    private let onSelect: (OpenRouterConfig.Model) -> Void
    private let fontManager = FontScaleManager.shared

    init(selectedModelId: String, onSelect: @escaping (OpenRouterConfig.Model) -> Void) {
        self.selectedModelId = selectedModelId
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ModelCell.self, forCellReuseIdentifier: "ModelCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        models.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ModelCell", for: indexPath) as! ModelCell
        let model = models[indexPath.row]
        cell.configure(with: model, isSelected: model.id == selectedModelId)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let model = models[indexPath.row]
        selectedModelId = model.id
        onSelect(model)
        dismiss(animated: true)
    }
}

// MARK: - Model Cell

private final class ModelCell: UITableViewCell {
    private let fontManager = FontScaleManager.shared

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with model: OpenRouterConfig.Model, isSelected: Bool) {
        var content = defaultContentConfiguration()
        content.text = model.name
        content.textProperties.font = fontManager.bodyFont

        let inputStr = formatPrice(model.inputCost)
        let outputStr = formatPrice(model.outputCost)
        let contextStr = formatContextLength(model.contextLength)
        content.secondaryText = "\(inputStr) in  ·  \(outputStr) out  ·  \(contextStr) context"
        content.secondaryTextProperties.font = fontManager.captionFont
        content.secondaryTextProperties.color = .secondaryLabel

        contentConfiguration = content
        accessoryType = isSelected ? .checkmark : .none
    }

    private func formatPrice(_ cost: Double) -> String {
        if cost < 1.0 {
            String(format: "$%.2f", cost)
        } else {
            String(format: "$%.0f", cost)
        }
    }

    private func formatContextLength(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            let millions = Double(tokens) / 1_000_000.0
            if millions == floor(millions) {
                return String(format: "%.0fM", millions)
            }
            return String(format: "%.1fM", millions)
        } else {
            let thousands = tokens / 1000
            return "\(thousands)K"
        }
    }
}
