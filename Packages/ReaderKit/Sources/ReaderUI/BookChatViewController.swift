import UIKit
import ReaderCore
import OSLog

/// Chat interface for conversing with the LLM about a book
public final class BookChatViewController: UIViewController {
    private static let logger = Logger(subsystem: "com.splap.reader", category: "chat")
    private let context: BookContext
    private let agentService = ReaderAgentService()
    private let initialSelection: String?
    private let conversationId: UUID?

    private var conversation: Conversation
    private var conversationHistory: [AgentMessage] = []
    private var isLoading = false

    var onToggleDrawer: (() -> Void)?

    // MARK: - UI Components

    private let tableView = UITableView()
    private let inputContainer = UIView()
    private let textField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    private var messages: [ChatMessage] = []
    private var messageTraces: [UUID: AgentExecutionTrace] = [:]

    private var inputContainerBottomConstraint: NSLayoutConstraint?

    // MARK: - Initialization

    public init(context: BookContext, selection: String? = nil, conversationId: UUID? = nil) {
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
        setupUI()
        setupKeyboardObservers()
        addWelcomeMessage()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
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

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(dismissChat)
        )

        // Table view for messages
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.keyboardDismissMode = .interactive
        tableView.register(ChatMessageCell.self, forCellReuseIdentifier: "MessageCell")
        view.addSubview(tableView)

        // Input container
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.backgroundColor = .secondarySystemBackground
        view.addSubview(inputContainer)

        // Text field
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Ask about the book..."
        textField.borderStyle = .roundedRect
        textField.delegate = self
        textField.returnKeyType = .send
        inputContainer.addSubview(textField)

        // Send button
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        sendButton.tintColor = .systemBlue
        sendButton.addTarget(self, action: #selector(sendMessage), for: .touchUpInside)
        inputContainer.addSubview(sendButton)

        // Loading indicator
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        inputContainer.addSubview(loadingIndicator)

        // Layout
        let bottomConstraint = inputContainer.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor
        )
        inputContainerBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputContainer.topAnchor),

            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomConstraint,

            textField.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 12),
            textField.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 8),
            textField.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -8),

            sendButton.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: textField.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 44),

            loadingIndicator.centerXAnchor.constraint(equalTo: sendButton.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor)
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

    private func addWelcomeMessage() {
        // Build book context with position
        var bookInfo = "Book: \(context.bookTitle)"
        if let author = context.bookAuthor {
            bookInfo += "\nAuthor: \(author)"
        }

        // Add position info
        let sections = context.sections
        if let currentIndex = sections.firstIndex(where: { $0.spineItemId == context.currentSpineItemId }) {
            let section = sections[currentIndex]

            // Use NCX label if available, otherwise fall back to extracted title
            let chapterLabel = section.displayLabel
            bookInfo += "\nChapter: \(chapterLabel)"

            // Add percentage through chapter if available
            if let blockId = context.currentBlockId,
               let block = context.blocksAround(blockId: blockId, count: 0).first,
               section.blockCount > 0 {
                let percentage = Int(round(Double(block.ordinal + 1) / Double(section.blockCount) * 100))
                bookInfo += "\nPosition: \(percentage)% through chapter"
            }
        }

        messages.append(ChatMessage(
            role: .system,
            content: bookInfo,
            title: "📚 Book Context",
            isCollapsed: true
        ))

        // Load existing conversation messages if this is an existing conversation
        if conversationId != nil && !conversation.messages.isEmpty {
            for storedMsg in conversation.messages {
                let role: ChatMessage.Role = storedMsg.role == .user ? .user : .assistant
                messages.append(ChatMessage(role: role, content: storedMsg.content))

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
            // If there's a selection, add it as a user message (not sent yet)
            messages.append(ChatMessage(role: .user, content: selection))
            // Focus text field and show keyboard
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.textField.becomeFirstResponder()
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

    private func saveAndSummarizeConversation() {
        // Convert UI messages to stored messages (exclude system messages)
        let storedMessages = messages.compactMap { msg -> StoredMessage? in
            switch msg.role {
            case .user:
                return StoredMessage(role: .user, content: msg.content)
            case .assistant:
                return StoredMessage(role: .assistant, content: msg.content)
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
        guard let text = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              !isLoading else {
            return
        }

        // Add user message
        messages.append(ChatMessage(role: .user, content: text))
        tableView.reloadData()
        scrollToBottom()

        textField.text = ""
        setLoading(true)

        // Send to agent
        Task {
            do {
                let result = try await agentService.chat(
                    message: text,
                    context: context,
                    history: conversationHistory
                )

                await MainActor.run {
                    // Update history
                    self.conversationHistory = result.updatedHistory

                    // Add tool usage note if tools were called
                    var displayContent = result.response.content
                    if !result.response.toolCallsMade.isEmpty {
                        let toolsUsed = result.response.toolCallsMade.joined(separator: ", ")
                        displayContent = "[Used: \(toolsUsed)]\n\n\(result.response.content)"
                    }

                    // Create message with trace if available
                    let hasTrace = result.response.executionTrace != nil
                    let message = ChatMessage(role: .assistant, content: displayContent, hasTrace: hasTrace)

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
        textField.isEnabled = !loading

        if loading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
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

    // MARK: - Trace Formatting

    private func formatTraceForDisplay(_ trace: AgentExecutionTrace, collapsed: Bool) -> String {
        if collapsed {
            let toolCount = trace.toolExecutions.count
            let toolNames = trace.toolExecutions.map { $0.functionName }.joined(separator: ", ")
            return "📊 Execution Details ▶  (Used \(toolCount) tools: \(toolNames))"
        }

        var text = "📊 Execution Details ▼\n\n"

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

        // Tools section
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

            // Set up tap handler to toggle trace
            cell.onTap = { [weak self] in
                self?.messages[indexPath.row].isCollapsed.toggle()
                self?.tableView.reloadRows(at: [indexPath], with: .automatic)
            }
        } else if message.role == .system {
            // Set up tap handler for system messages to toggle collapsed state
            cell.onTap = { [weak self] in
                self?.messages[indexPath.row].isCollapsed.toggle()
                self?.tableView.reloadRows(at: [indexPath], with: .automatic)
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

// MARK: - UITextFieldDelegate

extension BookChatViewController: UITextFieldDelegate {
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendMessage()
        return false
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
    private let messageLabel = UILabel()
    private let traceLabel = UILabel()
    var onTap: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.layer.cornerRadius = 12
        bubbleView.clipsToBounds = true
        contentView.addSubview(bubbleView)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.numberOfLines = 0
        messageLabel.font = .systemFont(ofSize: 16)
        bubbleView.addSubview(messageLabel)

        traceLabel.translatesAutoresizingMaskIntoConstraints = false
        traceLabel.numberOfLines = 0
        traceLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        traceLabel.textColor = .secondaryLabel
        traceLabel.isHidden = true
        bubbleView.addSubview(traceLabel)

        // Create fallback constraint for when trace is hidden
        let messageLabelBottomConstraint = messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10)
        messageLabelBottomConstraint.priority = .defaultLow

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            messageLabelBottomConstraint,

            traceLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 8),
            traceLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            traceLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            traceLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10)
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

        switch message.role {
        case .user:
            bubbleView.backgroundColor = .systemBlue
            messageLabel.textColor = .white
            messageLabel.font = .systemFont(ofSize: 16)
            messageLabel.text = message.content
            leadingConstraint = bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 60)
            trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)

        case .assistant:
            bubbleView.backgroundColor = .secondarySystemBackground
            messageLabel.textColor = .label
            messageLabel.font = .systemFont(ofSize: 16)
            messageLabel.text = message.content
            leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
            trailingConstraint = bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -60)

        case .system:
            bubbleView.backgroundColor = .tertiarySystemBackground
            messageLabel.textColor = .secondaryLabel
            messageLabel.font = .systemFont(ofSize: 14)

            // Show title with disclosure indicator when collapsed, full content when expanded
            if message.isCollapsed {
                messageLabel.text = "\(message.title ?? "Context") ▶"
            } else {
                messageLabel.text = "\(message.title ?? "Context") ▼\n\n\(message.content)"
            }

            // System messages span full width
            leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
            trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        }

        leadingConstraint?.isActive = true
        trailingConstraint?.isActive = true
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
