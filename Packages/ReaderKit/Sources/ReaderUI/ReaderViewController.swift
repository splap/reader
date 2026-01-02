import UIKit
import SwiftUI
import Combine
import ReaderCore

public final class ReaderViewController: UIViewController {
    private let viewModel: ReaderViewModel
    private var pageViewController: UIPageViewController!
    private var cancellables = Set<AnyCancellable>()

    #if DEBUG
    private var debugOverlay: DebugOverlayView?
    #endif

    public init(chapter: Chapter = SampleChapter.make()) {
        self.viewModel = ReaderViewModel(chapter: chapter)
        super.init(nibName: nil, bundle: nil)
    }

    public init(epubURL: URL, maxSections: Int = .max) {
        do {
            let chapter = try EPUBLoader().loadChapter(from: epubURL, maxSections: maxSections)
            self.viewModel = ReaderViewModel(chapter: chapter)
        } catch {
            self.viewModel = ReaderViewModel(chapter: SampleChapter.make())
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        setupPageViewController()
        setupNavigationBar()
        setupKeyCommands()
        setupDebugOverlay()
        bindViewModel()
    }

    private var hasInitialLayout = false

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Update page view controller frame
        pageViewController.view.frame = view.bounds

        let contentInsets = UIEdgeInsets(top: 48, left: 48, bottom: 48, right: 48)
        viewModel.updateLayout(pageSize: view.bounds.size, insets: contentInsets)

        // Show initial page after first layout
        if !hasInitialLayout && !viewModel.pages.isEmpty {
            hasInitialLayout = true
            showPage(at: viewModel.currentPageIndex, animated: false)
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
        }
        #endif
    }

    private func setupPageViewController() {
        pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: nil
        )
        pageViewController.dataSource = self
        pageViewController.delegate = self

        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.view.frame = view.bounds
        pageViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pageViewController.didMove(toParent: self)
    }

    private func setupNavigationBar() {
        let settingsButton = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(showSettings)
        )
        navigationItem.rightBarButtonItem = settingsButton
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
        // Observe pages changes
        viewModel.$pages
            .sink { [weak self] pages in
                guard let self, !pages.isEmpty else { return }
                let currentIndex = self.viewModel.currentPageIndex
                if currentIndex < pages.count {
                    self.showPage(at: currentIndex, animated: false)
                }
            }
            .store(in: &cancellables)

        // Observe current page changes
        viewModel.$currentPageIndex
            .removeDuplicates()
            .sink { [weak self] newIndex in
                guard let self else { return }
                self.showPage(at: newIndex, animated: true)
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

    private func showPage(at index: Int, animated: Bool) {
        guard index >= 0,
              index < viewModel.pages.count,
              pageViewController != nil else { return }

        let page = viewModel.pages[index]
        let pageVC = PageViewController(
            page: page,
            pageIndex: index,
            onSendToLLM: { [weak self] selection in
                self?.viewModel.llmPayload = LLMPayload(selection: selection)
            }
        )

        let direction: UIPageViewController.NavigationDirection = {
            if let current = pageViewController.viewControllers?.first as? PageViewController {
                return index > current.pageIndex ? .forward : .reverse
            }
            return .forward
        }()

        pageViewController.setViewControllers(
            [pageVC],
            direction: direction,
            animated: animated,
            completion: nil
        )
    }

    @objc private func showSettings() {
        let settingsView = ReaderSettingsView(fontScale: Binding(
            get: { [weak self] in self?.viewModel.fontScale ?? 1.0 },
            set: { [weak self] newValue in self?.viewModel.updateFontScale(newValue) }
        ))
        let hostingController = UIHostingController(rootView: settingsView)
        present(hostingController, animated: true)
    }

    @objc private func navigateToPreviousPage() {
        viewModel.navigateToPreviousPage()
    }

    @objc private func navigateToNextPage() {
        viewModel.navigateToNextPage()
    }

    private func presentLLMModal(with payload: LLMPayload) {
        let modalView = LLMModalView(payload: payload)
        let hostingController = UIHostingController(rootView: modalView)
        present(hostingController, animated: true) {
            self.viewModel.llmPayload = nil
        }
    }
}

// MARK: - UIPageViewControllerDataSource
extension ReaderViewController: UIPageViewControllerDataSource {
    public func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let pageVC = viewController as? PageViewController else { return nil }
        let previousIndex = pageVC.pageIndex - 1
        guard previousIndex >= 0 else { return nil }

        let page = viewModel.pages[previousIndex]
        return PageViewController(
            page: page,
            pageIndex: previousIndex,
            onSendToLLM: { [weak self] selection in
                self?.viewModel.llmPayload = LLMPayload(selection: selection)
            }
        )
    }

    public func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let pageVC = viewController as? PageViewController else { return nil }
        let nextIndex = pageVC.pageIndex + 1
        guard nextIndex < viewModel.pages.count else { return nil }

        let page = viewModel.pages[nextIndex]
        return PageViewController(
            page: page,
            pageIndex: nextIndex,
            onSendToLLM: { [weak self] selection in
                self?.viewModel.llmPayload = LLMPayload(selection: selection)
            }
        )
    }
}

// MARK: - UIPageViewControllerDelegate
extension ReaderViewController: UIPageViewControllerDelegate {
    public func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed,
              let pageVC = pageViewController.viewControllers?.first as? PageViewController else {
            return
        }
        viewModel.updateCurrentPage(pageVC.pageIndex)
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
        backgroundColor = UIColor.black.withAlphaComponent(0.7)
        layer.cornerRadius = 8
        isUserInteractionEnabled = false

        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 4

        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }

    func update() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard let viewModel else { return }

        let currentPage = viewModel.currentPageIndex
        let textLength = (currentPage >= 0 && currentPage < viewModel.pages.count) ?
            viewModel.pages[currentPage].textStorage.length : 0

        let wordsOnPage: Int = {
            guard currentPage >= 0 && currentPage < viewModel.pages.count else { return 0 }
            let text = viewModel.pages[currentPage].textStorage.string
            return countWords(in: text)
        }()

        stackView.addArrangedSubview(makeLabel("build: \(BuildInfo.timestamp)"))
        stackView.addArrangedSubview(makeLabel("pages: \(viewModel.pages.count)"))
        stackView.addArrangedSubview(makeLabel("text length (chars): \(textLength)"))
        stackView.addArrangedSubview(makeLabel("current page: \(currentPage)"))
        stackView.addArrangedSubview(makeLabel("words on page: \(wordsOnPage)"))

        sizeToFit()
    }

    private func makeLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .white
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
