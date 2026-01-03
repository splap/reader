import UIKit
import SwiftUI
import Combine
import ReaderCore
import OSLog

public final class ReaderViewController: UIViewController {
    private static let logger = Logger(subsystem: "com.example.reader", category: "reader-vc")
    private let viewModel: ReaderViewModel
    private let chapter: Chapter
    private let bookTitle: String?
    private let bookAuthor: String?
    private var webPageViewController: WebPageViewController!
    private var cancellables = Set<AnyCancellable>()

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
        setupNavigationBar()
        setupKeyCommands()
        setupDebugOverlay()
        bindViewModel()
    }

    private var hasInitialLayout = false

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        webPageViewController.view.frame = view.bounds

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
        let webPageVC = WebPageViewController(
            htmlSections: chapter.htmlSections,
            bookTitle: bookTitle,
            bookAuthor: bookAuthor,
            chapterTitle: chapter.title,
            fontScale: viewModel.fontScale,
            onSendToLLM: { [weak self] selection in
                self?.viewModel.llmPayload = LLMPayload(selection: selection)
            },
            onPageChanged: { [weak self] newPage, totalPages in
                self?.viewModel.updateCurrentPage(newPage, totalPages: totalPages)
                #if DEBUG
                self?.debugOverlay?.update()
                if let overlay = self?.debugOverlay {
                    self?.view.bringSubviewToFront(overlay)
                }
                #endif
            }
        )

        self.webPageViewController = webPageVC

        addChild(webPageVC)
        view.addSubview(webPageVC.view)
        webPageVC.view.frame = view.bounds
        webPageVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webPageVC.didMove(toParent: self)
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
        // Observe font scale changes
        viewModel.$fontScale
            .dropFirst()
            .sink { [weak self] newScale in
                guard let self else { return }
                self.webPageViewController.fontScale = newScale
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

    @objc private func navigateToPreviousPage() {
        webPageViewController.navigateToPreviousPage()
    }

    @objc private func navigateToNextPage() {
        webPageViewController.navigateToNextPage()
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
