import OSLog
import ReaderCore
import UIKit

/// Container view controller that manages the conversation drawer and chat view
public final class ChatContainerViewController: UIViewController {
    private static let logger = Log.logger(category: "chat-container")
    private let context: BookContext
    private let initialSelection: SelectionPayload?

    private var drawerViewController: ConversationDrawerViewController!
    private var chatViewController: BookChatViewController!
    private var chatNavController: UINavigationController!
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
        drawerViewController.onSelectCurrentChat = { [weak self] in
            self?.hideDrawer()
        }

        addChild(drawerViewController)
        view.addSubview(drawerViewController.view)
        drawerViewController.didMove(toParent: self)

        drawerViewController.view.translatesAutoresizingMaskIntoConstraints = false

        drawerWidthConstraint = drawerViewController.view.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            drawerViewController.view.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            drawerViewController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            drawerViewController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            drawerWidthConstraint,
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
            chatNavController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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
        if gesture.direction == .right, !isDrawerVisible {
            showDrawer()
        } else if gesture.direction == .left, isDrawerVisible {
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
        // Create new chat with conversation
        let newChatViewController = BookChatViewController(context: context, selection: nil, conversationId: id)
        newChatViewController.onToggleDrawer = { [weak self] in
            self?.toggleDrawer()
        }

        // Wrap in nav controller
        let newNavController = UINavigationController(rootViewController: newChatViewController)
        newNavController.view.translatesAutoresizingMaskIntoConstraints = false

        // Add new view first (underneath)
        addChild(newNavController)
        view.insertSubview(newNavController.view, belowSubview: chatNavController.view)
        newNavController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            newNavController.view.leadingAnchor.constraint(equalTo: drawerViewController.view.trailingAnchor),
            newNavController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            newNavController.view.topAnchor.constraint(equalTo: view.topAnchor),
            newNavController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Force layout so new view is ready
        view.layoutIfNeeded()

        // Remove old chat nav controller
        chatNavController.willMove(toParent: nil)
        chatNavController.view.removeFromSuperview()
        chatNavController.removeFromParent()

        // Update references
        chatNavController = newNavController
        chatViewController = newChatViewController
    }

    private func startNewChat() {
        // Collapse the drawer
        hideDrawer()

        // Create new chat
        let newChatViewController = BookChatViewController(context: context, selection: nil)
        newChatViewController.onToggleDrawer = { [weak self] in
            self?.toggleDrawer()
        }

        // Wrap in nav controller
        let newNavController = UINavigationController(rootViewController: newChatViewController)
        newNavController.view.translatesAutoresizingMaskIntoConstraints = false

        // Add new view first (underneath)
        addChild(newNavController)
        view.insertSubview(newNavController.view, belowSubview: chatNavController.view)
        newNavController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            newNavController.view.leadingAnchor.constraint(equalTo: drawerViewController.view.trailingAnchor),
            newNavController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            newNavController.view.topAnchor.constraint(equalTo: view.topAnchor),
            newNavController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Force layout so new view is ready
        view.layoutIfNeeded()

        // Remove old chat nav controller
        chatNavController.willMove(toParent: nil)
        chatNavController.view.removeFromSuperview()
        chatNavController.removeFromParent()

        // Update references
        chatNavController = newNavController
        chatViewController = newChatViewController
    }
}
