import Foundation
import OSLog

public enum BookLibraryError: LocalizedError {
    case fileNotFound
    case invalidEPUB
    case copyFailed(Error)
    case metadataExtractionFailed
    case bookNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "The selected file could not be found. If the file is in iCloud, make sure it's downloaded to this device."
        case .invalidEPUB:
            return "The file is not a valid EPUB document."
        case let .copyFailed(error):
            let nsError = error as NSError
            return """
            Failed to import book: \(error.localizedDescription)

            Error Domain: \(nsError.domain)
            Error Code: \(nsError.code)

            If this file is in iCloud Drive, try moving it to "On My iPad" first.
            """
        case .metadataExtractionFailed:
            return "Could not read book information."
        case let .bookNotFound(id):
            return "Book with ID \(id) not found."
        }
    }
}

public protocol BookLibraryStorage {
    func loadBooks() -> [Book]
    func saveBooks(_ books: [Book])
}

public final class UserDefaultsBookStorage: BookLibraryStorage {
    private let defaults: UserDefaults
    private let key = "reader.library.books"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadBooks() -> [Book] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        do {
            let books = try JSONDecoder().decode([Book].self, from: data)
            return books
        } catch {
            Log.logger(category: "library")
                .error("Failed to decode books: \(error.localizedDescription)")
            return []
        }
    }

    public func saveBooks(_ books: [Book]) {
        do {
            let data = try JSONEncoder().encode(books)
            defaults.set(data, forKey: key)
        } catch {
            Log.logger(category: "library")
                .error("Failed to encode books: \(error.localizedDescription)")
        }
    }
}

public final class BookLibraryService {
    private static let logger = Log.logger(category: "library")

    public static let shared = BookLibraryService()

    private let fileManager: FileManager
    private let booksDirectory: URL
    private let storage: BookLibraryStorage

    public init(
        fileManager: FileManager = .default,
        storage: BookLibraryStorage = UserDefaultsBookStorage()
    ) {
        self.fileManager = fileManager
        self.storage = storage

        // Get Application Support directory
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        booksDirectory = appSupport.appendingPathComponent("Books")

        // Create Books directory if it doesn't exist
        try? fileManager.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Import Operations

    public func importBook(from sourceURL: URL, startAccessing: Bool = false) throws -> Book {
        Self.logger.debug("Importing book from: \(sourceURL.path) (scheme: \(sourceURL.scheme ?? "nil"), security scope: \(startAccessing))")

        // Only use security-scoped resource access if the file is outside our sandbox
        // Files in tmp/Inbox are already accessible
        let needsSecurityScope = startAccessing && !sourceURL.path.contains("/tmp/")
        var didStartAccessing = false

        if needsSecurityScope {
            didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
            if !didStartAccessing {
                Self.logger.error("Failed to start accessing security scoped resource")
                throw BookLibraryError.fileNotFound
            }
        }

        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        // Check if file exists
        let fileExists = fileManager.fileExists(atPath: sourceURL.path)
        Self.logger.debug("File exists check: \(fileExists)")

        if !fileExists {
            Self.logger.error("File does not exist at path: \(sourceURL.path)")
            throw BookLibraryError.fileNotFound
        }

        // Copy file to library
        Self.logger.debug("Copying book to library")

        let (filePath, _) = try copyToLibrary(from: sourceURL)

        Self.logger.debug("Copy complete: \(filePath)")

        // Extract metadata
        let fileURL = booksDirectory.appendingPathComponent(filePath)
        let (title, author) = extractMetadata(from: fileURL)

        // Create book record
        let book = Book(
            title: title,
            author: author,
            filePath: filePath,
            importDate: Date(),
            lastOpenedDate: nil
        )

        // Save to storage
        var books = getAllBooks()
        books.append(book)
        storage.saveBooks(books)

        Self.logger.info("Imported book: \(title) (\(book.id))")

        // Index the book for search (background, non-blocking)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.indexBookSync(book)
        }

        return book
    }

    /// Synchronous indexing for background dispatch
    private func indexBookSync(_ book: Book) {
        Self.logger.info("Indexing book: \(book.title)")

        let fileURL = getFileURL(for: book)
        let loader = EPUBLoader()
        let chapter: Chapter
        do {
            chapter = try loader.loadChapter(from: fileURL, maxSections: .max)
        } catch {
            Self.logger.error("Index failed - EPUB load error: \(error)")
            return
        }

        let bookId = book.id.uuidString
        let chapters = [chapter]
        let chunks = Chunker.chunkBook(chapters: chapters, bookId: bookId)
        Self.logger.debug("Created \(chunks.count) chunks from \(chapter.allBlocks.count) blocks")

        let group = DispatchGroup()
        group.enter()
        Task {
            // Build vector index (semantic search) - also stores chunks for text retrieval
            await self.buildVectorIndex(bookId: bookId, chunks: chunks)

            // Build concept map (entities, themes, events)
            await self.buildConceptMap(bookId: bookId, chapters: chapters)

            group.leave()
        }
        group.wait()
    }

    /// Builds vector index for semantic search
    private func buildVectorIndex(bookId: String, chunks: [Chunk]) async {
        do {
            let embeddingService = EmbeddingService.shared

            // Check if embedding model is available
            let modelAvailable = try await embeddingService.loadModel()
            guard modelAvailable else {
                Self.logger.info("Embedding model not available, skipping vector index")
                return
            }

            // Generate embeddings
            let texts = chunks.map(\.text)
            let embeddings = try await embeddingService.embedBatch(texts: texts)

            // Build HNSW index
            try await VectorStore.shared.buildIndex(bookId: bookId, chunks: chunks, embeddings: embeddings)

            Self.logger.info("Built vector index with \(embeddings.count) embeddings")
        } catch {
            Self.logger.error("Vector index build failed: \(error.localizedDescription)")
        }
    }

    /// Builds concept map for routing and discovery
    private func buildConceptMap(bookId: String, chapters: [Chapter]) async {
        do {
            // Build the concept map
            let conceptMap = ConceptMapBuilder.build(
                bookId: bookId,
                chapters: chapters,
                chunkEmbeddings: nil // TODO: Pass chunk embeddings when available
            )

            // Save to persistent storage
            try await ConceptMapStore.shared.save(map: conceptMap)

            Self.logger.info("Built concept map: \(conceptMap.entities.count) entities, \(conceptMap.themes.count) themes")
        } catch {
            Self.logger.error("Concept map build failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Library Operations

    public func getAllBooks() -> [Book] {
        let books = storage.loadBooks()
        // Sort by lastOpenedDate (most recent first), then by importDate
        return books.sorted { lhs, rhs in
            if let lhsDate = lhs.lastOpenedDate, let rhsDate = rhs.lastOpenedDate {
                lhsDate > rhsDate
            } else if lhs.lastOpenedDate != nil {
                true
            } else if rhs.lastOpenedDate != nil {
                false
            } else {
                lhs.importDate > rhs.importDate
            }
        }
    }

    public func getBook(id: UUID) -> Book? {
        storage.loadBooks().first { $0.id == id }
    }

    public func deleteBook(id: UUID) throws {
        var books = storage.loadBooks()
        guard let index = books.firstIndex(where: { $0.id == id }) else {
            throw BookLibraryError.bookNotFound(id)
        }

        let book = books[index]
        let fileURL = booksDirectory.appendingPathComponent(book.filePath)

        // Delete the book directory
        let bookDir = fileURL.deletingLastPathComponent()
        try fileManager.removeItem(at: bookDir)

        // Remove from storage
        books.remove(at: index)
        storage.saveBooks(books)

        // Remove from all indices
        Task {
            let bookId = id.uuidString

            // Delete vector index (includes stored chunks)
            do {
                try await VectorStore.shared.deleteBook(bookId: bookId)
            } catch {
                Self.logger.error("Failed to delete book from vector index: \(error.localizedDescription)")
            }

            // Delete concept map
            do {
                try await ConceptMapStore.shared.delete(bookId: bookId)
            } catch {
                Self.logger.error("Failed to delete book concept map: \(error.localizedDescription)")
            }
        }

        Self.logger.info("Deleted book: \(book.title) (\(id))")
    }

    public func updateLastOpened(bookId: UUID) {
        var books = storage.loadBooks()
        guard let index = books.firstIndex(where: { $0.id == bookId }) else {
            return
        }

        books[index].lastOpenedDate = Date()
        storage.saveBooks(books)

        // Also save to UserDefaults for quick access on app launch
        UserDefaults.standard.set(bookId.uuidString, forKey: "reader.lastOpenedBookId")
    }

    // MARK: - File Operations

    public func getFileURL(for book: Book) -> URL {
        booksDirectory.appendingPathComponent(book.filePath)
    }

    private func copyToLibrary(from sourceURL: URL) throws -> (path: String, size: Int64) {
        let uuid = UUID()
        let bookDir = booksDirectory.appendingPathComponent(uuid.uuidString)
        let destURL = bookDir.appendingPathComponent("book.epub")

        Self.logger.debug("Creating book directory: \(uuid.uuidString)")
        try fileManager.createDirectory(at: bookDir, withIntermediateDirectories: true)

        Self.logger.debug("Copying file from \(sourceURL.lastPathComponent) to library")

        var coordinatorError: NSError?
        var copyError: Error?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: sourceURL, options: .withoutChanges, error: &coordinatorError) { url in
            Self.logger.debug("File coordinator provided URL: \(url.lastPathComponent)")

            do {
                try self.fileManager.copyItem(at: url, to: destURL)
                Self.logger.debug("File copy completed successfully")
            } catch {
                Self.logger.error("Copy failed: \(error.localizedDescription)")
                copyError = error
            }
        }

        if let error = coordinatorError {
            Self.logger.error("File coordinator error: \(error.localizedDescription)")
            throw BookLibraryError.copyFailed(error)
        }

        if let error = copyError {
            Self.logger.error("Copy operation failed")
            throw BookLibraryError.copyFailed(error)
        }

        let attributes = try fileManager.attributesOfItem(atPath: destURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        Self.logger.debug("File copied successfully, size: \(fileSize) bytes")

        return (path: "\(uuid.uuidString)/book.epub", size: fileSize)
    }

    private func extractMetadata(from epubURL: URL) -> (title: String, author: String?) {
        do {
            let loader = EPUBLoader()
            let metadata = try loader.loadSpineMetadata(from: epubURL)
            return (
                title: metadata.title ?? epubURL.deletingPathExtension().lastPathComponent,
                author: metadata.author
            )
        } catch {
            Self.logger.error("Failed to extract metadata: \(error.localizedDescription)")
            return (title: epubURL.deletingPathExtension().lastPathComponent, author: nil)
        }
    }

    // MARK: - Indexing

    /// Progress information for book indexing
    public struct IndexingProgress {
        public let stage: IndexingStage
        public let message: String

        public enum IndexingStage: String {
            case loading = "Loading book"
            case chunking = "Analyzing text"
            case lexical = "Building search index"
            case embeddings = "Generating embeddings"
            case vectorIndex = "Building semantic index"
            case conceptMap = "Extracting concepts"
            case complete = "Complete"
            case failed = "Failed"
        }
    }

    /// Lexical search is always available (in-memory), no index needed
    public func isLexicalIndexed(bookId _: String) async -> Bool {
        true
    }

    /// Checks if a book has a vector index for semantic search
    public func isVectorIndexed(bookId: String) async -> Bool {
        await VectorStore.shared.isIndexed(bookId: bookId)
    }

    /// Checks if a book has all required indexes (just vector index now)
    public func isFullyIndexed(bookId: String) async -> Bool {
        await isVectorIndexed(bookId: bookId)
    }

    /// Indexes a book with progress updates. Call this when opening a book that hasn't been indexed.
    /// - Parameters:
    ///   - book: The book to index
    ///   - progressHandler: Called with progress updates during indexing
    /// - Returns: true if indexing succeeded, false otherwise
    @MainActor
    public func ensureIndexed(
        book: Book,
        progressHandler: @escaping (IndexingProgress) -> Void
    ) async -> Bool {
        let bookId = book.id.uuidString

        // Check if vector index exists (lexical search is always in-memory)
        let hasVector = await isVectorIndexed(bookId: bookId)

        if hasVector {
            Self.logger.info("Book already indexed: \(book.title)")
            progressHandler(IndexingProgress(stage: .complete, message: "Already indexed"))
            return true
        }

        Self.logger.info("Starting indexing for book: \(book.title)")

        // Load the book
        progressHandler(IndexingProgress(stage: .loading, message: "Loading book content..."))

        let fileURL = getFileURL(for: book)
        let loader = EPUBLoader()
        let chapter: Chapter
        do {
            chapter = try loader.loadChapter(from: fileURL, maxSections: .max)
            Self.logger.info("Loaded \(chapter.allBlocks.count) blocks from book")
        } catch {
            Self.logger.error("Index failed - EPUB load error: \(error)")
            progressHandler(IndexingProgress(stage: .failed, message: "Failed to load book: \(error.localizedDescription)"))
            return false
        }

        // Chunk the book
        progressHandler(IndexingProgress(stage: .chunking, message: "Analyzing text structure..."))

        let chapters = [chapter]
        let chunks = Chunker.chunkBook(chapters: chapters, bookId: bookId)
        Self.logger.info("Created \(chunks.count) chunks from \(chapter.allBlocks.count) blocks")

        // Build vector index (includes chunk storage for text retrieval)
        if !hasVector {
            progressHandler(IndexingProgress(stage: .embeddings, message: "Generating embeddings..."))

            do {
                let embeddingService = EmbeddingService.shared

                // Check if embedding model is available
                let modelAvailable = try await embeddingService.loadModel()
                if !modelAvailable {
                    Self.logger.warning("Embedding model not available, skipping vector index")
                    // This is not a fatal error - lexical search still works
                } else {
                    // Generate embeddings with progress logging
                    let texts = chunks.map(\.text)
                    Self.logger.info("Generating embeddings for \(texts.count) chunks...")

                    let embeddings = try await embeddingService.embedBatch(texts: texts)

                    progressHandler(IndexingProgress(stage: .vectorIndex, message: "Building semantic index..."))

                    // Build HNSW index
                    try await VectorStore.shared.buildIndex(bookId: bookId, chunks: chunks, embeddings: embeddings)

                    Self.logger.info("Vector index complete: \(embeddings.count) embeddings indexed")
                }
            } catch {
                Self.logger.error("Vector index build failed: \(error.localizedDescription)")
                // Don't fail completely - lexical search still works
            }
        }

        // Mark indexing complete - book can be opened now
        progressHandler(IndexingProgress(stage: .complete, message: "Indexing complete"))
        Self.logger.info("Indexing complete for book: \(book.title)")

        // Build concept map in background (doesn't block book opening)
        // This is slow (~70s for large books) due to co-occurrence matrix calculation
        Task.detached(priority: .background) {
            Self.logger.info("Starting background concept map build for: \(book.title)")
            do {
                let conceptMap = ConceptMapBuilder.build(
                    bookId: bookId,
                    chapters: chapters,
                    chunkEmbeddings: nil
                )
                try await ConceptMapStore.shared.save(map: conceptMap)
                Self.logger.info("Background concept map complete: \(conceptMap.entities.count) entities, \(conceptMap.themes.count) themes")
            } catch {
                Self.logger.error("Background concept map build failed: \(error.localizedDescription)")
            }
        }

        return true
    }

    /// Kicks off background indexing if the book isn't already indexed.
    /// Returns immediately - does not block the caller.
    /// - Parameter book: The book to index
    public func ensureIndexedInBackground(book: Book) {
        let bookId = book.id.uuidString

        // Check if already indexed (quick synchronous check)
        let indexPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.splap.reader/vectors/\(bookId).usearch")

        if FileManager.default.fileExists(atPath: indexPath.path) {
            Self.logger.debug("Book already indexed, skipping: \(book.title)")
            return
        }

        Self.logger.info("Starting background indexing for: \(book.title)")

        // Run indexing in background
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.indexBookSync(book)
        }
    }

    /// Indexes a specific book by title (for testing/debugging)
    /// - Parameter titleContains: Substring to match in book title
    public func indexBookByTitle(_ titleContains: String) {
        guard let book = getAllBooks().first(where: { $0.title.lowercased().contains(titleContains.lowercased()) }) else {
            Self.logger.warning("No book found matching '\(titleContains)'")
            return
        }

        Self.logger.info("Indexing book: \(book.title)")

        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.indexBookSync(book)
        }
    }

    // MARK: - Test Books

    /// Scans the Documents/TestBooks directory and imports any new books found
    public func scanTestBooks() {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let testBooksURL = documentsURL.appendingPathComponent("TestBooks")

        guard fileManager.fileExists(atPath: testBooksURL.path) else {
            Self.logger.info("No TestBooks directory found")
            return
        }

        do {
            let contents = try fileManager.contentsOfDirectory(at: testBooksURL, includingPropertiesForKeys: nil)
            let epubFiles = contents.filter { $0.pathExtension.lowercased() == "epub" }

            Self.logger.debug("Found \(epubFiles.count) epub files in TestBooks")

            // Get existing book titles to deduplicate (survives UserDefaults clearing)
            let existingBooks = getAllBooks()
            let existingTitles = Set(existingBooks.map { $0.title.lowercased() })
            Self.logger.debug("Library has \(existingBooks.count) existing books")

            var newImports = 0
            for epubURL in epubFiles {
                let filename = epubURL.lastPathComponent

                // Extract title to check for duplicates
                let (title, _) = extractMetadata(from: epubURL)
                if existingTitles.contains(title.lowercased()) {
                    Self.logger.debug("Skipping duplicate book: \(title)")
                    continue
                }

                do {
                    let book = try importBook(from: epubURL, startAccessing: false)
                    Self.logger.info("Imported test book: \(book.title)")
                    newImports += 1
                } catch {
                    Self.logger.error("Failed to import \(filename): \(error.localizedDescription)")
                }
            }

            if newImports > 0 {
                Self.logger.info("Imported \(newImports) new test books")
            }
        } catch {
            Self.logger.error("Failed to scan TestBooks: \(error.localizedDescription)")
        }
    }
}
