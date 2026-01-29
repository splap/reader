import ReaderCore
import UIKit

/// Drawer view showing conversation history
final class ConversationDrawerViewController: UIViewController {
    private let context: BookContext
    private var conversations: [Conversation] = []
    private var hasCurrentChat = true // Always true when drawer is shown from a chat
    private let fontManager = FontScaleManager.shared

    var onSelectConversation: ((UUID) -> Void)?
    var onNewChat: (() -> Void)?
    var onSelectCurrentChat: (() -> Void)?

    private let headerView = UIView()
    private let headerLabel = UILabel()
    private let newChatButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)

    // MARK: - Initialization

    init(context: BookContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 16
        // All corners rounded
        view.clipsToBounds = true

        setupUI()
        loadConversations()
        setupFontScaleObserver()
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
        // Update header font
        headerLabel.font = .preferredFont(forTextStyle: .headline)

        // Reload table to update cell fonts
        tableView.reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadConversations()
    }

    // MARK: - Setup

    private func setupUI() {
        // Header with title and compose button (iOS standard pattern)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.text = "Chats"
        headerLabel.font = .preferredFont(forTextStyle: .headline)
        headerView.addSubview(headerLabel)

        newChatButton.translatesAutoresizingMaskIntoConstraints = false
        newChatButton.setImage(UIImage(systemName: "square.and.pencil"), for: .normal)
        newChatButton.addTarget(self, action: #selector(newChatTapped), for: .touchUpInside)
        headerView.addSubview(newChatButton)

        // Separator under header
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        headerView.addSubview(separator)

        // Table view for conversations
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.register(ConversationCell.self, forCellReuseIdentifier: "ConversationCell")
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 44),

            headerLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            headerLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            newChatButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            newChatButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            newChatButton.widthAnchor.constraint(equalToConstant: 44),
            newChatButton.heightAnchor.constraint(equalToConstant: 44),

            separator.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func loadConversations() {
        conversations = ConversationStorage.shared.getAllConversations()
            .filter { $0.bookTitle == context.bookTitle }
        tableView.reloadData()
    }

    // MARK: - Actions

    @objc private func newChatTapped() {
        onNewChat?()
    }
}

// MARK: - UITableViewDataSource

extension ConversationDrawerViewController: UITableViewDataSource {
    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        // +1 for "Current Chat" row if active
        conversations.count + (hasCurrentChat ? 1 : 0)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ConversationCell", for: indexPath) as! ConversationCell

        if hasCurrentChat, indexPath.row == 0 {
            cell.configureAsCurrentChat()
        } else {
            let conversationIndex = hasCurrentChat ? indexPath.row - 1 : indexPath.row
            cell.configure(with: conversations[conversationIndex])
        }
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ConversationDrawerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if hasCurrentChat, indexPath.row == 0 {
            onSelectCurrentChat?()
        } else {
            let conversationIndex = hasCurrentChat ? indexPath.row - 1 : indexPath.row
            let conversation = conversations[conversationIndex]
            onSelectConversation?(conversation.id)
        }
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        // Don't allow deleting current chat
        if hasCurrentChat, indexPath.row == 0 {
            return
        }

        if editingStyle == .delete {
            let conversationIndex = hasCurrentChat ? indexPath.row - 1 : indexPath.row
            let conversation = conversations[conversationIndex]
            ConversationStorage.shared.deleteConversation(id: conversation.id)
            conversations.remove(at: conversationIndex)
            tableView.deleteRows(at: [indexPath], with: .fade)
        }
    }

    func tableView(_: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Don't allow editing/deleting current chat row
        if hasCurrentChat, indexPath.row == 0 {
            return false
        }
        return true
    }
}

// MARK: - Conversation Cell

private final class ConversationCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()
    private let fontManager = FontScaleManager.shared

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .clear
        accessoryType = .disclosureIndicator

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        contentView.addSubview(titleLabel)

        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = .preferredFont(forTextStyle: .caption1)
        dateLabel.textColor = .secondaryLabel
        contentView.addSubview(dateLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            dateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            dateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            dateLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    func configure(with conversation: Conversation) {
        titleLabel.font = .preferredFont(forTextStyle: .body)
        dateLabel.font = .preferredFont(forTextStyle: .caption1)

        titleLabel.text = conversation.title
        titleLabel.textColor = .label
        accessoryType = .disclosureIndicator

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        dateLabel.text = formatter.localizedString(for: conversation.updatedAt, relativeTo: Date())
    }

    func configureAsCurrentChat() {
        titleLabel.font = .preferredFont(forTextStyle: .body)
        dateLabel.font = .preferredFont(forTextStyle: .caption1)

        titleLabel.text = "Current Chat"
        titleLabel.textColor = .systemBlue
        dateLabel.text = "Active"
        accessoryType = .disclosureIndicator // Same as other rows
    }
}
