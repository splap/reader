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
    public var onSpineChanged: ((Int, Int) -> Void)?
    public var onSendToLLM: ((SelectionPayload) -> Void)?
    public var onRenderReady: (() -> Void)?
    public var onCFIPositionChanged: ((String, Int) -> Void)?

    // MARK: - Private Properties

    private let htmlSections: [HTMLSection]
    private let bookId: String
    private let bookTitle: String?
    private let bookAuthor: String?
    private let chapterTitle: String?

    private var scrollView: UIScrollView!
    private var pageViews: [UIView] = []
    private var currentPageIndex: Int = 0
    private var totalPages: Int = 0

    private var attributedContent: AttributedContent?
    private var pageRanges: [NSRange] = []
    private var pageBlockIds: [[String]] = []

    private var hasBuiltPages = false
    private var loadingOverlay: UIView?

    /// Cached layout for the current chapter
    private var cachedLayout: ChapterLayout?

    /// Layout service for cache operations
    private let layoutService = PageLayoutService.shared

    // MARK: - Initialization

    public init(
        htmlSections: [HTMLSection],
        bookId: String,
        bookTitle: String? = nil,
        bookAuthor: String? = nil,
        chapterTitle: String? = nil,
        fontScale: CGFloat = 1.4
    ) {
        self.htmlSections = htmlSections
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.chapterTitle = chapterTitle
        self.fontScale = fontScale
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
        scrollView.alwaysBounceHorizontal = true
        scrollView.isDirectionalLockEnabled = true

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

    /// Select which sections to load
    /// NOTE: Section-based loading was disabled because it broke pagination -
    /// totalPages was calculated from only loaded content, making books appear
    /// to have far fewer pages than they actually do (e.g., Frankenstein showing 3 pages).
    /// If re-enabling, must estimate total pages from ALL sections, not just loaded ones.
    private func selectSectionsToLoad() -> [Int] {
        // Load all sections to ensure correct page count
        return Array(0..<htmlSections.count)
    }

    private func buildPages() {
        Self.logger.info("Building pages for native renderer")

        // Show loading overlay for initial build
        showLoadingOverlay()

        let fontScale = self.fontScale
        let viewBounds = self.view.bounds
        let bookId = self.bookId

        // PERF OPTIMIZATION: Only load sections around the initial position
        let sectionsToLoad = selectSectionsToLoad()
        let selectedSections = sectionsToLoad.map { htmlSections[$0] }
        Self.logger.info("PERF: Loading \(sectionsToLoad.count) of \(self.htmlSections.count) sections for native renderer")

        // Get spine item ID from first selected section
        let spineItemId = selectedSections.first?.spineItemId ?? "unknown"

        // Build layout config
        let horizontalPadding: CGFloat = 48
        let verticalPadding: CGFloat = 48
        let config = LayoutConfig(
            fontScale: fontScale,
            pageWidth: viewBounds.width,
            pageHeight: viewBounds.height,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        )

        Task {
            let startTime = CFAbsoluteTimeGetCurrent()

            // Check cache first
            let cachedLayout = await layoutService.getCachedLayout(
                bookId: bookId,
                spineItemId: spineItemId,
                config: config
            )

            // Build attributed content from selected sections only
            let imageCache = selectedSections.reduce(into: [String: Data]()) { result, section in
                result.merge(section.imageCache) { _, new in new }
            }

            let converter = HTMLToAttributedStringConverter(imageCache: imageCache, fontScale: fontScale)
            let conversionStart = CFAbsoluteTimeGetCurrent()
            let content = converter.convert(sections: selectedSections)
            let conversionTime = CFAbsoluteTimeGetCurrent() - conversionStart

            Self.logger.info("PERF: HTML conversion took \(String(format: "%.3f", conversionTime))s for \(content.blockOrder.count) blocks (\(selectedSections.count) sections)")

            let textPageRanges: [NSRange]

            if let cached = cachedLayout {
                // CACHE HIT - use cached page ranges directly
                Self.logger.info("Cache hit: using cached layout with \(cached.totalPages) pages")
                textPageRanges = cached.pageOffsets.map { $0.characterRange }

                let totalTime = CFAbsoluteTimeGetCurrent() - startTime
                Self.logger.info("TIMING: Cache hit render took \(totalTime)s total")

                await MainActor.run {
                    self.cachedLayout = cached
                }
            } else {
                // CACHE MISS - calculate page ranges
                Self.logger.info("Cache miss: calculating layout for \(spineItemId)")

                let pageSize = config.contentSize
                let layoutStart = CFAbsoluteTimeGetCurrent()
                let (ranges, pageOffsets) = self.calculatePageRangesWithOffsets(
                    for: content.attributedString,
                    pageSize: pageSize,
                    attributedContent: content
                )
                textPageRanges = ranges
                let layoutTime = CFAbsoluteTimeGetCurrent() - layoutStart

                let totalTime = CFAbsoluteTimeGetCurrent() - startTime
                Self.logger.info("TIMING: Page layout took \(layoutTime)s for \(ranges.count) pages. Total: \(totalTime)s")

                // Save to cache
                let layout = ChapterLayout(
                    bookId: bookId,
                    spineItemId: spineItemId,
                    config: config,
                    pageOffsets: pageOffsets
                )
                await layoutService.saveLayout(layout)

                await MainActor.run {
                    self.cachedLayout = layout
                }
            }

            // Update UI on main thread
            await MainActor.run {
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

                self.onPageChanged?(self.currentPageIndex, self.totalPages)
                self.onRenderReady?()
            }
        }
    }

    private enum PageContent {
        case text(range: NSRange, pageIndex: Int)
        case image(path: String, blockId: String, imageCache: [String: Data])
    }

    private func calculatePageRanges(for attributedString: NSAttributedString, pageSize: CGSize) -> [NSRange] {
        let (ranges, _) = calculatePageRangesWithOffsets(for: attributedString, pageSize: pageSize, attributedContent: nil)
        return ranges
    }

    /// Calculates page ranges and captures block boundary information for caching
    private func calculatePageRangesWithOffsets(
        for attributedString: NSAttributedString,
        pageSize: CGSize,
        attributedContent: AttributedContent?
    ) -> ([NSRange], [PageOffset]) {
        guard attributedString.length > 0 else { return ([], []) }

        // Get section break locations for forcing page breaks
        let sectionBreaks = Set(attributedContent?.sectionBreakLocations ?? [])

        var ranges: [NSRange] = []
        var pageOffsets: [PageOffset] = []
        var currentStart = 0
        let totalLength = attributedString.length

        var pageCount = 0
        var batchStart = CFAbsoluteTimeGetCurrent()

        while currentStart < totalLength {
            // Determine end boundary for this segment (either next section break or end)
            var segmentEnd = totalLength
            for breakLoc in sectionBreaks.sorted() {
                if breakLoc > currentStart {
                    segmentEnd = breakLoc
                    break
                }
            }

            // Calculate pages for this segment
            let segmentRange = NSRange(location: currentStart, length: segmentEnd - currentStart)
            let segmentString = attributedString.attributedSubstring(from: segmentRange)

            let textStorage = NSTextStorage(attributedString: segmentString)
            let layoutManager = NSLayoutManager()
            layoutManager.allowsNonContiguousLayout = true
            textStorage.addLayoutManager(layoutManager)

            var segmentOffset = 0

            while segmentOffset < segmentString.length {
                let container = NSTextContainer(size: pageSize)
                container.lineFragmentPadding = 0
                layoutManager.addTextContainer(container)
                layoutManager.ensureLayout(for: container)

                let glyphRange = layoutManager.glyphRange(for: container)
                if glyphRange.length == 0 {
                    break
                }

                let localCharRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

                // Convert to global character range
                let globalRange = NSRange(
                    location: currentStart + localCharRange.location,
                    length: localCharRange.length
                )
                ranges.append(globalRange)

                // Capture block boundary information
                if let content = attributedContent {
                    let offset = createPageOffset(
                        pageIndex: pageCount,
                        characterRange: globalRange,
                        attributedString: attributedString,
                        blockRanges: content.blockRanges
                    )
                    pageOffsets.append(offset)
                }

                segmentOffset = NSMaxRange(localCharRange)
                pageCount += 1

                // Log every 50 pages
                if pageCount % 50 == 0 {
                    let batchTime = CFAbsoluteTimeGetCurrent() - batchStart
                    let msPerPage = (batchTime / 50.0) * 1000
                    Self.logger.debug("PAGE_TIMING: Pages \(pageCount - 49)-\(pageCount), \(msPerPage)ms/page")
                    batchStart = CFAbsoluteTimeGetCurrent()
                }
            }

            currentStart = segmentEnd
        }

        return (ranges, pageOffsets)
    }

    /// Creates a PageOffset with block boundary information
    private func createPageOffset(
        pageIndex: Int,
        characterRange: NSRange,
        attributedString: NSAttributedString,
        blockRanges: [String: NSRange]
    ) -> PageOffset {
        var firstBlockId = "unknown"
        var firstBlockCharOffset = 0
        var lastBlockId = "unknown"
        var lastBlockCharOffset = 0

        let pageStart = characterRange.location
        let pageEnd = NSMaxRange(characterRange)

        // Find first block on this page
        for (blockId, blockRange) in blockRanges {
            let blockStart = blockRange.location
            let blockEnd = NSMaxRange(blockRange)

            // Check if this block contains the page start
            if blockStart <= pageStart && blockEnd > pageStart {
                firstBlockId = blockId
                firstBlockCharOffset = pageStart - blockStart
            }

            // Check if this block contains the page end
            if blockStart < pageEnd && blockEnd >= pageEnd {
                lastBlockId = blockId
                lastBlockCharOffset = pageEnd - blockStart
            }
        }

        // If we didn't find specific blocks, try to find any block that overlaps
        if firstBlockId == "unknown" || lastBlockId == "unknown" {
            for (blockId, blockRange) in blockRanges {
                let blockStart = blockRange.location
                let blockEnd = NSMaxRange(blockRange)

                // Check for any overlap with this page
                if blockStart < pageEnd && blockEnd > pageStart {
                    if firstBlockId == "unknown" {
                        firstBlockId = blockId
                        firstBlockCharOffset = max(0, pageStart - blockStart)
                    }
                    lastBlockId = blockId
                    lastBlockCharOffset = min(blockRange.length, pageEnd - blockStart)
                }
            }
        }

        return PageOffset(
            pageIndex: pageIndex,
            firstBlockId: firstBlockId,
            firstBlockCharOffset: firstBlockCharOffset,
            lastBlockId: lastBlockId,
            lastBlockCharOffset: lastBlockCharOffset,
            characterRange: characterRange
        )
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

        Self.logger.info("Created \(self.totalPages) page views")
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

        // Try to resolve the image path with various formats
        if let data = resolveImageData(path: path, imageCache: imageCache),
           let image = UIImage(data: data) {
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

    /// Resolves an image path to data, trying various path formats and extensions
    private func resolveImageData(path: String, imageCache: [String: Data]) -> Data? {
        // Try exact path first
        if let data = imageCache[path] {
            return data
        }

        // Try just the filename
        let filename = (path as NSString).lastPathComponent
        if let data = imageCache[filename] {
            return data
        }

        // Try without leading ../ or ./
        var cleanPath = path
        while cleanPath.hasPrefix("../") {
            cleanPath = String(cleanPath.dropFirst(3))
        }
        if cleanPath.hasPrefix("./") {
            cleanPath = String(cleanPath.dropFirst(2))
        }
        if let data = imageCache[cleanPath] {
            return data
        }

        // Try with common extension variations (.jpg <-> .jpeg)
        let extensions = [".jpg", ".jpeg", ".png", ".gif"]
        let baseName = (filename as NSString).deletingPathExtension

        for ext in extensions {
            let altFilename = baseName + ext
            if let data = imageCache[altFilename] {
                return data
            }
        }

        return nil
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
        Self.logger.info("Rebuilding pages with new font scale: \(self.fontScale)")

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

        // Rebuild using cache-aware approach with section-based loading
        let fontScale = self.fontScale
        let viewBounds = self.view.bounds
        let bookId = self.bookId

        // Use section-based loading for rebuilds too
        let sectionsToLoad = selectSectionsToLoad()
        let selectedSections = sectionsToLoad.map { htmlSections[$0] }
        Self.logger.info("PERF (rebuild): Loading \(sectionsToLoad.count) of \(self.htmlSections.count) sections")

        let spineItemId = selectedSections.first?.spineItemId ?? "unknown"

        let horizontalPadding: CGFloat = 48
        let verticalPadding: CGFloat = 48
        let config = LayoutConfig(
            fontScale: fontScale,
            pageWidth: viewBounds.width,
            pageHeight: viewBounds.height,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        )

        Task {
            let startTime = CFAbsoluteTimeGetCurrent()

            // Check cache first
            let cachedLayout = await layoutService.getCachedLayout(
                bookId: bookId,
                spineItemId: spineItemId,
                config: config
            )

            // Build attributed content from selected sections
            let imageCache = selectedSections.reduce(into: [String: Data]()) { result, section in
                result.merge(section.imageCache) { _, new in new }
            }

            let converter = HTMLToAttributedStringConverter(imageCache: imageCache, fontScale: fontScale)
            let conversionStart = CFAbsoluteTimeGetCurrent()
            let content = converter.convert(sections: selectedSections)
            let conversionTime = CFAbsoluteTimeGetCurrent() - conversionStart

            Self.logger.info("PERF (rebuild): HTML conversion took \(String(format: "%.3f", conversionTime))s for \(content.blockOrder.count) blocks")

            let textPageRanges: [NSRange]

            if let cached = cachedLayout {
                // CACHE HIT
                Self.logger.info("Cache hit (rebuild): using cached layout with \(cached.totalPages) pages")
                textPageRanges = cached.pageOffsets.map { $0.characterRange }

                let totalTime = CFAbsoluteTimeGetCurrent() - startTime
                Self.logger.info("TIMING (rebuild): Cache hit took \(totalTime)s total")

                await MainActor.run {
                    self.cachedLayout = cached
                }
            } else {
                // CACHE MISS - calculate
                Self.logger.info("Cache miss (rebuild): calculating layout")

                let pageSize = config.contentSize
                let layoutStart = CFAbsoluteTimeGetCurrent()
                let (ranges, pageOffsets) = self.calculatePageRangesWithOffsets(
                    for: content.attributedString,
                    pageSize: pageSize,
                    attributedContent: content
                )
                textPageRanges = ranges
                let layoutTime = CFAbsoluteTimeGetCurrent() - layoutStart

                let totalTime = CFAbsoluteTimeGetCurrent() - startTime
                Self.logger.info("TIMING (rebuild): Page layout took \(layoutTime)s for \(ranges.count) pages. Total: \(totalTime)s")

                // Save to cache
                let layout = ChapterLayout(
                    bookId: bookId,
                    spineItemId: spineItemId,
                    config: config,
                    pageOffsets: pageOffsets
                )
                await layoutService.saveLayout(layout)

                await MainActor.run {
                    self.cachedLayout = layout
                }
            }

            // Update UI on main thread
            await MainActor.run {
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
                Self.logger.info("Found block \(blockId) on page \(index)")
                navigateToPage(index, animated: animated)
                return
            }
        }
        Self.logger.warning("Block \(blockId) not found in any page")
    }

    public func navigateToSpineItem(_ spineItemId: String, animated: Bool) {
        guard let content = attributedContent else {
            Self.logger.warning("Cannot navigate to spine item - no content loaded")
            return
        }

        // Find the first block that belongs to this spine item
        for blockId in content.blockOrder {
            guard let range = content.blockRanges[blockId] else { continue }

            // Check if this block belongs to the target spine item
            var foundSpineItemId: String?
            content.attributedString.enumerateAttribute(.spineItemId, in: range, options: []) { value, _, stop in
                if let id = value as? String {
                    foundSpineItemId = id
                    stop.pointee = true
                }
            }

            if foundSpineItemId == spineItemId {
                // Found the first block of this spine item, navigate to it
                Self.logger.info("Found spine item \(spineItemId) starting at block \(blockId)")
                navigateToBlock(blockId, animated: animated)
                return
            }
        }

        Self.logger.warning("Spine item \(spineItemId) not found in content")
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
