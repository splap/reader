import UIKit
import SwiftUI
import Combine
import ReaderCore
import OSLog

public final class ReaderViewController: UIViewController {
    private static let logger = Log.logger(category: "reader-vc")
    private let viewModel: ReaderViewModel
    private let chapter: Chapter
    private let bookId: String
    private let bookTitle: String?
    private let bookAuthor: String?
    private var pageRenderer: PageRenderer!
    private var cancellables = Set<AnyCancellable>()
    private var backButton: FloatingButton!
    private var tocButton: FloatingButton!
    private var settingsButton: FloatingButton!
    private var chatButton: FloatingButton!
    private var scrubberContainer: UIView!
    private var scrubberSlider: UISlider!
    private var scrubberReadExtentView: UIView!
    private var pageLabel: UILabel!
    private var overlayVisible = false
    private let uiTestTargetPage: Int? = ReaderViewController.parseUITestTargetPage()
    private var hasPerformedUITestJump = false
    private let initialSpineItemIndex: Int?
    private var hasNavigatedToInitialSpineItem = false

    // Top bar container
    private var topBarContainer: UIView!
    private var titleLabel: UILabel!

    // Loading overlay for renderer switch
    private var loadingOverlay: UIView?
    private var awaitingRendererReady = false

    public init(chapter: Chapter = SampleChapter.make(), bookId: String = UUID().uuidString, bookTitle: String? = nil, bookAuthor: String? = nil, initialSpineItemIndex: Int? = nil) {
        self.viewModel = ReaderViewModel(chapter: chapter)
        self.chapter = chapter
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.initialSpineItemIndex = initialSpineItemIndex
        super.init(nibName: nil, bundle: nil)
    }

    public init(epubURL: URL, bookId: String = UUID().uuidString, bookTitle: String? = nil, bookAuthor: String? = nil, maxSections: Int = .max, initialSpineItemIndex: Int? = nil) {
        let initStart = CFAbsoluteTimeGetCurrent()
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.initialSpineItemIndex = initialSpineItemIndex
        do {
            let chapter = try EPUBLoader().loadChapter(from: epubURL, maxSections: maxSections)
            self.chapter = chapter
            self.viewModel = ReaderViewModel(chapter: chapter)
        } catch {
            let fallback = SampleChapter.make()
            self.chapter = fallback
            self.viewModel = ReaderViewModel(chapter: fallback)
        }
        super.init(nibName: nil, bundle: nil)
        Self.logger.info("PERF: ReaderViewController init took \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - initStart))s")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        setupWebPageViewController()
        setupFloatingButtons()
        setupScrubber()
        setupTapGesture()
        setupKeyCommands()
        bindViewModel()

        let showOverlay = CommandLine.arguments.contains("--uitesting-show-overlay")
        // Start with overlay hidden unless UI tests request it visible.
        setOverlayVisible(showOverlay, animated: false)

        // Observe render mode changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(renderModeDidChange(_:)),
            name: ReaderPreferences.renderModeDidChangeNotification,
            object: nil
        )
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    private var hasInitialLayout = false

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        pageRenderer.viewController.view.frame = view.bounds

        // Ensure top bar and scrubber are above the page renderer
        view.bringSubviewToFront(topBarContainer)
        view.bringSubviewToFront(scrubberContainer)

        if !hasInitialLayout {
            hasInitialLayout = true
        }
    }

    private func setupWebPageViewController() {
        // Set current spine item ID if we have sections
        if let firstSection = chapter.htmlSections.first {
            viewModel.setCurrentSpineItem(firstSection.spineItemId)
        }

        // Create renderer based on current preference
        let renderer: PageRenderer
        let renderMode = ReaderPreferences.shared.renderMode

        switch renderMode {
        case .native:
            renderer = NativePageViewController(
                htmlSections: chapter.htmlSections,
                bookId: bookId,
                bookTitle: bookTitle,
                bookAuthor: bookAuthor,
                chapterTitle: chapter.title,
                fontScale: viewModel.fontScale,
                initialBlockId: viewModel.initialBlockId
            )

        case .webView:
            renderer = WebPageViewController(
                htmlSections: chapter.htmlSections,
                bookTitle: bookTitle,
                bookAuthor: bookAuthor,
                chapterTitle: chapter.title,
                fontScale: viewModel.fontScale,
                initialPageIndex: viewModel.initialPageIndex,
                initialBlockId: viewModel.initialBlockId,
                hrefToSpineItemId: chapter.hrefToSpineItemId
            )
        }

        // Configure callbacks
        renderer.onSendToLLM = { [weak self] selection in
            self?.openChatWithSelection(selection)
        }
        renderer.onPageChanged = { [weak self] newPage, totalPages in
            self?.viewModel.updateCurrentPage(newPage, totalPages: totalPages)
            self?.updateScrubber()
            self?.maybePerformUITestJump(totalPages: totalPages)
            self?.maybeNavigateToInitialSpineItem()
        }
        renderer.onBlockPositionChanged = { [weak self] blockId, spineItemId in
            self?.viewModel.updateBlockPosition(blockId: blockId, spineItemId: spineItemId)
        }
        renderer.onRenderReady = {
            NotificationCenter.default.post(name: ReaderPreferences.readerRenderReadyNotification, object: nil)
        }

        self.pageRenderer = renderer

        let rendererVC = renderer.viewController
        addChild(rendererVC)
        view.addSubview(rendererVC.view)
        rendererVC.view.frame = view.bounds
        rendererVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        rendererVC.didMove(toParent: self)
    }


    private func setupFloatingButtons() {
        // Create top bar container with blur background
        topBarContainer = UIView()
        topBarContainer.translatesAutoresizingMaskIntoConstraints = false
        topBarContainer.backgroundColor = .clear

        // Blur background - use thin material for more transparency
        let blurEffect = UIBlurEffect(style: .systemThinMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 16
        blurView.clipsToBounds = true
        topBarContainer.addSubview(blurView)

        // Shadow for container
        topBarContainer.layer.shadowColor = UIColor.black.cgColor
        topBarContainer.layer.shadowOpacity = 0.2
        topBarContainer.layer.shadowOffset = CGSize(width: 0, height: 2)
        topBarContainer.layer.shadowRadius = 4

        // Create buttons
        backButton = FloatingButton(systemImage: "chevron.left")
        backButton.addTarget(self, action: #selector(navigateBack), for: .touchUpInside)
        backButton.accessibilityLabel = "Back"

        tocButton = FloatingButton(systemImage: "list.bullet")
        tocButton.accessibilityLabel = "Table of Contents"
        tocButton.accessibilityIdentifier = "toc-button"
        tocButton.showsMenuAsPrimaryAction = true
        tocButton.menu = buildTOCMenu()
        // Hide TOC button if there's no meaningful table of contents
        tocButton.isHidden = chapter.tableOfContents.count < 2

        settingsButton = FloatingButton(systemImage: "gearshape")
        settingsButton.addTarget(self, action: #selector(showSettings), for: .touchUpInside)
        settingsButton.accessibilityLabel = "Settings"

        chatButton = FloatingButton(systemImage: "text.bubble")
        chatButton.addTarget(self, action: #selector(showChat), for: .touchUpInside)
        chatButton.accessibilityLabel = "Chat"

        // Title label - shows book title
        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.text = bookTitle ?? "Reader"
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Add buttons and title to container
        topBarContainer.addSubview(backButton)
        topBarContainer.addSubview(tocButton)
        topBarContainer.addSubview(settingsButton)
        topBarContainer.addSubview(chatButton)
        topBarContainer.addSubview(titleLabel)

        view.addSubview(topBarContainer)

        NSLayoutConstraint.activate([
            // Top bar container at top
            topBarContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            topBarContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            topBarContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            topBarContainer.heightAnchor.constraint(equalToConstant: 76),

            // Blur fills container
            blurView.topAnchor.constraint(equalTo: topBarContainer.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: topBarContainer.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: topBarContainer.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: topBarContainer.bottomAnchor),

            // Back button - top left within container
            backButton.topAnchor.constraint(equalTo: topBarContainer.topAnchor, constant: 16),
            backButton.leadingAnchor.constraint(equalTo: topBarContainer.leadingAnchor, constant: 16),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            // TOC button - next to back button
            tocButton.topAnchor.constraint(equalTo: topBarContainer.topAnchor, constant: 16),
            tocButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 8),
            tocButton.widthAnchor.constraint(equalToConstant: 44),
            tocButton.heightAnchor.constraint(equalToConstant: 44),

            // Settings button - top right within container
            settingsButton.topAnchor.constraint(equalTo: topBarContainer.topAnchor, constant: 16),
            settingsButton.trailingAnchor.constraint(equalTo: topBarContainer.trailingAnchor, constant: -16),
            settingsButton.widthAnchor.constraint(equalToConstant: 44),
            settingsButton.heightAnchor.constraint(equalToConstant: 44),

            // Chat button - next to settings button
            chatButton.topAnchor.constraint(equalTo: topBarContainer.topAnchor, constant: 16),
            chatButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -12),
            chatButton.widthAnchor.constraint(equalToConstant: 44),
            chatButton.heightAnchor.constraint(equalToConstant: 44),

            // Title label - centered between TOC button and chat button
            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: tocButton.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: chatButton.leadingAnchor, constant: -12)
        ])
    }

    private func setupScrubber() {
        // Container with blur background
        scrubberContainer = UIView()
        scrubberContainer.translatesAutoresizingMaskIntoConstraints = false
        scrubberContainer.backgroundColor = .clear

        // Blur background - use thin material for more transparency
        let blurEffect = UIBlurEffect(style: .systemThinMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 16
        blurView.clipsToBounds = true
        scrubberContainer.addSubview(blurView)

        // Read extent indicator (shows as tinted track under the slider)
        scrubberReadExtentView = UIView()
        scrubberReadExtentView.translatesAutoresizingMaskIntoConstraints = false
        scrubberReadExtentView.backgroundColor = UIColor.systemRed.withAlphaComponent(0.3)
        scrubberReadExtentView.layer.cornerRadius = 2
        scrubberContainer.addSubview(scrubberReadExtentView)

        // Slider
        scrubberSlider = UISlider()
        scrubberSlider.translatesAutoresizingMaskIntoConstraints = false
        scrubberSlider.minimumValue = 0
        scrubberSlider.maximumValue = 1
        scrubberSlider.value = 0
        scrubberSlider.minimumTrackTintColor = .systemBlue
        scrubberSlider.maximumTrackTintColor = .systemGray4
        scrubberSlider.addTarget(self, action: #selector(scrubberValueChanged), for: .valueChanged)
        scrubberSlider.addTarget(self, action: #selector(scrubberTouchEnded), for: [.touchUpInside, .touchUpOutside])
        scrubberSlider.accessibilityLabel = "Page scrubber"
        scrubberContainer.addSubview(scrubberSlider)

        // Page label
        pageLabel = UILabel()
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        pageLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        pageLabel.textColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .white : .black
        }
        pageLabel.textAlignment = .center
        pageLabel.text = "Page 1 of 1"
        pageLabel.accessibilityIdentifier = "scrubber-page-label"
        scrubberContainer.addSubview(pageLabel)

        // Shadow for container
        scrubberContainer.layer.shadowColor = UIColor.black.cgColor
        scrubberContainer.layer.shadowOpacity = 0.2
        scrubberContainer.layer.shadowOffset = CGSize(width: 0, height: -2)
        scrubberContainer.layer.shadowRadius = 4

        view.addSubview(scrubberContainer)

        NSLayoutConstraint.activate([
            // Container at bottom
            scrubberContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            scrubberContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            scrubberContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            scrubberContainer.heightAnchor.constraint(equalToConstant: 72),

            // Blur fills container
            blurView.topAnchor.constraint(equalTo: scrubberContainer.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: scrubberContainer.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: scrubberContainer.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: scrubberContainer.bottomAnchor),

            // Page label at top
            pageLabel.topAnchor.constraint(equalTo: scrubberContainer.topAnchor, constant: 12),
            pageLabel.centerXAnchor.constraint(equalTo: scrubberContainer.centerXAnchor),

            // Slider below page label
            scrubberSlider.topAnchor.constraint(equalTo: pageLabel.bottomAnchor, constant: 8),
            scrubberSlider.leadingAnchor.constraint(equalTo: scrubberContainer.leadingAnchor, constant: 16),
            scrubberSlider.trailingAnchor.constraint(equalTo: scrubberContainer.trailingAnchor, constant: -16),

            // Read extent indicator aligned with slider track
            scrubberReadExtentView.centerYAnchor.constraint(equalTo: scrubberSlider.centerYAnchor),
            scrubberReadExtentView.leadingAnchor.constraint(equalTo: scrubberSlider.leadingAnchor),
            scrubberReadExtentView.heightAnchor.constraint(equalToConstant: 4)
        ])
    }

    private func setupTapGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        // Toggle overlay visibility
        setOverlayVisible(!overlayVisible, animated: true)
    }

    private func setOverlayVisible(_ visible: Bool, animated: Bool) {
        overlayVisible = visible
        let alpha: CGFloat = visible ? 1.0 : 0.0

        if animated {
            UIView.animate(withDuration: 0.25) {
                self.topBarContainer.alpha = alpha
                self.scrubberContainer.alpha = alpha
            }
        } else {
            topBarContainer.alpha = alpha
            scrubberContainer.alpha = alpha
        }
    }

    private func updateScrubber() {
        guard viewModel.totalPages > 0 else { return }

        let totalPages = viewModel.totalPages
        let currentPage = viewModel.currentPageIndex
        let maxReadPage = viewModel.maxReadPageIndex

        // Update slider position
        let sliderValue = Float(currentPage) / Float(max(1, totalPages - 1))
        scrubberSlider.value = sliderValue

        // Update page label (chapter info shown only if it fits)
        let pageText = "Page \(currentPage + 1) of \(totalPages)"
        pageLabel.text = pageText

        // Update read extent indicator width
        let maxReadFraction = CGFloat(maxReadPage) / CGFloat(max(1, totalPages - 1))
        let sliderWidth = scrubberSlider.bounds.width
        let extentWidth = sliderWidth * maxReadFraction

        // Find the extent view width constraint and update it
        for constraint in scrubberReadExtentView.constraints where constraint.firstAttribute == .width {
            constraint.isActive = false
        }
        scrubberReadExtentView.widthAnchor.constraint(equalToConstant: max(4, extentWidth)).isActive = true
    }

    private func maybePerformUITestJump(totalPages: Int) {
        guard let targetPage = uiTestTargetPage,
              !hasPerformedUITestJump,
              totalPages > 0 else { return }
        hasPerformedUITestJump = true
        let targetIndex = min(max(0, targetPage - 1), totalPages - 1)
        pageRenderer.navigateToPage(targetIndex, animated: false)
        viewModel.updateCurrentPage(targetIndex, totalPages: totalPages)
        updateScrubber()
    }

    private func maybeNavigateToInitialSpineItem() {
        guard let spineIndex = initialSpineItemIndex,
              !hasNavigatedToInitialSpineItem else { return }
        hasNavigatedToInitialSpineItem = true

        // Get the spine item ID at the given index
        guard spineIndex < chapter.htmlSections.count else {
            Self.logger.error("Initial spine item index \(spineIndex) out of range (max: \(self.chapter.htmlSections.count - 1))")
            return
        }

        let spineItemId = chapter.htmlSections[spineIndex].spineItemId
        Self.logger.info("Navigating to initial spine item index \(spineIndex): \(spineItemId)")
        pageRenderer.navigateToSpineItem(spineItemId, animated: false)
    }

    @objc private func scrubberValueChanged(_ sender: UISlider) {
        guard viewModel.totalPages > 1 else { return }

        let targetPage = Int(round(sender.value * Float(viewModel.totalPages - 1)))
        viewModel.navigateToPage(targetPage)
        viewModel.updateCurrentPage(targetPage, totalPages: viewModel.totalPages)
        updateScrubber()

        // Note: updateScrubber() already updates the label with chapter info
    }

    @objc private func scrubberTouchEnded(_ sender: UISlider) {
        guard viewModel.totalPages > 1 else { return }

        let targetPage = Int(round(sender.value * Float(viewModel.totalPages - 1)))
        pageRenderer.navigateToPage(targetPage, animated: false)
        viewModel.updateCurrentPage(targetPage, totalPages: viewModel.totalPages)
        updateScrubber()
    }

    private func setupKeyCommands() {
        // Arrow key navigation
        addKeyCommand(UIKeyCommand(
            input: UIKeyCommand.inputLeftArrow,
            modifierFlags: [],
            action: #selector(navigateToPreviousPage)
        ))
        addKeyCommand(UIKeyCommand(
            input: UIKeyCommand.inputRightArrow,
            modifierFlags: [],
            action: #selector(navigateToNextPage)
        ))
    }

    private func bindViewModel() {
        // Observe font scale changes
        viewModel.$fontScale
            .dropFirst()
            .sink { [weak self] newScale in
                guard let self else { return }
                self.pageRenderer.fontScale = newScale
            }
            .store(in: &cancellables)

        // Observe settings presented
        viewModel.$settingsPresented
            .filter { $0 }
            .sink { [weak self] _ in
                self?.showSettings()
                self?.viewModel.settingsPresented = false
            }
            .store(in: &cancellables)
    }


    @objc private func showSettings() {
        let settingsVC = ReaderSettingsViewController(
            fontScale: viewModel.fontScale,
            onFontScaleChanged: { [weak self] newScale in
                self?.viewModel.updateFontScale(newScale)
            }
        )
        let navController = UINavigationController(rootViewController: settingsVC)
        present(navController, animated: true)
    }

    @objc private func showChat() {
        openChatWithSelection(nil)
    }

    private func openChatWithSelection(_ selection: SelectionPayload?) {
        // Create book context from current state
        let bookContext = ReaderBookContext(
            chapter: chapter,
            bookId: bookId,
            bookTitle: bookTitle ?? "Unknown Book",
            bookAuthor: bookAuthor,
            currentSpineItemId: viewModel.currentSpineItemId ?? "",
            currentBlockId: viewModel.currentBlockId
        )

        let chatContainer = ChatContainerViewController(context: bookContext, selection: selection)
        chatContainer.modalPresentationStyle = .fullScreen

        present(chatContainer, animated: true)
    }

    @objc private func navigateBack() {
        navigationController?.popViewController(animated: true)
    }

    // MARK: - Table of Contents

    private func buildTOCMenu() -> UIMenu {
        let tocItems = chapter.tableOfContents
        let actions = tocItems.map { item in
            UIAction(title: item.label) { [weak self] _ in
                self?.navigateToChapter(item)
            }
        }
        return UIMenu(title: "Table of Contents", children: actions)
    }

    private func navigateToChapter(_ tocItem: TOCItem) {
        Self.logger.info("Navigating to chapter: \(tocItem.label) (spine: \(tocItem.id))")

        // Navigate to the spine item
        pageRenderer.navigateToSpineItem(tocItem.id, animated: false)

        // Show the scrubber overlay
        setOverlayVisible(true, animated: true)

        // Hide the scrubber after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.setOverlayVisible(false, animated: true)
        }
    }

    @objc private func navigateToPreviousPage() {
        pageRenderer.navigateToPreviousPage()
    }

    @objc private func navigateToNextPage() {
        pageRenderer.navigateToNextPage()
    }

    private static func parseUITestTargetPage() -> Int? {
        let prefix = "--uitesting-jump-to-page="
        for arg in CommandLine.arguments where arg.hasPrefix(prefix) {
            let value = arg.dropFirst(prefix.count)
            if let page = Int(value), page > 0 {
                return page
            }
        }
        return nil
    }

    // MARK: - Render Mode Switching

    @objc private func renderModeDidChange(_ notification: Notification) {
        guard let newMode = notification.object as? RenderMode else { return }
        switchRenderer(to: newMode)
    }

    private func switchRenderer(to mode: RenderMode) {

        // Mark that we're waiting for renderer to be ready
        awaitingRendererReady = true

        // Show loading overlay
        showLoadingOverlay(message: "Switching to \(mode.displayName) renderer...")

        // Delay slightly to allow overlay to appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.performRendererSwitch(to: mode)
        }
    }

    private func performRendererSwitch(to mode: RenderMode) {
        // Remove old renderer
        let oldRendererVC = pageRenderer.viewController
        oldRendererVC.willMove(toParent: nil)
        oldRendererVC.view.removeFromSuperview()
        oldRendererVC.removeFromParent()

        // Create new renderer
        let renderer: PageRenderer
        switch mode {
        case .native:
            renderer = NativePageViewController(
                htmlSections: chapter.htmlSections,
                bookId: bookId,
                bookTitle: bookTitle,
                bookAuthor: bookAuthor,
                chapterTitle: chapter.title,
                fontScale: viewModel.fontScale,
                initialBlockId: viewModel.currentBlockId
            )

        case .webView:
            renderer = WebPageViewController(
                htmlSections: chapter.htmlSections,
                bookTitle: bookTitle,
                bookAuthor: bookAuthor,
                chapterTitle: chapter.title,
                fontScale: viewModel.fontScale,
                initialPageIndex: viewModel.currentPageIndex,
                initialBlockId: viewModel.currentBlockId,
                hrefToSpineItemId: chapter.hrefToSpineItemId
            )
        }

        // Configure callbacks
        renderer.onSendToLLM = { [weak self] selection in
            self?.openChatWithSelection(selection)
        }
        renderer.onPageChanged = { [weak self] newPage, totalPages in
            self?.viewModel.updateCurrentPage(newPage, totalPages: totalPages)
            self?.updateScrubber()
            self?.maybePerformUITestJump(totalPages: totalPages)

            // Hide loading overlay when renderer reports first page (content is ready)
            if self?.awaitingRendererReady == true {
                self?.awaitingRendererReady = false
                self?.hideLoadingOverlay()
            }
        }
        renderer.onBlockPositionChanged = { [weak self] blockId, spineItemId in
            self?.viewModel.updateBlockPosition(blockId: blockId, spineItemId: spineItemId)
        }
        renderer.onRenderReady = {
            NotificationCenter.default.post(name: ReaderPreferences.readerRenderReadyNotification, object: nil)
        }

        self.pageRenderer = renderer

        // Add new renderer
        let rendererVC = renderer.viewController
        addChild(rendererVC)
        view.insertSubview(rendererVC.view, at: 0)
        rendererVC.view.frame = view.bounds
        rendererVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        rendererVC.didMove(toParent: self)

        // Ensure overlay elements are on top
        view.bringSubviewToFront(topBarContainer)
        view.bringSubviewToFront(scrubberContainer)
        if let overlay = loadingOverlay {
            view.bringSubviewToFront(overlay)
        }

        // Fallback: hide overlay after 10 seconds if callback never fires
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.awaitingRendererReady == true {
                self?.awaitingRendererReady = false
                self?.hideLoadingOverlay()
            }
        }
    }

    private func showLoadingOverlay(message: String) {
        // Remove existing overlay if any
        loadingOverlay?.removeFromSuperview()

        let overlay = UIView()
        overlay.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
        overlay.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.startAnimating()

        let label = UILabel()
        label.text = message
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .label
        label.textAlignment = .center

        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(label)
        overlay.addSubview(stack)

        view.addSubview(overlay)
        loadingOverlay = overlay

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)
        ])

        overlay.alpha = 0
        UIView.animate(withDuration: 0.2) {
            overlay.alpha = 1
        }
    }

    private func hideLoadingOverlay() {
        guard let overlay = loadingOverlay else { return }
        UIView.animate(withDuration: 0.2, animations: {
            overlay.alpha = 0
        }, completion: { _ in
            overlay.removeFromSuperview()
            self.loadingOverlay = nil
        })
    }
}

// MARK: - UIGestureRecognizerDelegate
extension ReaderViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Allow tap gesture to work alongside WebView gestures
        return true
    }
}

// MARK: - FloatingButton
private final class FloatingButton: UIButton {
    init(systemImage: String) {
        super.init(frame: .zero)

        // Button configuration
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: systemImage)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)

        // Adaptive icon color: dark icons in light mode, light icons in dark mode
        let iconColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .white : .black
        }
        config.baseForegroundColor = iconColor
        configuration = config

        // Layout
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
