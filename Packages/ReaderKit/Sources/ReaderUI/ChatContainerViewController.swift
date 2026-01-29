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
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    // Content area (below top bar)
    private let contentContainer = UIView()
    private var drawerViewController: ConversationDrawerViewController!
    private var chatViewController: BookChatViewController!
    private var drawerWidthConstraint: NSLayoutConstraint!

    private var isDrawerVisible = false

    // Origin tracking: the chat state when drawer was opened (for "back" navigation)
    private var originChatViewController: BookChatViewController?
    private var originConversationId: UUID?

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
        // Container for the floating bar (holds blur + shadow)
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.backgroundColor = .clear
        view.addSubview(topBar)

        // Blur background - match reader's style
        let blurEffect = UIBlurEffect(style: .systemThinMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 16
        blurView.clipsToBounds = true
        topBar.addSubview(blurView)

        // Shadow for container - match reader's style
        topBar.layer.shadowColor = UIColor.black.cgColor
        topBar.layer.shadowOpacity = 0.2
        topBar.layer.shadowOffset = CGSize(width: 0, height: 2)
        topBar.layer.shadowRadius = 4

        // Sidebar toggle button (left) - match reader's FloatingButton style
        sidebarButton.translatesAutoresizingMaskIntoConstraints = false
        var sidebarConfig = UIButton.Configuration.plain()
        sidebarConfig.image = UIImage(systemName: "sidebar.left")
        sidebarConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        let iconColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .white : .black
        }
        sidebarConfig.baseForegroundColor = iconColor
        sidebarButton.configuration = sidebarConfig
        sidebarButton.addTarget(self, action: #selector(toggleDrawer), for: .touchUpInside)
        sidebarButton.accessibilityIdentifier = "chat-sidebar-button"
        topBar.addSubview(sidebarButton)

        // Centered title (book name)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = context.bookTitle
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        topBar.addSubview(titleLabel)

        // Done button (right) - standard iOS modal pattern
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        var closeConfig = UIButton.Configuration.plain()
        closeConfig.title = "Done"
        closeConfig.baseForegroundColor = .systemBlue
        closeConfig.contentInsets = .zero
        // Use attributed title for proper font control
        closeConfig.attributedTitle = AttributedString("Done", attributes: AttributeContainer([
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
        ]))
        closeButton.configuration = closeConfig
        closeButton.addTarget(self, action: #selector(dismissChat), for: .touchUpInside)
        topBar.addSubview(closeButton)

        let topBarHeight: CGFloat = 64

        NSLayoutConstraint.activate([
            // Floating bar with insets from edges
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            topBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            topBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            topBar.heightAnchor.constraint(equalToConstant: topBarHeight),

            // Blur fills container
            blurView.topAnchor.constraint(equalTo: topBar.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),

            // Sidebar button - vertically centered
            sidebarButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            sidebarButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 8),
            sidebarButton.widthAnchor.constraint(equalToConstant: 44),
            sidebarButton.heightAnchor.constraint(equalToConstant: 44),

            // Done button - vertically centered, close to right edge
            closeButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            // Title centered in the entire bar
            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: sidebarButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),
        ])
    }

    private func setupContentContainer() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            // Content starts below the floating bar (with a small gap)
            contentContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 8),
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
            self?.restoreOriginChat()
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
        // Save current state as origin (only if not already browsing)
        if originChatViewController == nil {
            originChatViewController = chatViewController
            originConversationId = chatViewController.currentConversationId
        }

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
        } completion: { _ in
            // Clear origin when drawer closes (user dismissed without navigating back)
            self.clearOrigin()
        }
    }

    private func restoreOriginChat() {
        // If we're already showing the origin, nothing to do
        guard let origin = originChatViewController, origin !== chatViewController else {
            return
        }

        // Restore the origin chat view controller (keep drawer open, like other selections)
        origin.view.translatesAutoresizingMaskIntoConstraints = false

        // Add origin view (underneath current)
        addChild(origin)
        contentContainer.insertSubview(origin.view, belowSubview: chatViewController.view)
        origin.didMove(toParent: self)

        NSLayoutConstraint.activate([
            origin.view.leadingAnchor.constraint(equalTo: drawerViewController.view.trailingAnchor),
            origin.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            origin.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            origin.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])

        contentContainer.layoutIfNeeded()

        // Remove current chat view controller
        chatViewController.willMove(toParent: nil)
        chatViewController.view.removeFromSuperview()
        chatViewController.removeFromParent()

        // Update reference
        chatViewController = origin

        // Don't clear origin - user can continue browsing and return again
        // Origin is cleared when drawer closes or "New Chat" is clicked
    }

    private func clearOrigin() {
        originChatViewController = nil
        originConversationId = nil
    }

    @objc private func dismissChat() {
        chatViewController.saveConversation()
        dismiss(animated: true)
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
        // Clear origin - user is explicitly starting fresh
        clearOrigin()

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
