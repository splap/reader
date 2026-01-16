import UIKit
import OSLog
import ReaderCore

/// Native renderer using UITextView with horizontal paging
public final class NativePageViewController: UIViewController, PageRenderer {

    private static let logger = Logger(subsystem: "com.splap.reader", category: "NativePageViewController")

    // MARK: - PageRenderer Protocol

    public var viewController: UIViewController { self }

    public var fontScale: CGFloat {
        didSet {
            guard fontScale != oldValue else { return }
            rebuildPagesAsync()
        }
    }

    public var onPageChanged: ((Int, Int) -> Void)?
    public var onBlockPositionChanged: ((String, String?) -> Void)?
    public var onSendToLLM: ((SelectionPayload) -> Void)?

    // MARK: - Private Properties

    private let htmlSections: [HTMLSection]
    private let bookTitle: String?
    private let bookAuthor: String?
    private let chapterTitle: String?
    private let initialBlockId: String?

    private var scrollView: UIScrollView!
    private var pageViews: [UIView] = []
    private var currentPageIndex: Int = 0
    private var totalPages: Int = 0

    private var attributedContent: AttributedContent?
    private var pageRanges: [NSRange] = []
    private var pageBlockIds: [[String]] = []

    private var hasBuiltPages = false
    private var loadingOverlay: UIView?

    // MARK: - Initialization

    public init(
        htmlSections: [HTMLSection],
        bookTitle: String? = nil,
        bookAuthor: String? = nil,
        chapterTitle: String? = nil,
        fontScale: CGFloat = 1.4,
        initialBlockId: String? = nil
    ) {
        self.htmlSections = htmlSections
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.chapterTitle = chapterTitle
        self.fontScale = fontScale
        self.initialBlockId = initialBlockId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupScrollView()
        setupKeyboardNavigation()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !hasBuiltPages && view.bounds.width > 0 && view.bounds.height > 0 {
            hasBuiltPages = true
            buildPages()
        }
    }

    // MARK: - Setup

    private func setupScrollView() {
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bounces = true
        scrollView.delegate = self
        scrollView.alwaysBounceVertical = false

        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupKeyboardNavigation() {
        // Arrow key navigation
        let leftArrow = UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(handleLeftArrow))
        let rightArrow = UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(handleRightArrow))
        addKeyCommand(leftArrow)
        addKeyCommand(rightArrow)
    }

    @objc private func handleLeftArrow() {
        navigateToPreviousPage()
    }

    @objc private func handleRightArrow() {
        navigateToNextPage()
    }

    // MARK: - Page Building

    private func buildPages() {
        Self.logger.info("Building pages for native renderer")

        // Show loading overlay for initial build
        showLoadingOverlay()

        let fontScale = self.fontScale
        let htmlSections = self.htmlSections
        let viewBounds = self.view.bounds
        let initialBlockId = self.initialBlockId

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Combine image caches from all sections
            let imageCache = htmlSections.reduce(into: [String: Data]()) { result, section in
                result.merge(section.imageCache) { _, new in new }
            }

            let converter = HTMLToAttributedStringConverter(imageCache: imageCache, fontScale: fontScale)
            let content = converter.convert(sections: htmlSections)

            Self.logger.info("Converted \(content.blockOrder.count, privacy: .public) blocks, \(content.fullPageImages.count, privacy: .public) full-page images")

            // Calculate page breaks
            let horizontalPadding: CGFloat = 48
            let verticalPadding: CGFloat = 48
            let pageSize = CGSize(
                width: viewBounds.width - (horizontalPadding * 2),
                height: viewBounds.height - (verticalPadding * 2)
            )

            let textPageRanges = self.calculatePageRanges(for: content.attributedString, pageSize: pageSize)

            Self.logger.info("Calculated \(textPageRanges.count, privacy: .public) text pages")

            // Update UI on main thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                self.attributedContent = content

                // Build page contents (text pages + image pages interleaved)
                var allPages: [PageContent] = textPageRanges.enumerated().map { index, range in
                    .text(range: range, pageIndex: index)
                }

                // Insert image pages at appropriate positions (reverse to maintain indices)
                for (imagePath, blockId, insertIndex) in content.fullPageImages.reversed() {
                    let imageContent = PageContent.image(path: imagePath, blockId: blockId, imageCache: imageCache)
                    let insertPosition = min(insertIndex, allPages.count)
                    allPages.insert(imageContent, at: insertPosition)
                }

                // Create views
                self.createPageViews(for: allPages, attributedString: content.attributedString)

                // Hide loading overlay
                self.hideLoadingOverlay()

                // Restore position
                if let blockId = initialBlockId {
                    Self.logger.info("Restoring to block: \(blockId, privacy: .public)")
                    self.navigateToBlock(blockId, animated: false)
                }

                self.onPageChanged?(self.currentPageIndex, self.totalPages)
            }
        }
    }

    private enum PageContent {
        case text(range: NSRange, pageIndex: Int)
        case image(path: String, blockId: String, imageCache: [String: Data])
    }

    private func calculatePageRanges(for attributedString: NSAttributedString, pageSize: CGSize) -> [NSRange] {
        guard attributedString.length > 0 else { return [] }

        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = false
        textStorage.addLayoutManager(layoutManager)

        var ranges: [NSRange] = []
        var lastGlyphIndex = 0
        let totalGlyphs = layoutManager.numberOfGlyphs

        while lastGlyphIndex < totalGlyphs {
            let container = NSTextContainer(size: pageSize)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            layoutManager.ensureLayout(for: container)

            let glyphRange = layoutManager.glyphRange(for: container)

            if glyphRange.length == 0 {
                // No more content fits
                break
            }

            let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            ranges.append(characterRange)

            lastGlyphIndex = NSMaxRange(glyphRange)
        }

        return ranges
    }

    private func createPageViews(for pages: [PageContent], attributedString: NSAttributedString) {
        // Clear existing
        pageViews.forEach { $0.removeFromSuperview() }
        pageViews.removeAll()
        pageRanges.removeAll()
        pageBlockIds.removeAll()

        let pageWidth = view.bounds.width
        let pageHeight = view.bounds.height
        let horizontalPadding: CGFloat = 48
        let verticalPadding: CGFloat = 48

        for (index, content) in pages.enumerated() {
            let pageView: UIView

            switch content {
            case .text(let range, _):
                let textView = createTextView(for: range, in: attributedString, padding: UIEdgeInsets(
                    top: verticalPadding,
                    left: horizontalPadding,
                    bottom: verticalPadding,
                    right: horizontalPadding
                ))
                pageView = textView
                pageRanges.append(range)

                // Find block IDs in this range
                let blockIds = findBlockIds(in: range, attributedString: attributedString)
                pageBlockIds.append(blockIds)

            case .image(let path, let blockId, let imageCache):
                let imageView = createImagePageView(path: path, imageCache: imageCache)
                pageView = imageView
                pageRanges.append(NSRange(location: 0, length: 0)) // Placeholder
                pageBlockIds.append([blockId])
            }

            pageView.frame = CGRect(x: CGFloat(index) * pageWidth, y: 0, width: pageWidth, height: pageHeight)
            scrollView.addSubview(pageView)
            pageViews.append(pageView)
        }

        scrollView.contentSize = CGSize(width: pageWidth * CGFloat(pages.count), height: pageHeight)
        totalPages = pages.count

        Self.logger.info("Created \(self.totalPages, privacy: .public) page views")
    }

    private func createTextView(for range: NSRange, in fullText: NSAttributedString, padding: UIEdgeInsets) -> UITextView {
        let pageText = fullText.attributedSubstring(from: range)

        let textView = UITextView()
        textView.attributedText = pageText
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.textContainerInset = padding
        textView.backgroundColor = .systemBackground
        textView.isSelectable = true

        // Add menu for selection
        textView.delegate = self

        return textView
    }

    private func createImagePageView(path: String, imageCache: [String: Data]) -> UIView {
        let container = UIView()
        container.backgroundColor = .systemBackground

        if let data = imageCache[path], let image = UIImage(data: data) {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(imageView)

            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                imageView.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -96),
                imageView.heightAnchor.constraint(lessThanOrEqualTo: container.heightAnchor, constant: -96)
            ])
        }

        return container
    }

    private func findBlockIds(in range: NSRange, attributedString: NSAttributedString) -> [String] {
        var blockIds: [String] = []
        let safeRange = NSRange(
            location: range.location,
            length: min(range.length, attributedString.length - range.location)
        )

        guard safeRange.length > 0 else { return blockIds }

        attributedString.enumerateAttribute(.blockId, in: safeRange, options: []) { value, _, _ in
            if let blockId = value as? String, !blockIds.contains(blockId) {
                blockIds.append(blockId)
            }
        }
        return blockIds
    }

    private func rebuildPagesAsync() {
        Self.logger.info("Rebuilding pages with new font scale: \(self.fontScale, privacy: .public)")

        // Save current position
        let savedBlockId = pageBlockIds.indices.contains(currentPageIndex) ? pageBlockIds[currentPageIndex].first : nil

        // Show loading overlay
        showLoadingOverlay()

        // Clear existing pages
        pageViews.forEach { $0.removeFromSuperview() }
        pageViews.removeAll()
        pageRanges.removeAll()
        pageBlockIds.removeAll()
        attributedContent = nil

        // Rebuild on background queue, update UI on main
        let fontScale = self.fontScale
        let htmlSections = self.htmlSections
        let viewBounds = self.view.bounds

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Build attributed content off main thread
            let imageCache = htmlSections.reduce(into: [String: Data]()) { result, section in
                result.merge(section.imageCache) { _, new in new }
            }

            let converter = HTMLToAttributedStringConverter(imageCache: imageCache, fontScale: fontScale)
            let content = converter.convert(sections: htmlSections)

            // Calculate page ranges off main thread
            let horizontalPadding: CGFloat = 48
            let verticalPadding: CGFloat = 48
            let pageSize = CGSize(
                width: viewBounds.width - (horizontalPadding * 2),
                height: viewBounds.height - (verticalPadding * 2)
            )
            let textPageRanges = self.calculatePageRanges(for: content.attributedString, pageSize: pageSize)

            // Update UI on main thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                self.attributedContent = content
                self.hasBuiltPages = true

                // Build page contents
                var allPages: [PageContent] = textPageRanges.enumerated().map { index, range in
                    .text(range: range, pageIndex: index)
                }

                // Insert image pages
                for (imagePath, blockId, insertIndex) in content.fullPageImages.reversed() {
                    let imageContent = PageContent.image(path: imagePath, blockId: blockId, imageCache: imageCache)
                    let insertPosition = min(insertIndex, allPages.count)
                    allPages.insert(imageContent, at: insertPosition)
                }

                // Create views
                self.createPageViews(for: allPages, attributedString: content.attributedString)

                // Hide loading overlay
                self.hideLoadingOverlay()

                // Restore position
                if let blockId = savedBlockId {
                    self.navigateToBlock(blockId, animated: false)
                }

                self.onPageChanged?(self.currentPageIndex, self.totalPages)
            }
        }
    }

    // MARK: - Loading Overlay

    private func showLoadingOverlay() {
        guard loadingOverlay == nil else { return }

        let overlay = UIView()
        overlay.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
        overlay.translatesAutoresizingMaskIntoConstraints = false

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        let label = UILabel()
        label.text = "Reformatting..."
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        overlay.addSubview(spinner)
        overlay.addSubview(label)
        view.addSubview(overlay)

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -20),

            label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16)
        ])

        loadingOverlay = overlay
    }

    private func hideLoadingOverlay() {
        loadingOverlay?.removeFromSuperview()
        loadingOverlay = nil
    }

    // MARK: - Navigation (PageRenderer Protocol)

    public func navigateToNextPage() {
        let nextPage = min(currentPageIndex + 1, totalPages - 1)
        navigateToPage(nextPage, animated: true)
    }

    public func navigateToPreviousPage() {
        let prevPage = max(currentPageIndex - 1, 0)
        navigateToPage(prevPage, animated: true)
    }

    public func navigateToPage(_ pageIndex: Int, animated: Bool) {
        guard totalPages > 0 else { return }
        let targetPage = max(0, min(pageIndex, totalPages - 1))
        let targetX = CGFloat(targetPage) * view.bounds.width
        scrollView.setContentOffset(CGPoint(x: targetX, y: 0), animated: animated)

        if !animated {
            currentPageIndex = targetPage
            reportPositionChange()
        }
    }

    public func navigateToBlock(_ blockId: String, animated: Bool) {
        // Find page containing this block
        for (index, blockIds) in pageBlockIds.enumerated() {
            if blockIds.contains(blockId) {
                Self.logger.info("Found block \(blockId, privacy: .public) on page \(index, privacy: .public)")
                navigateToPage(index, animated: animated)
                return
            }
        }
        Self.logger.warning("Block \(blockId, privacy: .public) not found in any page")
    }

    public func queryFirstVisibleBlock(completion: @escaping (String?, String?) -> Void) {
        guard currentPageIndex < pageBlockIds.count,
              let firstBlockId = pageBlockIds[currentPageIndex].first else {
            completion(nil, nil)
            return
        }

        // Find spine item ID from attributed content
        var spineItemId: String?
        if let content = attributedContent,
           let range = content.blockRanges[firstBlockId] {
            content.attributedString.enumerateAttribute(.spineItemId, in: range, options: []) { value, _, stop in
                if let id = value as? String {
                    spineItemId = id
                    stop.pointee = true
                }
            }
        }

        completion(firstBlockId, spineItemId)
    }

    // MARK: - Private Helpers

    private func reportPositionChange() {
        onPageChanged?(currentPageIndex, totalPages)

        queryFirstVisibleBlock { [weak self] blockId, spineItemId in
            guard let blockId = blockId else { return }
            self?.onBlockPositionChanged?(blockId, spineItemId)
        }
    }
}

// MARK: - UIScrollViewDelegate

extension NativePageViewController: UIScrollViewDelegate {
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateCurrentPage()
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateCurrentPage()
    }

    private func updateCurrentPage() {
        let pageWidth = view.bounds.width
        guard pageWidth > 0 else { return }

        let newPage = Int(round(scrollView.contentOffset.x / pageWidth))
        if newPage != currentPageIndex && newPage >= 0 && newPage < totalPages {
            currentPageIndex = newPage
            reportPositionChange()
        }
    }
}

// MARK: - UITextViewDelegate

extension NativePageViewController: UITextViewDelegate {
    public func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard range.length > 0 else { return nil }

        let sendToLLMAction = UIAction(title: "Send to LLM", image: UIImage(systemName: "message")) { [weak self] _ in
            self?.handleSendToLLM(from: textView, range: range)
        }

        // Add our action to the suggested actions
        var actions = suggestedActions
        actions.insert(sendToLLMAction, at: 0)

        return UIMenu(children: actions)
    }

    private func handleSendToLLM(from textView: UITextView, range: NSRange) {
        guard let attributedText = textView.attributedText else { return }

        let selectedText = (attributedText.string as NSString).substring(with: range)

        // Get context (text around selection)
        let contextStart = max(0, range.location - 250)
        let contextEnd = min(attributedText.length, NSMaxRange(range) + 250)
        let contextRange = NSRange(location: contextStart, length: contextEnd - contextStart)
        let contextText = (attributedText.string as NSString).substring(with: contextRange)

        // Find block ID at selection
        var blockId: String?
        var spineItemId: String?

        attributedText.enumerateAttribute(.blockId, in: range, options: []) { value, _, stop in
            if let id = value as? String {
                blockId = id
                stop.pointee = true
            }
        }

        attributedText.enumerateAttribute(.spineItemId, in: range, options: []) { value, _, stop in
            if let id = value as? String {
                spineItemId = id
                stop.pointee = true
            }
        }

        let payload = SelectionPayload(
            selectedText: selectedText,
            contextText: contextText,
            range: range,
            bookTitle: bookTitle,
            bookAuthor: bookAuthor,
            chapterTitle: chapterTitle,
            blockId: blockId,
            spineItemId: spineItemId
        )

        onSendToLLM?(payload)
    }
}
