import UIKit
import ReaderCore

/// Drawer view showing conversation history
final class ConversationDrawerViewController: UIViewController {
    private let context: BookContext
    private var conversations: [Conversation] = []

    var onSelectConversation: ((UUID) -> Void)?
    var onNewChat: (() -> Void)?

    private let tableView = UITableView()
    private let newChatButton = UIButton(type: .system)

    // MARK: - Initialization

    init(context: BookContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .secondarySystemBackground

        setupUI()
        loadConversations()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadConversations()
    }

    // MARK: - Setup

    private func setupUI() {
        // New chat button at top
        newChatButton.translatesAutoresizingMaskIntoConstraints = false
        newChatButton.setTitle("+ New Chat", for: .normal)
        newChatButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        newChatButton.addTarget(self, action: #selector(newChatTapped), for: .touchUpInside)
        newChatButton.backgroundColor = .systemBlue
        newChatButton.setTitleColor(.white, for: .normal)
        newChatButton.layer.cornerRadius = 8
        view.addSubview(newChatButton)

        // Table view for conversations
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.register(ConversationCell.self, forCellReuseIdentifier: "ConversationCell")
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            newChatButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            newChatButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            newChatButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            newChatButton.heightAnchor.constraint(equalToConstant: 44),

            tableView.topAnchor.constraint(equalTo: newChatButton.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
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
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return conversations.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ConversationCell", for: indexPath) as! ConversationCell
        cell.configure(with: conversations[indexPath.row])
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ConversationDrawerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let conversation = conversations[indexPath.row]
        onSelectConversation?(conversation.id)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let conversation = conversations[indexPath.row]
            ConversationStorage.shared.deleteConversation(id: conversation.id)
            conversations.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
        }
    }
}

// MARK: - Conversation Cell

private final class ConversationCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .clear
        selectedBackgroundView = {
            let view = UIView()
            view.backgroundColor = .systemGray5
            return view
        }()

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        contentView.addSubview(titleLabel)

        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = .systemFont(ofSize: 13)
        dateLabel.textColor = .secondaryLabel
        contentView.addSubview(dateLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            dateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            dateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            dateLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    func configure(with conversation: Conversation) {
        titleLabel.text = conversation.title

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        dateLabel.text = formatter.localizedString(for: conversation.updatedAt, relativeTo: Date())
    }
}
