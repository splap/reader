import UIKit
import SwiftUI
import Combine
import ReaderCore
import OSLog

public final class ReaderViewController: UIViewController {
    private static let logger = Log.logger(category: "reader-vc")
    private let viewModel: ReaderViewModel
    private let chapter: Chapter
    private let bookTitle: String?
    private let bookAuthor: String?
    private var pageRenderer: PageRenderer!
    private var cancellables = Set<AnyCancellable>()
    private var backButton: FloatingButton!
    private var settingsButton: FloatingButton!
    private var chatButton: FloatingButton!
    private var scrubberContainer: UIView!
    private var scrubberSlider: UISlider!
    private var scrubberReadExtentView: UIView!
    private var pageLabel: UILabel!
    private var overlayVisible = false
    private let uiTestTargetPage: Int? = ReaderViewController.parseUITestTargetPage()
    private var hasPerformedUITestJump = false

    #if DEBUG
    private var debugOverlay: DebugOverlayView?
    #endif

    public init(chapter: Chapter = SampleChapter.make(), bookTitle: String? = nil, bookAuthor: String? = nil) {
        self.viewModel = ReaderViewModel(chapter: chapter)
        self.chapter = chapter
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        super.init(nibName: nil, bundle: nil)
    }

    public init(epubURL: URL, bookTitle: String? = nil, bookAuthor: String? = nil, maxSections: Int = .max) {
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
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
        setupDebugOverlay()
        bindViewModel()

        let showOverlay = CommandLine.arguments.contains("--uitesting-show-overlay")
        // Start with overlay hidden unless UI tests request it visible.
        setOverlayVisible(showOverlay, animated: false)
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

        // Ensure floating buttons and scrubber are above the page renderer
        view.bringSubviewToFront(backButton)
        view.bringSubviewToFront(settingsButton)
        view.bringSubviewToFront(chatButton)
        view.bringSubviewToFront(scrubberContainer)

        if !hasInitialLayout {
            hasInitialLayout = true
            #if DEBUG
            debugOverlay?.update()
            #endif
        }

        #if DEBUG
        if let overlay = debugOverlay {
            overlay.sizeToFit()
            let x = (view.bounds.width - overlay.bounds.width) / 2
            let y = (view.bounds.height - overlay.bounds.height) / 2
            overlay.frame.origin = CGPoint(x: x, y: y)
            view.bringSubviewToFront(overlay)
        }
        #endif
    }

    private func setupWebPageViewController() {
        // Set current spine item ID if we have sections
        if let firstSection = chapter.htmlSections.first {
            viewModel.setCurrentSpineItem(firstSection.spineItemId)
        }

        // Create renderer based on current preference
        let renderer: PageRenderer
        let renderMode = ReaderPreferences.shared.renderMode

        Self.logger.info("Creating renderer with mode: \(renderMode.rawValue, privacy: .public)")

        switch renderMode {
        case .native:
            renderer = NativePageViewController(
                htmlSections: chapter.htmlSections,
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
                initialBlockId: viewModel.initialBlockId
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
            #if DEBUG
            self?.debugOverlay?.update()
            if let overlay = self?.debugOverlay {
                self?.view.bringSubviewToFront(overlay)
            }
            #endif
        }
        renderer.onBlockPositionChanged = { [weak self] blockId, spineItemId in
            self?.viewModel.updateBlockPosition(blockId: blockId, spineItemId: spineItemId)
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
        // Create buttons
        backButton = FloatingButton(systemImage: "chevron.left")
        backButton.addTarget(self, action: #selector(navigateBack), for: .touchUpInside)
        backButton.accessibilityLabel = "Back"

        settingsButton = FloatingButton(systemImage: "gearshape")
        settingsButton.addTarget(self, action: #selector(showSettings), for: .touchUpInside)
        settingsButton.accessibilityLabel = "Settings"

        chatButton = FloatingButton(systemImage: "text.bubble")
        chatButton.addTarget(self, action: #selector(showChat), for: .touchUpInside)
        chatButton.accessibilityLabel = "Chat"

        view.addSubview(backButton)
        view.addSubview(settingsButton)
        view.addSubview(chatButton)

        NSLayoutConstraint.activate([
            // Back button - top left
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            // Settings button - top right
            settingsButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            settingsButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            settingsButton.widthAnchor.constraint(equalToConstant: 44),
            settingsButton.heightAnchor.constraint(equalToConstant: 44),

            // Chat button - next to settings button
            chatButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            chatButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -12),
            chatButton.widthAnchor.constraint(equalToConstant: 44),
            chatButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func setupScrubber() {
        // Container with blur background
        scrubberContainer = UIView()
        scrubberContainer.translatesAutoresizingMaskIntoConstraints = false

        // Blur background
        let blurEffect = UIBlurEffect(style: .systemMaterial)
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
                self.backButton.alpha = alpha
                self.settingsButton.alpha = alpha
                self.chatButton.alpha = alpha
                self.scrubberContainer.alpha = alpha
            }
        } else {
            backButton.alpha = alpha
            settingsButton.alpha = alpha
            chatButton.alpha = alpha
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

        // Update page label
        pageLabel.text = "Page \(currentPage + 1) of \(totalPages)"

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

    @objc private func scrubberValueChanged(_ sender: UISlider) {
        guard viewModel.totalPages > 1 else { return }

        let targetPage = Int(round(sender.value * Float(viewModel.totalPages - 1)))
        viewModel.navigateToPage(targetPage)
        viewModel.updateCurrentPage(targetPage, totalPages: viewModel.totalPages)
        updateScrubber()

        // Update label immediately for responsiveness
        pageLabel.text = "Page \(targetPage + 1) of \(viewModel.totalPages)"
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

    private func setupDebugOverlay() {
        #if DEBUG
        debugOverlay = DebugOverlayView(viewModel: viewModel)
        if let overlay = debugOverlay {
            view.addSubview(overlay)
            view.bringSubviewToFront(overlay)
        }
        #endif
    }

    private func bindViewModel() {
        // Observe font scale changes
        viewModel.$fontScale
            .dropFirst()
            .sink { [weak self] newScale in
                guard let self else { return }
                self.pageRenderer.fontScale = newScale
                #if DEBUG
                self.debugOverlay?.update()
                #endif
            }
            .store(in: &cancellables)

        // Observe LLM payload
        viewModel.$llmPayload
            .compactMap { $0 }
            .sink { [weak self] payload in
                self?.presentLLMModal(with: payload)
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

    @objc private func navigateToPreviousPage() {
        pageRenderer.navigateToPreviousPage()
    }

    @objc private func navigateToNextPage() {
        pageRenderer.navigateToNextPage()
    }

    private func presentLLMModal(with payload: LLMPayload) {
        let modalVC = LLMModalViewController(selection: payload.selection)
        let navController = UINavigationController(rootViewController: modalVC)

        // Configure sheet presentation - nearly full screen
        if let sheet = navController.sheetPresentationController {
            // Custom detent for 95% height
            let customDetent = UISheetPresentationController.Detent.custom { context in
                return context.maximumDetentValue * 0.95
            }
            sheet.detents = [customDetent]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.largestUndimmedDetentIdentifier = nil // Dim background
            sheet.preferredCornerRadius = 16
        }

        present(navController, animated: true) {
            self.viewModel.llmPayload = nil
        }
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

        // Blur background
        let blurEffect = UIBlurEffect(style: .systemMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.isUserInteractionEnabled = false
        blurView.layer.cornerRadius = 22
        blurView.clipsToBounds = true
        blurView.translatesAutoresizingMaskIntoConstraints = false

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

        // Shadow
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4

        // Layout
        translatesAutoresizingMaskIntoConstraints = false

        // Add blur as background
        insertSubview(blurView, at: 0)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#if DEBUG
private final class DebugOverlayView: UIView {
    private weak var viewModel: ReaderViewModel?
    private let stackView = UIStackView()

    init(viewModel: ReaderViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        setupView()
        update()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.7)
                : UIColor.black.withAlphaComponent(0.7)
        }
        layer.cornerRadius = 8
        isUserInteractionEnabled = false
        clipsToBounds = true

        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 6

        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }

    override func sizeToFit() {
        super.sizeToFit()
        let size = stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        frame.size = CGSize(width: size.width + 32, height: size.height + 32)
    }

    func update() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard let viewModel else { return }

        stackView.addArrangedSubview(makeLabel("build: \(BuildInfo.timestamp)"))
        stackView.addArrangedSubview(makeLabel("total pages: \(viewModel.totalPages)"))
        stackView.addArrangedSubview(makeLabel("current page: \(viewModel.currentPageIndex)"))
        stackView.addArrangedSubview(makeLabel("font scale: \(String(format: "%.1f", viewModel.fontScale))x"))

        sizeToFit()
    }

    private func makeLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .black : .white
        }
        label.font = .systemFont(ofSize: 14)
        return label
    }

    private func countWords(in text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if !inWord {
                    count += 1
                    inWord = true
                }
            } else {
                inWord = false
            }
        }
        return count
    }
}
#endif
