import UIKit
import ReaderCore
import OSLog
import MapKit

/// Chat interface for conversing with the LLM about a book
public final class BookChatViewController: UIViewController {
    private static let logger = Log.logger(category: "chat")
    private let context: BookContext
    private let agentService = ReaderAgentService()
    private let initialSelection: SelectionPayload?
    private let conversationId: UUID?
    private let fontManager = FontScaleManager.shared

    private var conversation: Conversation
    private var conversationHistory: [AgentMessage] = []
    private var isLoading = false

    var onToggleDrawer: (() -> Void)?

    // MARK: - UI Components

    private let tableView = UITableView()
    private let inputContainer = UIView()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let buttonRow = UIView()
    private let modelButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let statusBubble = UIView()
    private let statusLabel = UILabel()

    private var messages: [ChatMessage] = []
    private var messageTraces: [UUID: AgentExecutionTrace] = [:]

    private var inputContainerBottomConstraint: NSLayoutConstraint?
    private var textViewHeightConstraint: NSLayoutConstraint?

    private let minTextViewHeight: CGFloat = 36
    private let maxTextViewHeight: CGFloat = 200
    private let buttonRowHeight: CGFloat = 44

    // MARK: - Initialization

    public init(context: BookContext, selection: SelectionPayload? = nil, conversationId: UUID? = nil) {
        self.context = context
        self.initialSelection = selection
        self.conversationId = conversationId

        // Load existing conversation or create new one
        if let convId = conversationId,
           let existingConv = ConversationStorage.shared.getConversation(id: convId) {
            self.conversation = existingConv
        } else {
            // Create new conversation
            self.conversation = Conversation(
                title: "New Chat",
                bookTitle: context.bookTitle,
                bookAuthor: context.bookAuthor,
                messages: []
            )
        }

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        Self.logger.debug("Chat UI opened for book: \(self.context.bookTitle, privacy: .public)")
        setupUI()
        setupKeyboardObservers()
        setupFontScaleObserver()
        addWelcomeMessage()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
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
        // Update fonts
        textView.font = fontManager.bodyFont
        placeholderLabel.font = fontManager.bodyFont
        modelButton.titleLabel?.font = fontManager.captionFont
        updateTextViewHeight()

        // Reload table to update message cells
        tableView.reloadData()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Chat"

        // Navigation bar
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal"),
            style: .plain,
            target: self,
            action: #selector(toggleDrawer)
        )

        // Debug transcript button
        let debugButton = UIBarButtonItem(
            image: UIImage(systemName: "doc.text"),
            style: .plain,
            target: self,
            action: #selector(copyDebugTranscript)
        )

        let closeButton = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(dismissChat)
        )

        navigationItem.rightBarButtonItems = [closeButton, debugButton]

        // Table view for messages
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.keyboardDismissMode = .interactive
        tableView.register(ChatMessageCell.self, forCellReuseIdentifier: "MessageCell")
        view.addSubview(tableView)

        // Input container - single rounded rectangle
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.backgroundColor = .secondarySystemBackground
        inputContainer.layer.cornerRadius = 16
        inputContainer.clipsToBounds = true
        view.addSubview(inputContainer)

        // Text view - transparent, sits inside the container
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.font = fontManager.bodyFont
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        textView.isScrollEnabled = false
        textView.delegate = self
        inputContainer.addSubview(textView)

        // Placeholder label
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = "Ask about the book..."
        placeholderLabel.font = fontManager.bodyFont
        placeholderLabel.textColor = .placeholderText
        inputContainer.addSubview(placeholderLabel)

        // Button row - at the bottom of the container
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.backgroundColor = .clear
        inputContainer.addSubview(buttonRow)

        // Model selector button - left side of button row
        modelButton.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.plain()
        config.title = OpenRouterConfig.modelDisplayName
        config.baseForegroundColor = .secondaryLabel
        config.image = UIImage(systemName: "chevron.down")
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 10, weight: .regular, scale: .small)
        config.imagePlacement = .trailing
        config.imagePadding = 4
        modelButton.configuration = config
        modelButton.showsMenuAsPrimaryAction = true
        modelButton.menu = createModelMenu()
        buttonRow.addSubview(modelButton)

        // Send button - in the button row, right-aligned
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        sendButton.tintColor = .systemBlue
        sendButton.contentHorizontalAlignment = .fill
        sendButton.contentVerticalAlignment = .fill
        sendButton.addTarget(self, action: #selector(sendMessage), for: .touchUpInside)
        buttonRow.addSubview(sendButton)

        // Loading indicator
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        buttonRow.addSubview(loadingIndicator)

        // Status bubble - shows what we're waiting for
        statusBubble.translatesAutoresizingMaskIntoConstraints = false
        statusBubble.backgroundColor = .tertiarySystemFill
        statusBubble.layer.cornerRadius = 12
        statusBubble.isHidden = true
        tableView.addSubview(statusBubble)

        // Status label inside bubble
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = fontManager.captionFont
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusBubble.addSubview(statusLabel)

        // Layout
        let bottomConstraint = inputContainer.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14
        )
        inputContainerBottomConstraint = bottomConstraint

        // Start with minimum height
        let textViewHeight = textView.heightAnchor.constraint(equalToConstant: minTextViewHeight)
        textViewHeightConstraint = textViewHeight

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputContainer.topAnchor, constant: -14),

            // Input container with horizontal margins
            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            bottomConstraint,

            // Text view at top of container
            textView.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 4),
            textView.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -4),
            textViewHeight,

            // Placeholder aligned with text
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 12),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 4),

            // Button row below text view
            buttonRow.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 4),
            buttonRow.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -8),
            buttonRow.heightAnchor.constraint(equalToConstant: 32),

            // Model button in the button row, left side
            modelButton.leadingAnchor.constraint(equalTo: buttonRow.leadingAnchor, constant: 12),
            modelButton.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),

            // Send button in the button row, right side
            sendButton.trailingAnchor.constraint(equalTo: buttonRow.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 28),
            sendButton.heightAnchor.constraint(equalToConstant: 28),

            loadingIndicator.centerXAnchor.constraint(equalTo: sendButton.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),

            // Status bubble - positioned just above the input container
            statusBubble.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusBubble.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -60),
            statusBubble.bottomAnchor.constraint(equalTo: inputContainer.topAnchor, constant: -8),

            // Status label inside bubble
            statusLabel.topAnchor.constraint(equalTo: statusBubble.topAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: statusBubble.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: statusBubble.trailingAnchor, constant: -12),
            statusLabel.bottomAnchor.constraint(equalTo: statusBubble.bottomAnchor, constant: -8)
        ])
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    private func createModelMenu() -> UIMenu {
        let actions = OpenRouterConfig.availableModels.map { model in
            UIAction(
                title: model.name,
                state: model.id == OpenRouterConfig.model ? .on : .off
            ) { [weak self] _ in
                OpenRouterConfig.model = model.id
                self?.modelButton.setTitle(model.name, for: .normal)
                self?.modelButton.menu = self?.createModelMenu()
            }
        }
        return UIMenu(title: "Select Model", children: actions)
    }

    private func addWelcomeMessage() {
        // Load existing conversation messages if this is an existing conversation
        if conversationId != nil && !conversation.messages.isEmpty {
            for storedMsg in conversation.messages {
                let role: ChatMessage.Role = storedMsg.role == .user ? .user : .assistant
                let hasTrace = storedMsg.executionTrace != nil
                let message = ChatMessage(role: role, content: storedMsg.content, isCollapsed: hasTrace, hasTrace: hasTrace)
                messages.append(message)

                // Restore execution trace if available
                if let trace = storedMsg.executionTrace {
                    messageTraces[message.id] = trace
                }

                // Add to conversation history for the agent
                if storedMsg.role == .user {
                    conversationHistory.append(AgentMessage(role: .user, content: storedMsg.content))
                } else {
                    conversationHistory.append(AgentMessage(
                        role: .assistant,
                        content: storedMsg.content,
                        toolCalls: nil
                    ))
                }
            }
        } else if let selection = initialSelection {
            // Strip quotes from selection, wrap in quotes, and format with "selection: "
            let cleanedSelection = selection.selectedText.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
            let formattedText = "selection: \"\(cleanedSelection)\"\n\n"
            textView.text = formattedText
            placeholderLabel.isHidden = true

            // Delay height calculation until view is laid out, then focus and position cursor
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.view.layoutIfNeeded()
                self.updateTextViewHeight()
                self.textView.becomeFirstResponder()
                // Position cursor at the end (after the two newlines)
                let endPosition = self.textView.endOfDocument
                self.textView.selectedTextRange = self.textView.textRange(from: endPosition, to: endPosition)
                // Scroll to make cursor visible
                self.textView.scrollRangeToVisible(NSRange(location: self.textView.text.count, length: 0))
            }
        } else {
            // Show welcome message if no selection
            let welcome = "I can help you understand this book. Try asking:\n\n" +
                "- \"Summarize this chapter\"\n" +
                "- \"Who is [character name]?\"\n" +
                "- \"Find mentions of [topic]\"\n" +
                "- \"Explain what's happening here\""

            messages.append(ChatMessage(role: .assistant, content: welcome))
        }

        tableView.reloadData()
    }

    // MARK: - Actions

    @objc private func toggleDrawer() {
        onToggleDrawer?()
    }

    @objc private func dismissChat() {
        // Save conversation before dismissing
        saveAndSummarizeConversation()
        dismiss(animated: true)
    }

    @objc private func copyDebugTranscript() {
        let transcript = buildDebugTranscript()
        UIPasteboard.general.string = transcript

        // Show brief confirmation
        let alert = UIAlertController(
            title: "Copied",
            message: "Debug transcript copied to clipboard (\(transcript.count) chars)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func buildDebugTranscript() -> String {
        var transcript = "=== DEBUG TRANSCRIPT ===\n"
        transcript += "Book: \(context.bookTitle)"
        if let author = context.bookAuthor {
            transcript += " by \(author)"
        }
        transcript += "\nGenerated: \(Date())\n"
        transcript += "========================\n\n"

        // Render unified timeline from all message traces
        var stepIndex = 0
        for message in messages {
            guard let trace = messageTraces[message.id] else { continue }

            for step in trace.timeline {
                transcript += formatTimelineStep(step, index: stepIndex)
                stepIndex += 1
            }
        }

        return transcript
    }

    private func formatTimelineStep(_ step: TimelineStep, index: Int) -> String {
        switch step {
        case .user(let content):
            let preview = content.count > 100 ? String(content.prefix(100)) + "..." : content
            return "[\(index)] USER: \(preview)\n\n"

        case .llm(let exec):
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

        case .tool(let exec):
            var line = "[\(index)] TOOL \(exec.functionName) - \(String(format: "%.3f", exec.executionTime))s\n"
            // Compact args on one line
            let argsPreview = exec.arguments.replacingOccurrences(of: "\n", with: " ")
            line += "    args: \(argsPreview)\n"
            // Truncated result
            let resultPreview = exec.result.count > 150
                ? String(exec.result.prefix(150)).replacingOccurrences(of: "\n", with: " ") + "..."
                : exec.result.replacingOccurrences(of: "\n", with: " ")
            line += "    result: \(resultPreview)\n"
            return line + "\n"

        case .assistant(let content):
            let preview = content.count > 200 ? String(content.prefix(200)) + "..." : content
            return "[\(index)] ASSISTANT:\n\(preview)\n\n"
        }
    }

    private func timelineStepLabel(_ step: TimelineStep) -> String {
        switch step {
        case .user:
            return "User message"
        case .llm(let exec):
            if let tools = exec.requestedTools, !tools.isEmpty {
                return "LLM → \(tools.joined(separator: ", "))"
            }
            return "LLM (final response)"
        case .tool(let exec):
            return exec.functionName
        case .assistant:
            return "Assistant response"
        }
    }

    private func saveAndSummarizeConversation() {
        // Convert UI messages to stored messages (exclude system messages)
        let storedMessages = messages.compactMap { msg -> StoredMessage? in
            switch msg.role {
            case .user:
                return StoredMessage(role: .user, content: msg.content)
            case .assistant:
                // Include execution trace if available
                let trace = messageTraces[msg.id]
                return StoredMessage(role: .assistant, content: msg.content, executionTrace: trace)
            case .system:
                return nil // Don't save system/context messages
            }
        }

        // Only save if there's actual conversation (not just welcome message)
        guard storedMessages.count > 1 else {
            return
        }

        // Update conversation with messages
        conversation.messages = storedMessages
        conversation.updatedAt = Date()

        // Auto-summarize if title is still "New Chat"
        if conversation.title == "New Chat" {
            summarizeConversation()
        } else {
            // Just save without summarizing
            ConversationStorage.shared.saveConversation(conversation)
        }
    }

    private func summarizeConversation() {
        // Build a prompt to summarize the conversation
        let conversationText = conversation.messages.prefix(6).map { msg in
            "\(msg.role == .user ? "User" : "Assistant"): \(msg.content)"
        }.joined(separator: "\n")

        let summaryPrompt = """
        Generate a short title (3-5 words max) for this conversation:

        \(conversationText)

        Respond with ONLY the title, nothing else.
        """

        // Use the agent service to generate a summary
        Task {
            do {
                let result = try await agentService.chat(
                    message: summaryPrompt,
                    context: context,
                    history: []
                )

                await MainActor.run {
                    // Use the response as the title
                    let title = result.response.content
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .prefix(50) // Limit length
                    self.conversation.title = String(title)
                    ConversationStorage.shared.saveConversation(self.conversation)
                }
            } catch {
                // Fallback: use first user message as title
                await MainActor.run {
                    if let firstUser = self.conversation.messages.first(where: { $0.role == .user }) {
                        let title = firstUser.content.prefix(30)
                        self.conversation.title = String(title) + "..."
                    }
                    ConversationStorage.shared.saveConversation(self.conversation)
                }
            }
        }
    }

    @objc private func sendMessage() {
        guard let text = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              !isLoading else {
            return
        }

        // Add user message
        messages.append(ChatMessage(role: .user, content: text))
        tableView.reloadData()
        scrollToBottom()

        textView.text = ""
        placeholderLabel.isHidden = false
        updateTextViewHeight()
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
                    // Update history
                    self.conversationHistory = result.updatedHistory

                    // Create message with trace if available (collapsed by default)
                    let hasTrace = result.response.executionTrace != nil
                    let message = ChatMessage(role: .assistant, content: result.response.content, isCollapsed: hasTrace, hasTrace: hasTrace)

                    // Store trace if available
                    if let trace = result.response.executionTrace {
                        self.messageTraces[message.id] = trace
                    }

                    messages.append(message)
                    tableView.reloadData()
                    scrollToBottom()
                    setLoading(false)
                }
            } catch {
                await MainActor.run {
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: "Error: \(error.localizedDescription)"
                    ))
                    tableView.reloadData()
                    scrollToBottom()
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
            // Show status bubble with model name
            statusLabel.text = "Waiting on \(OpenRouterConfig.modelDisplayName)..."
            statusBubble.isHidden = false
            statusBubble.alpha = 0
            UIView.animate(withDuration: 0.2) {
                self.statusBubble.alpha = 1
            }
        } else {
            loadingIndicator.stopAnimating()
            // Hide status bubble
            UIView.animate(withDuration: 0.2) {
                self.statusBubble.alpha = 0
            } completion: { _ in
                self.statusBubble.isHidden = true
            }
            // Restore focus to text field after loading completes
            textView.becomeFirstResponder()
        }
    }

    private func updateTextViewHeight() {
        let size = CGSize(width: textView.frame.width, height: .infinity)
        let estimatedSize = textView.sizeThatFits(size)

        // Use OS-provided height, clamped to max
        let newHeight = min(estimatedSize.height, maxTextViewHeight)
        textViewHeightConstraint?.constant = max(minTextViewHeight, newHeight)

        // Enable scrolling only when content exceeds max height
        textView.isScrollEnabled = estimatedSize.height > maxTextViewHeight

        UIView.animate(withDuration: 0.1) {
            self.view.layoutIfNeeded()
        }
    }

    private func scrollToBottom() {
        guard !messages.isEmpty else { return }
        let indexPath = IndexPath(row: messages.count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
    }

    // MARK: - Keyboard

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }

        let keyboardHeight = keyboardFrame.height - view.safeAreaInsets.bottom
        inputContainerBottomConstraint?.constant = -keyboardHeight

        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }

        scrollToBottom()
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }

        inputContainerBottomConstraint?.constant = 0

        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Trace Helpers

    /// Extract map data from show_map tool results in trace
    private func extractMapsFromTrace(_ trace: AgentExecutionTrace?) -> [(lat: Double, lon: Double, name: String)] {
        guard let trace = trace else { return [] }

        var maps: [(lat: Double, lon: Double, name: String)] = []

        for execution in trace.toolExecutions {
            if execution.functionName == "show_map" && execution.success {
                // Parse MAP_RESULT:lat,lon,name format
                let result = execution.result
                if result.hasPrefix("MAP_RESULT:") {
                    let data = String(result.dropFirst("MAP_RESULT:".count))
                    let parts = data.split(separator: ",", maxSplits: 2)
                    if parts.count >= 3,
                       let lat = Double(parts[0]),
                       let lon = Double(parts[1]) {
                        let name = String(parts[2])
                        maps.append((lat: lat, lon: lon, name: name))
                    }
                }
            }
        }

        return maps
    }

    private func formatTraceForDisplay(_ trace: AgentExecutionTrace, collapsed: Bool) -> String {
        let totalTime = trace.totalExecutionTime
        let stepCount = trace.timeline.count

        if collapsed {
            return "Execution Details ▶  (\(stepCount) steps, \(String(format: "%.2f", totalTime))s total)"
        }

        var text = "Execution Details ▼\n\n"

        // Book context section
        text += "BOOK CONTEXT\n"
        text += "• \(trace.bookContext.title)"
        if let author = trace.bookContext.author {
            text += " by \(author)"
        }
        text += "\n"
        if let chapter = trace.bookContext.currentChapter {
            text += "• Current: \(chapter)\n"
        }
        text += "• Position: \(trace.bookContext.position)\n"
        if let excerpt = trace.bookContext.surroundingText {
            let excerptPrefix = excerpt.prefix(100)
            text += "• Context: \"\(excerptPrefix)...\"\n"
        }

        // Tools section (detailed)
        if !trace.toolExecutions.isEmpty {
            text += "\nTOOLS CALLED\n"
            for (index, tool) in trace.toolExecutions.enumerated() {
                text += "\n\(index + 1). \(tool.functionName)\n"
                let prettyArgs = tool.arguments.prettyJSON()
                text += "   Input: \(prettyArgs.prefix(150))\n"
                text += "   Result: \(tool.result.prefix(200))\n"
                text += "   Time: \(String(format: "%.2f", tool.executionTime))s\n"
                if !tool.success, let error = tool.error {
                    text += "   ⚠️ Error: \(error)\n"
                }
            }
        }

        // Timeline section
        if !trace.timeline.isEmpty {
            text += "\nTIMELINE\n"
            for (index, step) in trace.timeline.enumerated() {
                let timeStr = String(format: "%5.2fs", step.executionTime)
                text += "\(index + 1). [\(timeStr)] \(timelineStepLabel(step))\n"
            }
            text += "─────────────────────\n"
            text += "   Total: \(String(format: "%.2f", totalTime))s\n"
        }

        return text
    }
}

// MARK: - UITableViewDataSource

extension BookChatViewController: UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MessageCell", for: indexPath) as! ChatMessageCell
        let message = messages[indexPath.row]
        cell.configure(with: message)

        // Display trace if available
        if message.hasTrace, let trace = messageTraces[message.id] {
            let traceText = formatTraceForDisplay(trace, collapsed: message.isCollapsed)
            cell.setTraceText(traceText)

            // Extract and display maps from trace
            let maps = extractMapsFromTrace(trace)
            cell.setMaps(maps)

            // Set up tap handler to toggle trace
            cell.onTap = { [weak self] in
                guard let self = self else { return }
                let wasCollapsed = self.messages[indexPath.row].isCollapsed
                self.messages[indexPath.row].isCollapsed.toggle()
                self.tableView.reloadRows(at: [indexPath], with: .automatic)

                // If expanding, scroll to show the expanded content
                if wasCollapsed {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.tableView.scrollToRow(at: indexPath, at: .top, animated: true)
                    }
                }
            }
        } else if message.role == .system {
            // Set up tap handler for system messages to toggle collapsed state
            cell.onTap = { [weak self] in
                guard let self = self else { return }
                let wasCollapsed = self.messages[indexPath.row].isCollapsed
                self.messages[indexPath.row].isCollapsed.toggle()
                self.tableView.reloadRows(at: [indexPath], with: .automatic)

                // If expanding, scroll to show the expanded content
                if wasCollapsed {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.tableView.scrollToRow(at: indexPath, at: .top, animated: true)
                    }
                }
            }
        } else {
            cell.setTraceText(nil)
            cell.onTap = nil
        }

        return cell
    }
}

// MARK: - UITableViewDelegate

extension BookChatViewController: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    public func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
}

// MARK: - UITextViewDelegate

extension BookChatViewController: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        updateTextViewHeight()
    }

    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Send message on return key if shift is not held
        if text == "\n" {
            sendMessage()
            return false
        }
        return true
    }
}

// MARK: - Chat Message Model

private struct ChatMessage {
    enum Role {
        case user
        case assistant
        case system
    }

    let id: UUID
    let role: Role
    let content: String
    let title: String? // For collapsed system messages
    var isCollapsed: Bool // For system messages
    let hasTrace: Bool // Whether this message has an execution trace

    init(role: Role, content: String, title: String? = nil, isCollapsed: Bool = false, hasTrace: Bool = false) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.title = title
        self.isCollapsed = isCollapsed
        self.hasTrace = hasTrace
    }
}

// MARK: - Chat Message Cell

private final class ChatMessageCell: UITableViewCell {
    private let bubbleView = UIView()
    private let contentStack = UIStackView()  // Main vertical stack for all content
    private let messageLabel = UILabel()
    private let imageContainerView = UIStackView()
    private let traceLabel = UILabel()
    private let fontManager = FontScaleManager.shared
    var onTap: (() -> Void)?

    // Track active image loading tasks
    private var imageLoadTasks: [URLSessionDataTask] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Cancel any pending image loads
        imageLoadTasks.forEach { $0.cancel() }
        imageLoadTasks.removeAll()
        // Clear images
        imageContainerView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        imageContainerView.isHidden = true
    }

    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none

        // Bubble container
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.layer.cornerRadius = 12
        bubbleView.clipsToBounds = true
        contentView.addSubview(bubbleView)

        // Main content stack - handles all vertical layout automatically
        // Hidden views are removed from layout by UIStackView
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.alignment = .fill
        bubbleView.addSubview(contentStack)

        // Message label
        messageLabel.numberOfLines = 0
        messageLabel.font = fontManager.bodyFont
        contentStack.addArrangedSubview(messageLabel)

        // Image container for displaying images/maps
        imageContainerView.axis = .vertical
        imageContainerView.spacing = 8
        imageContainerView.isHidden = true
        contentStack.addArrangedSubview(imageContainerView)

        // Trace label for execution details
        traceLabel.numberOfLines = 0
        traceLabel.font = fontManager.monospacedFont(size: 12)
        traceLabel.textColor = .secondaryLabel
        traceLabel.isHidden = true
        contentStack.addArrangedSubview(traceLabel)

        // Simple constraints: bubble in cell, stack in bubble with padding
        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            contentStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            contentStack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -12)
        ])

        // Add tap gesture for collapsible messages
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        bubbleView.addGestureRecognizer(tap)
        bubbleView.isUserInteractionEnabled = true
    }

    @objc private func handleTap() {
        onTap?()
    }

    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?

    func configure(with message: ChatMessage) {
        // Remove old constraints
        leadingConstraint?.isActive = false
        trailingConstraint?.isActive = false

        // Update trace label font
        traceLabel.font = fontManager.monospacedFont(size: 12)

        // Parse content for images
        let (cleanedContent, images) = parseImagesFromContent(message.content)

        switch message.role {
        case .user:
            bubbleView.backgroundColor = .systemBlue
            messageLabel.textColor = .white
            messageLabel.font = fontManager.bodyFont
            messageLabel.text = cleanedContent
            leadingConstraint = bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 60)
            trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)

        case .assistant:
            bubbleView.backgroundColor = .secondarySystemBackground
            messageLabel.textColor = .label
            messageLabel.font = fontManager.bodyFont
            messageLabel.text = cleanedContent
            leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20)
            trailingConstraint = bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -60)

        case .system:
            bubbleView.backgroundColor = .tertiarySystemBackground
            messageLabel.textColor = .secondaryLabel
            messageLabel.font = fontManager.scaledFont(size: 14)

            // Show title with disclosure indicator when collapsed, full content when expanded
            if message.isCollapsed {
                messageLabel.text = "\(message.title ?? "Context") ▶"
            } else {
                messageLabel.text = "\(message.title ?? "Context") ▼\n\n\(cleanedContent)"
            }

            // System messages span full width
            leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20)
            trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
        }

        leadingConstraint?.isActive = true
        trailingConstraint?.isActive = true

        // Display images (maps are set separately via setMaps)
        displayMedia(images: images, maps: [])
    }

    func setMaps(_ maps: [(lat: Double, lon: Double, name: String)]) {
        // Add maps to the container
        for map in maps {
            let mapWrapper = createMapView(lat: map.lat, lon: map.lon, name: map.name)
            imageContainerView.addArrangedSubview(mapWrapper)
        }
        if !maps.isEmpty {
            imageContainerView.isHidden = false
        }
    }

    /// Parse markdown-style image syntax from content
    private func parseImagesFromContent(_ content: String) -> (cleanedContent: String, images: [(url: String, caption: String)]) {
        var images: [(url: String, caption: String)] = []
        var cleanedContent = content

        // Pattern: ![caption](url) - standard markdown image syntax
        // Also handles ![[caption]](url) variant
        let pattern = #"!\[+([^\]]*)\]+\(([^)]+)\)"#

        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(cleanedContent.startIndex..., in: cleanedContent)
            let matches = regex.matches(in: cleanedContent, options: [], range: range)

            // Process matches in reverse order to preserve string indices
            for match in matches.reversed() {
                if let captionRange = Range(match.range(at: 1), in: cleanedContent),
                   let urlRange = Range(match.range(at: 2), in: cleanedContent),
                   let fullRange = Range(match.range, in: cleanedContent) {
                    let caption = String(cleanedContent[captionRange])
                    let url = String(cleanedContent[urlRange])
                    images.insert((url: url, caption: caption), at: 0)
                    cleanedContent.removeSubrange(fullRange)
                }
            }
        }

        return (cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines), images)
    }

    private func displayMedia(images: [(url: String, caption: String)], maps: [(lat: Double, lon: Double, name: String)]) {
        // Clear existing content
        imageContainerView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard !images.isEmpty || !maps.isEmpty else {
            imageContainerView.isHidden = true
            return
        }

        imageContainerView.isHidden = false

        // Display maps first
        for map in maps {
            let mapWrapper = createMapView(lat: map.lat, lon: map.lon, name: map.name)
            imageContainerView.addArrangedSubview(mapWrapper)
        }

        // Then display images
        for image in images {
            let imageWrapper = createImageView(url: image.url, caption: image.caption)
            imageContainerView.addArrangedSubview(imageWrapper)
        }
    }

    private func createImageView(url: String, caption: String) -> UIView {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 12
        imageView.clipsToBounds = true
        wrapper.addSubview(imageView)

        let captionLabel = UILabel()
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.text = caption
        captionLabel.font = fontManager.captionFont
        captionLabel.textColor = .secondaryLabel
        captionLabel.textAlignment = .center
        captionLabel.numberOfLines = 2
        wrapper.addSubview(captionLabel)

        // Loading indicator
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        imageView.addSubview(spinner)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 8),
            imageView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 280),

            captionLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 12),
            captionLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            captionLabel.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            captionLabel.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -8),

            spinner.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: imageView.centerYAnchor)
        ])

        // Set a minimum height while loading
        let heightConstraint = imageView.heightAnchor.constraint(equalToConstant: 150)
        heightConstraint.priority = .defaultLow
        heightConstraint.isActive = true

        // Load image async
        if let imageUrl = URL(string: url) {
            let task = URLSession.shared.dataTask(with: imageUrl) { [weak imageView, weak spinner, weak self] data, _, error in
                DispatchQueue.main.async {
                    spinner?.stopAnimating()
                    spinner?.removeFromSuperview()

                    if let data = data, let loadedImage = UIImage(data: data) {
                        imageView?.image = loadedImage

                        // Update height constraint based on aspect ratio
                        let aspectRatio = loadedImage.size.height / loadedImage.size.width
                        let maxWidth = (self?.contentView.bounds.width ?? 300) - 108 // Account for larger margins
                        let calculatedHeight = min(maxWidth * aspectRatio, 280)
                        heightConstraint.constant = calculatedHeight

                        // Trigger table view layout update and scroll to show image
                        if let tableView = self?.superview as? UITableView {
                            UIView.performWithoutAnimation {
                                tableView.beginUpdates()
                                tableView.endUpdates()
                            }
                            // Scroll to show the newly loaded image
                            if let indexPath = tableView.indexPath(for: self!) {
                                tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
                            }
                        }
                    }
                }
            }
            imageLoadTasks.append(task)
            task.resume()
        }

        return wrapper
    }

    private func createMapView(lat: Double, lon: Double, name: String) -> UIView {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        let mapImageView = UIImageView()
        mapImageView.translatesAutoresizingMaskIntoConstraints = false
        mapImageView.contentMode = .scaleAspectFit
        mapImageView.layer.cornerRadius = 12
        mapImageView.clipsToBounds = true
        mapImageView.backgroundColor = .tertiarySystemBackground
        mapImageView.isUserInteractionEnabled = true
        wrapper.addSubview(mapImageView)

        // Add tap to open in Maps app
        let tapGesture = MapTapGestureRecognizer(target: self, action: #selector(mapTapped(_:)))
        tapGesture.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        tapGesture.locationName = name
        mapImageView.addGestureRecognizer(tapGesture)

        let captionLabel = UILabel()
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.text = name
        captionLabel.font = fontManager.captionFont
        captionLabel.textColor = .secondaryLabel
        captionLabel.textAlignment = .center
        captionLabel.numberOfLines = 2
        wrapper.addSubview(captionLabel)

        // Loading indicator
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        mapImageView.addSubview(spinner)

        let mapHeight: CGFloat = 200

        NSLayoutConstraint.activate([
            mapImageView.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 8),
            mapImageView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            mapImageView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            mapImageView.heightAnchor.constraint(equalToConstant: mapHeight),

            captionLabel.topAnchor.constraint(equalTo: mapImageView.bottomAnchor, constant: 12),
            captionLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            captionLabel.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            captionLabel.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -8),

            spinner.centerXAnchor.constraint(equalTo: mapImageView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: mapImageView.centerYAnchor)
        ])

        // Use MKMapSnapshotter to generate map image
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: 350, height: mapHeight)
        options.mapType = .standard

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { [weak self] snapshot, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                // Remove spinner
                for subview in mapImageView.subviews {
                    if let spinner = subview as? UIActivityIndicatorView {
                        spinner.stopAnimating()
                        spinner.removeFromSuperview()
                    }
                }

                guard let snapshot = snapshot, error == nil else {
                    mapImageView.backgroundColor = .systemRed.withAlphaComponent(0.2)
                    return
                }

                // Draw the snapshot with a pin annotation
                UIGraphicsBeginImageContextWithOptions(snapshot.image.size, true, snapshot.image.scale)
                snapshot.image.draw(at: .zero)

                // Draw a pin at the coordinate
                let pinPoint = snapshot.point(for: coordinate)
                if let pinImage = UIImage(systemName: "mappin.circle.fill")?.withTintColor(.systemRed, renderingMode: .alwaysOriginal) {
                    let pinSize = CGSize(width: 30, height: 30)
                    pinImage.draw(in: CGRect(origin: CGPoint(x: pinPoint.x - pinSize.width / 2, y: pinPoint.y - pinSize.height), size: pinSize))
                }

                let finalImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()

                mapImageView.image = finalImage

                // Trigger table view layout update
                if let tableView = self.superview as? UITableView {
                    UIView.performWithoutAnimation {
                        tableView.beginUpdates()
                        tableView.endUpdates()
                    }
                    if let indexPath = tableView.indexPath(for: self) {
                        tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
                    }
                }
            }
        }

        return wrapper
    }

    func setTraceText(_ text: String?) {
        if let text = text {
            traceLabel.text = text
            traceLabel.isHidden = false
        } else {
            traceLabel.text = nil
            traceLabel.isHidden = true
        }
    }

    @objc private func mapTapped(_ gesture: MapTapGestureRecognizer) {
        let coordinate = gesture.coordinate
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = gesture.locationName
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        ])
    }
}

// MARK: - String Extension for JSON Formatting

private extension String {
    func prettyJSON() -> String {
        guard let data = self.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return self
        }
        return prettyString
    }
}

// MARK: - Map Tap Gesture Recognizer

private class MapTapGestureRecognizer: UITapGestureRecognizer {
    var coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D()
    var locationName: String = ""
}
