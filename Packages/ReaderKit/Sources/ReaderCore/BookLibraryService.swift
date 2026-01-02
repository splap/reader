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
        case .copyFailed(let error):
            let nsError = error as NSError
            return """
            Failed to import book: \(error.localizedDescription)

            Error Domain: \(nsError.domain)
            Error Code: \(nsError.code)

            If this file is in iCloud Drive, try moving it to "On My iPad" first.
            """
        case .metadataExtractionFailed:
            return "Could not read book information."
        case .bookNotFound(let id):
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
            Logger(subsystem: "com.example.reader", category: "library")
                .error("Failed to decode books: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func saveBooks(_ books: [Book]) {
        do {
            let data = try JSONEncoder().encode(books)
            defaults.set(data, forKey: key)
        } catch {
            Logger(subsystem: "com.example.reader", category: "library")
                .error("Failed to encode books: \(error.localizedDescription, privacy: .public)")
        }
    }
}

public final class BookLibraryService {
    private static let logger = Logger(subsystem: "com.splap.reader", category: "library")

    public static let shared = BookLibraryService()

    private let fileManager: FileManager
    private let booksDirectory: URL
    private let storage: BookLibraryStorage
    private let debugLogURL: URL

    public init(
        fileManager: FileManager = .default,
        storage: BookLibraryStorage = UserDefaultsBookStorage()
    ) {
        self.fileManager = fileManager
        self.storage = storage

        // Get Application Support directory
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.booksDirectory = appSupport.appendingPathComponent("Books")
        self.debugLogURL = appSupport.appendingPathComponent("import-debug.log")

        // Create Books directory if it doesn't exist
        try? fileManager.createDirectory(at: booksDirectory, withIntermediateDirectories: true)

        // Write initial log entry
        writeDebugLog("=== BookLibraryService initialized ===")
    }

    private func writeDebugLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = "[\(timestamp)] \(message)\n"
        if let data = logEntry.data(using: .utf8) {
            if fileManager.fileExists(atPath: debugLogURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: debugLogURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try? fileHandle.close()
                }
            } else {
                try? data.write(to: debugLogURL)
            }
        }
    }

    // MARK: - Import Operations

    public func importBook(from sourceURL: URL, startAccessing: Bool = false) throws -> Book {
        let logMsg = """
        📚 [IMPORT] Attempting to import book
        Source URL: \(sourceURL)
        Source URL path: \(sourceURL.path)
        Source URL scheme: \(sourceURL.scheme ?? "nil")
        Start accessing: \(startAccessing)
        """
        NSLog("%@", logMsg)
        writeDebugLog(logMsg)
        Self.logger.info("Attempting to import book from: \(sourceURL.path, privacy: .public)")
        Self.logger.info("Source URL scheme: \(sourceURL.scheme ?? "nil", privacy: .public)")
        Self.logger.info("Start accessing: \(startAccessing, privacy: .public)")

        // Only use security-scoped resource access if the file is outside our sandbox
        // Files in tmp/Inbox are already accessible
        let needsSecurityScope = startAccessing && !sourceURL.path.contains("/tmp/")
        var didStartAccessing = false

        if needsSecurityScope {
            didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
            if !didStartAccessing {
                let errMsg = "❌ Failed to start accessing security scoped resource"
                writeDebugLog(errMsg)
                NSLog("📚 [IMPORT] %@", errMsg)
                Self.logger.error("Failed to start accessing security scoped resource")
                throw BookLibraryError.fileNotFound
            }
        } else {
            writeDebugLog("File is in sandbox, no security scope needed")
        }

        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        // Check if file exists
        let fileExists = fileManager.fileExists(atPath: sourceURL.path)
        writeDebugLog("File exists at path: \(fileExists)")
        NSLog("📚 [IMPORT] File exists at path: \(fileExists)")
        Self.logger.info("File exists at path: \(fileExists, privacy: .public)")

        if !fileExists {
            let errMsg = "❌ File does not exist at path: \(sourceURL.path)"
            writeDebugLog(errMsg)
            NSLog("📚 [IMPORT] %@", errMsg)
            Self.logger.error("File does not exist at path: \(sourceURL.path, privacy: .public)")
            throw BookLibraryError.fileNotFound
        }

        // Copy file to library
        writeDebugLog("Beginning copy to library")
        NSLog("📚 [IMPORT] Beginning copy to library")
        Self.logger.info("Beginning copy to library")

        let (filePath, _) = try copyToLibrary(from: sourceURL)

        writeDebugLog("✅ Successfully copied to: \(filePath)")
        NSLog("📚 [IMPORT] ✅ Successfully copied to: \(filePath)")
        Self.logger.info("Successfully copied to: \(filePath, privacy: .public)")

        // Extract metadata
        let fileURL = booksDirectory.appendingPathComponent(filePath)
        let (title, _) = extractMetadata(from: fileURL)

        // Create book record
        let book = Book(
            title: title,
            filePath: filePath,
            importDate: Date(),
            lastOpenedDate: nil
        )

        // Save to storage
        var books = getAllBooks()
        books.append(book)
        storage.saveBooks(books)

        Self.logger.info("Imported book: \(title, privacy: .public) (\(book.id, privacy: .public))")

        return book
    }

    // MARK: - Library Operations

    public func getAllBooks() -> [Book] {
        let books = storage.loadBooks()
        // Sort by lastOpenedDate (most recent first), then by importDate
        return books.sorted { lhs, rhs in
            if let lhsDate = lhs.lastOpenedDate, let rhsDate = rhs.lastOpenedDate {
                return lhsDate > rhsDate
            } else if lhs.lastOpenedDate != nil {
                return true
            } else if rhs.lastOpenedDate != nil {
                return false
            } else {
                return lhs.importDate > rhs.importDate
            }
        }
    }

    public func getBook(id: UUID) -> Book? {
        return storage.loadBooks().first { $0.id == id }
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

        Self.logger.info("Deleted book: \(book.title, privacy: .public) (\(id, privacy: .public))")
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
        return booksDirectory.appendingPathComponent(book.filePath)
    }

    private func copyToLibrary(from sourceURL: URL) throws -> (path: String, size: Int64) {
        let uuid = UUID()
        let bookDir = booksDirectory.appendingPathComponent(uuid.uuidString)
        let destURL = bookDir.appendingPathComponent("book.epub")

        NSLog("📁 [COPY] Creating destination directory: \(bookDir.path)")
        Self.logger.info("Creating destination directory: \(bookDir.path, privacy: .public)")
        try fileManager.createDirectory(at: bookDir, withIntermediateDirectories: true)

        NSLog("📁 [COPY] Starting file coordinator copy")
        NSLog("📁 [COPY] Source: \(sourceURL.path)")
        NSLog("📁 [COPY] Dest: \(destURL.path)")
        Self.logger.info("Starting file coordinator copy from: \(sourceURL.path, privacy: .public)")
        Self.logger.info("Destination: \(destURL.path, privacy: .public)")

        var coordinatorError: NSError?
        var copyError: Error?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: sourceURL, options: .withoutChanges, error: &coordinatorError) { url in
            NSLog("📁 [COPY] Coordinator provided URL: \(url.path)")
            NSLog("📁 [COPY] File exists at coordinator URL: \(self.fileManager.fileExists(atPath: url.path))")
            Self.logger.info("Coordinator provided URL: \(url.path, privacy: .public)")
            Self.logger.info("File exists at coordinator URL: \(self.fileManager.fileExists(atPath: url.path), privacy: .public)")

            do {
                try self.fileManager.copyItem(at: url, to: destURL)
                self.writeDebugLog("✅ Copy succeeded")
                NSLog("📁 [COPY] ✅ Copy succeeded")
                Self.logger.info("Copy succeeded")
            } catch {
                let errMsg = """
                ❌ Copy failed
                Error: \(error.localizedDescription)
                Domain: \((error as NSError).domain)
                Code: \((error as NSError).code)
                """
                self.writeDebugLog(errMsg)
                NSLog("📁 [COPY] %@", errMsg)
                Self.logger.error("Copy failed: \(error.localizedDescription, privacy: .public)")
                Self.logger.error("Error details: \((error as NSError).debugDescription, privacy: .public)")
                copyError = error
            }
        }

        if let error = coordinatorError {
            let errMsg = """
            ❌ Coordinator error
            Error: \(error.localizedDescription)
            Domain: \(error.domain)
            Code: \(error.code)
            """
            writeDebugLog(errMsg)
            NSLog("📁 [COPY] %@", errMsg)
            Self.logger.error("Coordinator error: \(error.localizedDescription, privacy: .public)")
            Self.logger.error("Coordinator error domain: \(error.domain, privacy: .public)")
            Self.logger.error("Coordinator error code: \(error.code, privacy: .public)")
            throw BookLibraryError.copyFailed(error)
        }

        if let error = copyError {
            writeDebugLog("❌ Copy error occurred, throwing")
            NSLog("📁 [COPY] ❌ Copy error occurred")
            Self.logger.error("Copy error occurred")
            throw BookLibraryError.copyFailed(error)
        }

        let attributes = try fileManager.attributesOfItem(atPath: destURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        Self.logger.info("File copied successfully, size: \(fileSize, privacy: .public) bytes")

        return (path: "\(uuid.uuidString)/book.epub", size: fileSize)
    }

    private func extractMetadata(from epubURL: URL) -> (title: String, author: String?) {
        do {
            let loader = EPUBLoader()
            let chapter = try loader.loadChapter(from: epubURL, maxSections: 1)
            return (title: chapter.title ?? epubURL.deletingPathExtension().lastPathComponent, author: nil)
        } catch {
            Self.logger.error("Failed to extract metadata: \(error.localizedDescription, privacy: .public)")
            return (title: epubURL.deletingPathExtension().lastPathComponent, author: nil)
        }
    }
}
