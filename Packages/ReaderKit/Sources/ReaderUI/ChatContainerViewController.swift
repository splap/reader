import OSLog
import ReaderCore
import UIKit

/// Container view controller that manages the conversation drawer and chat view
public final class ChatContainerViewController: UIViewController {
    private static let logger = Log.logger(category: "chat-container")
    private let context: BookContext
    private let initialSelection: SelectionPayload?

    // Top bar (fixed, never moves)
    private let topBar = UIView()
    private let sidebarButton = UIButton(type: .system)
    private let debugButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    // Content area (below top bar)
    private let contentContainer = UIView()
    private var drawerViewController: ConversationDrawerViewController!
    private var chatViewController: BookChatViewController!
    private var drawerWidthConstraint: NSLayoutConstraint!

    private var isDrawerVisible = false

    /// Responsive drawer width - percentage of view width, capped
    private var drawerWidth: CGFloat {
        min(view.bounds.width * 0.4, 350)
    }

    // MARK: - Initialization

    public init(context: BookContext, selection: SelectionPayload? = nil) {
        self.context = context
        initialSelection = selection
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        setupTopBar()
        setupContentContainer()
        setupDrawer()
        setupChat()
        setupGestures()
    }

    // MARK: - Setup

    private func setupTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.backgroundColor = .systemBackground
        view.addSubview(topBar)

        // Sidebar toggle button (left)
        sidebarButton.translatesAutoresizingMaskIntoConstraints = false
        sidebarButton.setImage(UIImage(systemName: "sidebar.left"), for: .normal)
        sidebarButton.addTarget(self, action: #selector(toggleDrawer), for: .touchUpInside)
        topBar.addSubview(sidebarButton)

        // Close button (right)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.addTarget(self, action: #selector(dismissChat), for: .touchUpInside)
        topBar.addSubview(closeButton)

        // Debug button (right, before close)
        debugButton.translatesAutoresizingMaskIntoConstraints = false
        debugButton.setImage(UIImage(systemName: "doc.text"), for: .normal)
        debugButton.addTarget(self, action: #selector(copyDebugTranscript), for: .touchUpInside)
        topBar.addSubview(debugButton)

        let topBarHeight: CGFloat = 44

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: topBarHeight),

            sidebarButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            sidebarButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            sidebarButton.widthAnchor.constraint(equalToConstant: 44),
            sidebarButton.heightAnchor.constraint(equalToConstant: 44),

            closeButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
            closeButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            debugButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            debugButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            debugButton.widthAnchor.constraint(equalToConstant: 44),
            debugButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setupContentContainer() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupDrawer() {
        drawerViewController = ConversationDrawerViewController(context: context)
        drawerViewController.onSelectConversation = { [weak self] conversationId in
            self?.loadConversation(id: conversationId)
        }
        drawerViewController.onNewChat = { [weak self] in
            self?.startNewChat()
        }
        drawerViewController.onSelectCurrentChat = { [weak self] in
            self?.hideDrawer()
        }

        addChild(drawerViewController)
        contentContainer.addSubview(drawerViewController.view)
        drawerViewController.didMove(toParent: self)

        drawerViewController.view.translatesAutoresizingMaskIntoConstraints = false

        drawerWidthConstraint = drawerViewController.view.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            drawerViewController.view.leadingAnchor.constraint(equalTo: contentContainer.layoutMarginsGuide.leadingAnchor),
            drawerViewController.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            drawerViewController.view.bottomAnchor.constraint(equalTo: contentContainer.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            drawerWidthConstraint,
        ])
    }

    private func setupChat() {
        chatViewController = BookChatViewController(context: context, selection: initialSelection)

        addChild(chatViewController)
        contentContainer.addSubview(chatViewController.view)
        chatViewController.didMove(toParent: self)

        chatViewController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            chatViewController.view.leadingAnchor.constraint(equalTo: drawerViewController.view.trailingAnchor),
            chatViewController.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            chatViewController.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            chatViewController.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    private func setupGestures() {
        // Swipe gesture to open drawer
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe))
        swipeRight.direction = .right
        contentContainer.addGestureRecognizer(swipeRight)

        // Swipe gesture to close drawer
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe))
        swipeLeft.direction = .left
        contentContainer.addGestureRecognizer(swipeLeft)
    }

    // MARK: - Actions

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        if gesture.direction == .right, !isDrawerVisible {
            showDrawer()
        } else if gesture.direction == .left, isDrawerVisible {
            hideDrawer()
        }
    }

    @objc private func toggleDrawer() {
        if isDrawerVisible {
            hideDrawer()
        } else {
            showDrawer()
        }
    }

    private func showDrawer() {
        isDrawerVisible = true
        drawerWidthConstraint.constant = drawerWidth

        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
            self.view.layoutIfNeeded()
        }
    }

    private func hideDrawer() {
        isDrawerVisible = false
        drawerWidthConstraint.constant = 0

        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseIn) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func dismissChat() {
        chatViewController.saveConversation()
        dismiss(animated: true)
    }

    @objc private func copyDebugTranscript() {
        let transcript = chatViewController.buildDebugTranscript()
        UIPasteboard.general.string = transcript

        let alert = UIAlertController(
            title: "Copied",
            message: "Debug transcript copied to clipboard (\(transcript.count) chars)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func loadConversation(id: UUID) {
        // Create new chat with conversation
        let newChatViewController = BookChatViewController(context: context, selection: nil, conversationId: id)
        newChatViewController.view.translatesAutoresizingMaskIntoConstraints = false

        // Add new view first (underneath)
        addChild(newChatViewController)
        contentContainer.insertSubview(newChatViewController.view, belowSubview: chatViewController.view)
        newChatViewController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            newChatViewController.view.leadingAnchor.constraint(equalTo: drawerViewController.view.trailingAnchor),
            newChatViewController.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            newChatViewController.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            newChatViewController.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])

        // Force layout so new view is ready
        contentContainer.layoutIfNeeded()

        // Remove old chat view controller
        chatViewController.willMove(toParent: nil)
        chatViewController.view.removeFromSuperview()
        chatViewController.removeFromParent()

        // Update reference
        chatViewController = newChatViewController
    }

    private func startNewChat() {
        // Collapse the drawer
        hideDrawer()

        // Create new chat
        let newChatViewController = BookChatViewController(context: context, selection: nil)
        newChatViewController.view.translatesAutoresizingMaskIntoConstraints = false

        // Add new view first (underneath)
        addChild(newChatViewController)
        contentContainer.insertSubview(newChatViewController.view, belowSubview: chatViewController.view)
        newChatViewController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            newChatViewController.view.leadingAnchor.constraint(equalTo: drawerViewController.view.trailingAnchor),
            newChatViewController.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            newChatViewController.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            newChatViewController.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])

        // Force layout so new view is ready
        contentContainer.layoutIfNeeded()

        // Remove old chat view controller
        chatViewController.willMove(toParent: nil)
        chatViewController.view.removeFromSuperview()
        chatViewController.removeFromParent()

        // Update reference
        chatViewController = newChatViewController
    }
}
