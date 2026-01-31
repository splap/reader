import Combine
import OSLog
import ReaderCore
import SwiftUI
import UIKit

/// Delegate protocol for ReaderViewController to communicate with its container
protocol ReaderViewControllerContainerDelegate: AnyObject {
    func readerViewControllerDidRequestOverlayToggle(_ controller: ReaderViewController)
    func readerViewControllerDidRequestChat(_ controller: ReaderViewController, selection: SelectionPayload?)
}

public final class ReaderViewController: UIViewController {
    private static let logger = Log.logger(category: "reader-vc")
    private let viewModel: ReaderViewModel
    let chapter: Chapter
    private let bookId: String
    private let bookTitle: String?
    private let bookAuthor: String?
    private var pageRenderer: PageRenderer!
    private var cancellables = Set<AnyCancellable>()
    private var scrubberContainer: UIView!
    private var scrubberSlider: UISlider!
    private var scrubberReadExtentView: UIView!
    private var pageLabel: UILabel!
    private var loadingProgressLabel: UILabel!
    private var overlayVisible = false
    private let uiTestTargetPage: Int? = ReaderViewController.parseUITestTargetPage()
    private var hasPerformedUITestJump = false
    private let initialSpineItemIndex: Int?
    private var hasNavigatedToInitialSpineItem = false

    // Loading overlay for renderer switch
    private var loadingOverlay: UIView?
    private var awaitingRendererReady = false

    // Spine (chapter) tracking for progress display
    private(set) var currentSpineIndex: Int = 0
    private var totalSpineItems: Int = 0

    // Container delegate for overlay toggle and chat requests
    weak var containerDelegate: ReaderViewControllerContainerDelegate?

    // Whether this VC is being used standalone (without container) - legacy support
    private var isStandalone: Bool { containerDelegate == nil }

    // Standalone mode top bar (only used when no container)
    private var standaloneTopBar: UIView?

    // Track the layout key used for current page counting
    private var countingLayoutKey: LayoutKey?

    // Suppress scrubber updates during cross-spine navigation to prevent jitter
    private var isScrubberNavigating: Bool = false

    public init(chapter: Chapter = SampleChapter.make(), bookId: String = UUID().uuidString, bookTitle: String? = nil, bookAuthor: String? = nil, initialSpineItemIndex: Int? = nil) {
        viewModel = ReaderViewModel(chapter: chapter, bookId: bookId)
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
            viewModel = ReaderViewModel(chapter: chapter, bookId: bookId)
        } catch {
            Self.logger.error("Failed to load EPUB from \(epubURL.path): \(error)")
            let fallback = SampleChapter.make()
            chapter = fallback
            viewModel = ReaderViewModel(chapter: fallback, bookId: bookId)
        }
        super.init(nibName: nil, bundle: nil)
        Self.logger.info("PERF: ReaderViewController init took \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - initStart))s")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        // Setup UI elements BEFORE web page VC (which triggers callbacks during viewDidLoad)
        setupScrubber()
        setupWebPageViewController()
        setupTapGesture()
        setupKeyCommands()
        bindViewModel()

        let showOverlay = CommandLine.arguments.contains("--uitesting-show-overlay")
        // Start with overlay hidden unless UI tests request it visible.
        setOverlayVisible(showOverlay, animated: false)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Only hide nav bar if standalone (container handles this otherwise)
        if isStandalone {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Only restore nav bar if standalone
        if isStandalone {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }

    private var hasInitialLayout = false

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        pageRenderer.viewController.view.frame = view.bounds

        // Ensure scrubber is above the page renderer
        view.bringSubviewToFront(scrubberContainer)

        if !hasInitialLayout {
            hasInitialLayout = true
        }
    }

    private func setupWebPageViewController() {
        // Create WebView renderer
        let renderer = WebPageViewController(
            htmlSections: chapter.htmlSections,
            bookTitle: bookTitle,
            bookAuthor: bookAuthor,
            chapterTitle: chapter.title,
            fontScale: viewModel.fontScale,
            initialCFI: viewModel.initialCFI,
            hrefToSpineItemId: chapter.hrefToSpineItemId
        )

        // Configure callbacks
        renderer.onSendToLLM = { [weak self] selection in
            self?.openChatWithSelection(selection)
        }
        renderer.onPageChanged = { [weak self] newPage, totalPages in
            self?.viewModel.updateCurrentPage(newPage, totalPages: totalPages)
            self?.updateScrubber()
            self?.maybePerformUITestJump(totalPages: totalPages)
            self?.maybeNavigateToInitialSpineItem()
            self?.checkLayoutForPageCounting()
        }
        renderer.onSpineChanged = { [weak self] spineIndex, totalSpines in
            self?.currentSpineIndex = spineIndex
            self?.totalSpineItems = totalSpines
            self?.viewModel.setCurrentSpineIndex(spineIndex)
            self?.updateScrubber()
        }
        // Block position tracking removed - CFI is the only position mechanism
        renderer.onRenderReady = { [weak self] in
            NotificationCenter.default.post(name: ReaderPreferences.readerRenderReadyNotification, object: nil)
        }
        renderer.onCFIPositionChanged = { [weak self] cfi, spineIndex in
            self?.viewModel.updateCFIPosition(cfi: cfi, spineIndex: spineIndex)
        }

        // Hook up loading progress callback (WebView renderer only)
        if let webRenderer = renderer as? WebPageViewController {
            webRenderer.onLoadingProgress = { [weak self] loaded, total in
                self?.updateLoadingProgress(loaded: loaded, total: total)
            }
        }

        pageRenderer = renderer

        let rendererVC = renderer.viewController
        addChild(rendererVC)
        view.addSubview(rendererVC.view)
        rendererVC.view.frame = view.bounds
        rendererVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        rendererVC.didMove(toParent: self)
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

        // Loading progress label (currently hidden; spine-scoped rendering loads one chapter at a time)
        loadingProgressLabel = UILabel()
        loadingProgressLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingProgressLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        loadingProgressLabel.textColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .lightGray : .darkGray
        }
        loadingProgressLabel.textAlignment = .center
        loadingProgressLabel.text = ""
        loadingProgressLabel.isHidden = true
        scrubberContainer.addSubview(loadingProgressLabel)

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
            pageLabel.topAnchor.constraint(equalTo: scrubberContainer.topAnchor, constant: 8),
            pageLabel.centerXAnchor.constraint(equalTo: scrubberContainer.centerXAnchor),

            // Loading progress label below page label
            loadingProgressLabel.topAnchor.constraint(equalTo: pageLabel.bottomAnchor, constant: 2),
            loadingProgressLabel.centerXAnchor.constraint(equalTo: scrubberContainer.centerXAnchor),

            // Slider below loading progress label
            scrubberSlider.topAnchor.constraint(equalTo: loadingProgressLabel.bottomAnchor, constant: 4),
            scrubberSlider.leadingAnchor.constraint(equalTo: scrubberContainer.leadingAnchor, constant: 16),
            scrubberSlider.trailingAnchor.constraint(equalTo: scrubberContainer.trailingAnchor, constant: -16),

            // Read extent indicator aligned with slider track
            scrubberReadExtentView.centerYAnchor.constraint(equalTo: scrubberSlider.centerYAnchor),
            scrubberReadExtentView.leadingAnchor.constraint(equalTo: scrubberSlider.leadingAnchor),
            scrubberReadExtentView.heightAnchor.constraint(equalToConstant: 4),
        ])
    }

    private func setupTapGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func handleTap(_: UITapGestureRecognizer) {
        // Toggle overlay visibility - delegate to container if available
        if let delegate = containerDelegate {
            delegate.readerViewControllerDidRequestOverlayToggle(self)
        } else {
            setOverlayVisible(!overlayVisible, animated: true)
        }
    }

    /// Set overlay (scrubber) visibility - called by container
    func setOverlayVisible(_ visible: Bool, animated: Bool) {
        overlayVisible = visible
        let alpha: CGFloat = visible ? 1.0 : 0.0

        if animated {
            UIView.animate(withDuration: 0.25) {
                self.scrubberContainer.alpha = alpha
            }
        } else {
            scrubberContainer.alpha = alpha
        }
    }

    private func updateScrubber() {
        guard viewModel.totalPages > 0 else { return }

        // Skip updates during cross-spine scrubber navigation to prevent jitter
        // The slider and label are already set to the target position
        guard !isScrubberNavigating else { return }

        let totalPages = viewModel.totalPages
        let currentPage = viewModel.currentPageIndex

        // Build page label text and slider position
        let pageText: String
        let sliderValue: Float

        // If global page counts are available, use global position
        if case let .complete(pageCounts) = viewModel.globalPageCountStatus, totalSpineItems > 1 {
            let globalPage = pageCounts.globalPage(
                spineIndex: currentSpineIndex,
                localPage: currentPage
            )
            sliderValue = Float(globalPage - 1) / Float(max(1, pageCounts.totalPages - 1))
            pageText = "Page \(globalPage) of \(pageCounts.totalPages)"
        } else if totalSpineItems > 1 {
            // Show chapter-level info while counting
            sliderValue = Float(currentPage) / Float(max(1, totalPages - 1))
            pageText = "Page \(currentPage + 1) of \(totalPages) · Ch. \(currentSpineIndex + 1) of \(totalSpineItems)"
        } else {
            // Single-chapter book
            sliderValue = Float(currentPage) / Float(max(1, totalPages - 1))
            pageText = "Page \(currentPage + 1) of \(totalPages)"
        }

        scrubberSlider.value = sliderValue
        pageLabel.text = pageText

        // Hide read extent indicator (CFI-based tracking doesn't use max page)
        scrubberReadExtentView.isHidden = true
    }

    /// Update the loading progress label (shows current spine item position)
    private func updateLoadingProgress(loaded _: Int, total _: Int) {
        // Guard against being called before UI is set up
        guard loadingProgressLabel != nil else { return }

        // With spine-scoped rendering, loaded is the current spine index + 1
        // We don't show this during normal reading, but it can be useful for debugging
        loadingProgressLabel.isHidden = true
        loadingProgressLabel.text = ""
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
            Self.logger.error("Initial spine item index \(spineIndex) out of range (max: \(chapter.htmlSections.count - 1))")
            return
        }

        let spineItemId = chapter.htmlSections[spineIndex].spineItemId
        Self.logger.info("Navigating to initial spine item index \(spineIndex): \(spineItemId)")
        pageRenderer.navigateToSpineItem(spineItemId, animated: false)
    }

    @objc private func scrubberValueChanged(_ sender: UISlider) {
        guard viewModel.totalPages > 1 else { return }

        // When global page counts are available, use global navigation
        if case let .complete(pageCounts) = viewModel.globalPageCountStatus, totalSpineItems > 1 {
            let targetGlobalPage = Int(round(sender.value * Float(pageCounts.totalPages - 1))) + 1
            let (targetSpine, targetLocalPage) = pageCounts.localPosition(forGlobalPage: targetGlobalPage)

            // During drag, only navigate within the same spine (for responsiveness)
            // Cross-spine navigation happens on touch end to avoid loading multiple spines
            if targetSpine == currentSpineIndex {
                pageRenderer.navigateToPage(targetLocalPage, animated: false)
                viewModel.updateCurrentPage(targetLocalPage, totalPages: viewModel.totalPages)
            }
            // Always update the label to show target position (preview)
            updateScrubberLabel(globalPage: targetGlobalPage, totalPages: pageCounts.totalPages)
        } else {
            // Local-only navigation (no global counts yet)
            let targetPage = Int(round(sender.value * Float(viewModel.totalPages - 1)))
            pageRenderer.navigateToPage(targetPage, animated: false)
            viewModel.updateCurrentPage(targetPage, totalPages: viewModel.totalPages)
            updateScrubber()
        }
    }

    @objc private func scrubberTouchEnded(_ sender: UISlider) {
        guard viewModel.totalPages > 1 else { return }

        // When global page counts are available, use global navigation
        if case let .complete(pageCounts) = viewModel.globalPageCountStatus, totalSpineItems > 1 {
            let targetGlobalPage = Int(round(sender.value * Float(pageCounts.totalPages - 1))) + 1
            let (targetSpine, targetLocalPage) = pageCounts.localPosition(forGlobalPage: targetGlobalPage)

            // If crossing spine boundaries, suppress scrubber updates until navigation completes
            if targetSpine != currentSpineIndex {
                isScrubberNavigating = true
                // Clear after spine load + page navigation completes (200ms covers the 100ms delay in WebPageViewController)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.isScrubberNavigating = false
                    self?.updateScrubber()
                }
            }

            // Commit navigation (may cross spine boundaries)
            pageRenderer.navigateToSpineIndex(targetSpine, atPage: targetLocalPage)
        } else {
            // Local-only navigation
            let targetPage = Int(round(sender.value * Float(viewModel.totalPages - 1)))
            pageRenderer.navigateToPage(targetPage, animated: false)
            viewModel.updateCurrentPage(targetPage, totalPages: viewModel.totalPages)
            updateScrubber()
        }
    }

    /// Update only the scrubber label (used during drag preview)
    private func updateScrubberLabel(globalPage: Int, totalPages: Int) {
        pageLabel.text = "Page \(globalPage) of \(totalPages)"
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
                pageRenderer.fontScale = newScale
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

        // Observe global page count status changes
        viewModel.$globalPageCountStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateScrubber()
            }
            .store(in: &cancellables)
    }

    func showSettings() {
        let settingsVC = ReaderSettingsViewController(
            fontScale: viewModel.fontScale,
            onFontScaleChanged: { [weak self] newScale in
                self?.viewModel.updateFontScale(newScale)
            }
        )
        let navController = UINavigationController(rootViewController: settingsVC)
        present(navController, animated: true)
    }

    private func openChatWithSelection(_ selection: SelectionPayload?) {
        // Delegate to container if available
        if let delegate = containerDelegate {
            delegate.readerViewControllerDidRequestChat(self, selection: selection)
            return
        }

        // Standalone fallback - present chat modally
        let spineIndex = viewModel.currentSpineIndex
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

        let chatContainer = ChatContainerViewController(context: bookContext, selection: selection)
        chatContainer.modalPresentationStyle = .fullScreen

        present(chatContainer, animated: true)
    }

    // MARK: - Table of Contents

    /// Whether there's a meaningful table of contents (more than 1 item)
    var hasMeaningfulTOC: Bool {
        chapter.tableOfContents.count >= 2
    }

    /// Build the table of contents menu for the navigation bar
    func buildTOCMenu() -> UIMenu? {
        let tocItems = chapter.tableOfContents
        guard !tocItems.isEmpty else { return nil }

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
        if let delegate = containerDelegate {
            // Container handles overlay visibility
            delegate.readerViewControllerDidRequestOverlayToggle(self)
        } else {
            setOverlayVisible(true, animated: true)

            // Hide the scrubber after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.setOverlayVisible(false, animated: true)
            }
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
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
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

    // MARK: - Global Page Counting

    /// Get the current layout key based on renderer state
    private func currentLayoutKey() -> LayoutKey? {
        guard let webVC = pageRenderer as? WebPageViewController else { return nil }

        let viewportWidth = Int(webVC.view.bounds.width)
        let viewportHeight = Int(webVC.view.bounds.height)

        guard viewportWidth > 0, viewportHeight > 0 else { return nil }

        return LayoutKey(
            fontScale: Double(viewModel.fontScale),
            marginSize: Int(ReaderPreferences.shared.marginSize),
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight
        )
    }

    /// Check if layout has changed and restart page counting if needed
    /// Called after every page change (which happens after any reflow)
    private func checkLayoutForPageCounting() {
        // Only count for multi-chapter books
        guard chapter.htmlSections.count > 1 else { return }

        guard let currentKey = currentLayoutKey() else { return }

        // If layout hasn't changed, nothing to do
        if currentKey == countingLayoutKey { return }

        // Layout changed - start or restart counting
        Self.logger.info("Layout changed, starting page count with: \(currentKey.hashString)")
        countingLayoutKey = currentKey
        viewModel.startGlobalPageCounting(htmlSections: chapter.htmlSections, layoutKey: currentKey)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension ReaderViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        // Allow tap gesture to work alongside WebView gestures
        true
    }
}
