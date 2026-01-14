import UIKit
import ReaderCore
import OSLog

/// Container view controller that manages the conversation drawer and chat view
public final class ChatContainerViewController: UIViewController {
    private static let logger = Logger(subsystem: "com.splap.reader", category: "chat-container")
    private let context: BookContext
    private let initialSelection: String?

    private var drawerViewController: ConversationDrawerViewController!
    private var chatViewController: BookChatViewController!
    private var chatNavController: UINavigationController!
    private var drawerWidthConstraint: NSLayoutConstraint!

    private let drawerWidth: CGFloat = 300
    private var isDrawerVisible = false

    // MARK: - Initialization

    public init(context: BookContext, selection: String? = nil) {
        self.context = context
        self.initialSelection = selection
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        setupDrawer()
        setupChat()
        setupGestures()
    }

    // MARK: - Setup

    private func setupDrawer() {
        drawerViewController = ConversationDrawerViewController(context: context)
        drawerViewController.onSelectConversation = { [weak self] conversationId in
            self?.loadConversation(id: conversationId)
        }
        drawerViewController.onNewChat = { [weak self] in
            self?.startNewChat()
        }

        addChild(drawerViewController)
        view.addSubview(drawerViewController.view)
        drawerViewController.didMove(toParent: self)

        drawerViewController.view.translatesAutoresizingMaskIntoConstraints = false

        drawerWidthConstraint = drawerViewController.view.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            drawerViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            drawerViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            drawerViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            drawerWidthConstraint
        ])
    }

    private func setupChat() {
        chatViewController = BookChatViewController(context: context, selection: initialSelection)
        chatViewController.onToggleDrawer = { [weak self] in
            self?.toggleDrawer()
        }

        // Wrap chat in its own nav controller
        chatNavController = UINavigationController(rootViewController: chatViewController)

        addChild(chatNavController)
        view.addSubview(chatNavController.view)
        chatNavController.didMove(toParent: self)

        chatNavController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            chatNavController.view.leadingAnchor.constraint(equalTo: drawerViewController.view.trailingAnchor),
            chatNavController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatNavController.view.topAnchor.constraint(equalTo: view.topAnchor),
            chatNavController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupGestures() {
        // Swipe gesture to open drawer
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe))
        swipeRight.direction = .right
        view.addGestureRecognizer(swipeRight)

        // Swipe gesture to close drawer
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe))
        swipeLeft.direction = .left
        view.addGestureRecognizer(swipeLeft)
    }

    // MARK: - Actions

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        if gesture.direction == .right && !isDrawerVisible {
            showDrawer()
        } else if gesture.direction == .left && isDrawerVisible {
            hideDrawer()
        }
    }

    private func toggleDrawer() {
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

    private func loadConversation(id: UUID) {
        // Remove current chat nav controller
        chatNavController.willMove(toParent: nil)
        chatNavController.view.removeFromSuperview()
        chatNavController.removeFromParent()

        // Create new chat with conversation
        chatViewController = BookChatViewController(context: context, selection: nil, conversationId: id)
        chatViewController.onToggleDrawer = { [weak self] in
            self?.toggleDrawer()
        }

        // Wrap in nav controller
        chatNavController = UINavigationController(rootViewController: chatViewController)

        addChild(chatNavController)
        view.addSubview(chatNavController.view)
        chatNavController.didMove(toParent: self)

        chatNavController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            chatNavController.view.leadingAnchor.constraint(equalTo: drawerViewController.view.trailingAnchor),
            chatNavController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatNavController.view.topAnchor.constraint(equalTo: view.topAnchor),
            chatNavController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hideDrawer()
    }

    private func startNewChat() {
        // Remove current chat nav controller
        chatNavController.willMove(toParent: nil)
        chatNavController.view.removeFromSuperview()
        chatNavController.removeFromParent()

        // Create new chat
        chatViewController = BookChatViewController(context: context, selection: nil)
        chatViewController.onToggleDrawer = { [weak self] in
            self?.toggleDrawer()
        }

        // Wrap in nav controller
        chatNavController = UINavigationController(rootViewController: chatViewController)

        addChild(chatNavController)
        view.addSubview(chatNavController.view)
        chatNavController.didMove(toParent: self)

        chatNavController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            chatNavController.view.leadingAnchor.constraint(equalTo: drawerViewController.view.trailingAnchor),
            chatNavController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatNavController.view.topAnchor.constraint(equalTo: view.topAnchor),
            chatNavController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hideDrawer()
    }
}
