import OSLog
import ReaderCore
import UIKit

/// Container view controller that owns the unified navigation bar
/// and manages transitions between reader and chat content
public final class ReaderContainerViewController: UIViewController {
    private static let logger = Log.logger(category: "reader-container")

    // Book context
    private let epubURL: URL
    private let bookId: String
    private let bookTitle: String?
    private let bookAuthor: String?

    // Navigation bar (persistent, doesn't move during transitions)
    private let navigationBar = ReaderNavigationBar()

    // Content area
    private let contentContainer = UIView()

    // Child view controllers
    private var readerViewController: ReaderViewController!
    private var chatContainerViewController: ChatContainerViewController?

    // Current mode
    private enum ContentMode {
        case reader
        case chat
    }

    private var currentMode: ContentMode = .reader

    // State tracking
    private var overlayVisible = false
    private var scrubberVisibleBeforeChat = false

    // MARK: - Initialization

    public init(epubURL: URL, bookId: String, bookTitle: String?, bookAuthor: String?) {
        self.epubURL = epubURL
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
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

        setupContentContainer()
        setupNavigationBar()
        setupReader()

        // Start with overlay hidden (matching reader behavior)
        let showOverlay = CommandLine.arguments.contains("--uitesting-show-overlay")
        setOverlayVisible(showOverlay, animated: false)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // MARK: - Setup

    private func setupContentContainer() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)

        // Content fills entire view (will be under the navigation bar)
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupNavigationBar() {
        navigationBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigationBar)

        NSLayoutConstraint.activate([
            navigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            navigationBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            navigationBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            navigationBar.heightAnchor.constraint(equalToConstant: ReaderNavigationBar.height),
        ])
    }

    private func setupReader() {
        readerViewController = ReaderViewController(
            epubURL: epubURL,
            bookId: bookId,
            bookTitle: bookTitle,
            bookAuthor: bookAuthor
        )

        addChild(readerViewController)
        contentContainer.addSubview(readerViewController.view)
        readerViewController.view.frame = contentContainer.bounds
        readerViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        readerViewController.didMove(toParent: self)

        // Set up delegate for bar configuration
        readerViewController.containerDelegate = self

        // Configure nav bar for reader mode
        updateNavigationBar(animated: false)
    }

    // MARK: - Overlay Visibility

    private func setOverlayVisible(_ visible: Bool, animated: Bool) {
        overlayVisible = visible
        let alpha: CGFloat = visible ? 1.0 : 0.0

        if animated {
            UIView.animate(withDuration: 0.25) {
                self.navigationBar.alpha = alpha
            }
        } else {
            navigationBar.alpha = alpha
        }

        // Forward to reader for scrubber visibility
        readerViewController.setOverlayVisible(visible, animated: animated)
    }

    func toggleOverlay() {
        setOverlayVisible(!overlayVisible, animated: true)
    }

    // MARK: - Navigation Bar Configuration

    private func updateNavigationBar(animated: Bool) {
        let config: NavigationBarConfiguration = switch currentMode {
        case .reader:
            readerNavigationBarConfiguration()
        case .chat:
            chatNavigationBarConfiguration()
        }

        navigationBar.configure(with: config, animated: animated)
    }

    private func readerNavigationBarConfiguration() -> NavigationBarConfiguration {
        var leadingItems: [NavigationBarItem] = [
            .button(systemImage: "chevron.left", accessibilityLabel: "Back") { [weak self] in
                self?.navigateBack()
            },
        ]

        // Add TOC menu if there are enough items
        if let tocMenu = readerViewController.buildTOCMenu(), readerViewController.hasMeaningfulTOC {
            leadingItems.append(.menu(
                systemImage: "list.bullet",
                accessibilityLabel: "Table of Contents",
                accessibilityIdentifier: "toc-button",
                menu: tocMenu
            ))
        }

        let trailingItems: [NavigationBarItem] = [
            .button(systemImage: "text.bubble", accessibilityLabel: "Chat") { [weak self] in
                self?.showChat(selection: nil)
            },
            .button(systemImage: "gearshape", accessibilityLabel: "Settings") { [weak self] in
                self?.readerViewController.showSettings()
            },
        ]

        return NavigationBarConfiguration(
            leadingItems: leadingItems,
            title: bookTitle ?? "Reader",
            trailingItems: trailingItems
        )
    }

    private func chatNavigationBarConfiguration() -> NavigationBarConfiguration {
        let leadingItems: [NavigationBarItem] = [
            .button(systemImage: "sidebar.left", accessibilityLabel: "Conversations") { [weak self] in
                self?.chatContainerViewController?.toggleDrawer()
            },
            .button(systemImage: "book", accessibilityLabel: "Reader") { [weak self] in
                self?.showReader()
            },
        ]

        let trailingItems: [NavigationBarItem] = [
            .textButton(title: "Done") { [weak self] in
                self?.showReader()
            },
        ]

        return NavigationBarConfiguration(
            leadingItems: leadingItems,
            title: bookTitle ?? "Chat",
            trailingItems: trailingItems
        )
    }

    // MARK: - Mode Transitions

    func showChat(selection: SelectionPayload?) {
        guard currentMode == .reader else { return }

        Self.logger.info("Transitioning to chat mode")

        // Remember scrubber state
        scrubberVisibleBeforeChat = overlayVisible

        // Create book context
        let spineIndex = readerViewController.currentSpineIndex
        let chapter = readerViewController.chapter
        let currentSpineItemId = spineIndex < chapter.htmlSections.count
            ? chapter.htmlSections[spineIndex].spineItemId
            : (chapter.htmlSections.first?.spineItemId ?? "")

        let bookContext = ReaderBookContext(
            chapter: chapter,
            bookId: bookId,
            bookTitle: bookTitle ?? "Unknown Book",
            bookAuthor: bookAuthor,
            currentSpineItemId: currentSpineItemId,
            currentBlockId: nil
        )

        // Create chat container
        let chatVC = ChatContainerViewController(context: bookContext, selection: selection)
        chatVC.containerDelegate = self
        // Set top inset to account for navigation bar (16pt top margin + 56pt bar height + 8pt gap)
        chatVC.topContentInset = 16 + ReaderNavigationBar.height + 8
        // Set bottom inset to account for input area (~120pt input container + 14pt margin)
        chatVC.bottomContentInset = 134
        chatContainerViewController = chatVC

        // Add as child
        addChild(chatVC)
        chatVC.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(chatVC.view)

        NSLayoutConstraint.activate([
            chatVC.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            chatVC.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            chatVC.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            chatVC.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])

        // Position chat off-screen to the right
        chatVC.view.transform = CGAffineTransform(translationX: view.bounds.width, y: 0)

        chatVC.didMove(toParent: self)

        // Ensure navigation bar stays visible and on top during chat
        navigationBar.alpha = 1.0
        view.bringSubviewToFront(navigationBar)

        currentMode = .chat

        // Animate transition
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            // Slide reader out to left, fade slightly
            self.readerViewController.view.transform = CGAffineTransform(translationX: -self.view.bounds.width * 0.3, y: 0)
            self.readerViewController.view.alpha = 0.5

            // Slide chat in from right
            chatVC.view.transform = .identity
        } completion: { _ in
            // Hide reader (it's off-screen anyway)
            self.readerViewController.view.isHidden = true
        }

        // Update navigation bar with animation
        updateNavigationBar(animated: true)
    }

    func showReader() {
        guard currentMode == .chat else { return }

        Self.logger.info("Transitioning to reader mode")

        // Make reader visible again
        readerViewController.view.isHidden = false

        currentMode = .reader

        // Animate transition
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            // Slide reader back to center
            self.readerViewController.view.transform = .identity
            self.readerViewController.view.alpha = 1.0

            // Slide chat out to right
            self.chatContainerViewController?.view.transform = CGAffineTransform(translationX: self.view.bounds.width, y: 0)
        } completion: { _ in
            // Remove chat from hierarchy
            self.chatContainerViewController?.willMove(toParent: nil)
            self.chatContainerViewController?.view.removeFromSuperview()
            self.chatContainerViewController?.removeFromParent()
            self.chatContainerViewController = nil

            // Restore overlay state
            self.setOverlayVisible(self.scrubberVisibleBeforeChat, animated: true)
        }

        // Update navigation bar with animation
        updateNavigationBar(animated: true)
    }

    private func navigateBack() {
        if currentMode == .chat {
            showReader()
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
}

// MARK: - ReaderViewControllerContainerDelegate

extension ReaderContainerViewController: ReaderViewControllerContainerDelegate {
    func readerViewControllerDidRequestOverlayToggle(_: ReaderViewController) {
        toggleOverlay()
    }

    func readerViewControllerDidRequestChat(_: ReaderViewController, selection: SelectionPayload?) {
        showChat(selection: selection)
    }
}

// MARK: - ChatContainerViewControllerDelegate

extension ReaderContainerViewController: ChatContainerViewControllerDelegate {
    func chatContainerDidRequestDismiss(_: ChatContainerViewController) {
        showReader()
    }
}
