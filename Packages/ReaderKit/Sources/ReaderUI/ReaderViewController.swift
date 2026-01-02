import UIKit
import SwiftUI
import Combine
import ReaderCore
import OSLog

public final class ReaderViewController: UIViewController {
    private static let logger = Logger(subsystem: "com.example.reader", category: "reader-vc")
    private let viewModel: ReaderViewModel
    private let chapter: Chapter
    private var webPageViewController: WebPageViewController!
    private var cancellables = Set<AnyCancellable>()

    #if DEBUG
    private var debugOverlay: DebugOverlayView?
    #endif

    public init(chapter: Chapter = SampleChapter.make()) {
        self.viewModel = ReaderViewModel(chapter: chapter)
        self.chapter = chapter
        super.init(nibName: nil, bundle: nil)
    }

    public init(epubURL: URL, maxSections: Int = .max) {
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
        let settingsView = ReaderSettingsView(fontScale: Binding(
            get: { [weak self] in self?.viewModel.fontScale ?? 1.0 },
            set: { [weak self] newValue in self?.viewModel.updateFontScale(newValue) }
        ))
        let hostingController = UIHostingController(rootView: settingsView)
        present(hostingController, animated: true)
    }

    @objc private func navigateToPreviousPage() {
        webPageViewController.navigateToPreviousPage()
    }

    @objc private func navigateToNextPage() {
        webPageViewController.navigateToNextPage()
    }

    private func presentLLMModal(with payload: LLMPayload) {
        let modalView = LLMModalView(payload: payload)
        let hostingController = UIHostingController(rootView: modalView)
        present(hostingController, animated: true) {
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
