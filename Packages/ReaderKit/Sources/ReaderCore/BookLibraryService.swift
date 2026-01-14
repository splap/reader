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
        writeDebugLog("Starting import from: \(sourceURL.path)")
        Self.logger.debug("Importing book from: \(sourceURL.path, privacy: .public) (scheme: \(sourceURL.scheme ?? "nil", privacy: .public), security scope: \(startAccessing, privacy: .public))")

        // Only use security-scoped resource access if the file is outside our sandbox
        // Files in tmp/Inbox are already accessible
        let needsSecurityScope = startAccessing && !sourceURL.path.contains("/tmp/")
        var didStartAccessing = false

        if needsSecurityScope {
            didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
            if !didStartAccessing {
                writeDebugLog("Failed to start accessing security scoped resource")
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
        Self.logger.debug("File exists check: \(fileExists, privacy: .public)")

        if !fileExists {
            writeDebugLog("File does not exist at path: \(sourceURL.path)")
            Self.logger.error("File does not exist at path: \(sourceURL.path, privacy: .public)")
            throw BookLibraryError.fileNotFound
        }

        // Copy file to library
        writeDebugLog("Beginning copy to library")
        Self.logger.debug("Copying book to library")

        let (filePath, _) = try copyToLibrary(from: sourceURL)

        writeDebugLog("Successfully copied to: \(filePath)")
        Self.logger.debug("Copy complete: \(filePath, privacy: .public)")

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

        Self.logger.debug("Creating book directory: \(uuid.uuidString, privacy: .public)")
        try fileManager.createDirectory(at: bookDir, withIntermediateDirectories: true)

        Self.logger.debug("Copying file from \(sourceURL.lastPathComponent, privacy: .public) to library")

        var coordinatorError: NSError?
        var copyError: Error?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: sourceURL, options: .withoutChanges, error: &coordinatorError) { url in
            Self.logger.debug("File coordinator provided URL: \(url.lastPathComponent, privacy: .public)")

            do {
                try self.fileManager.copyItem(at: url, to: destURL)
                self.writeDebugLog("Copy succeeded")
                Self.logger.debug("File copy completed successfully")
            } catch {
                self.writeDebugLog("Copy failed: \(error.localizedDescription)")
                Self.logger.error("Copy failed: \(error.localizedDescription, privacy: .public)")
                copyError = error
            }
        }

        if let error = coordinatorError {
            writeDebugLog("Coordinator error: \(error.localizedDescription)")
            Self.logger.error("File coordinator error: \(error.localizedDescription, privacy: .public)")
            throw BookLibraryError.copyFailed(error)
        }

        if let error = copyError {
            writeDebugLog("Copy error occurred")
            Self.logger.error("Copy operation failed")
            throw BookLibraryError.copyFailed(error)
        }

        let attributes = try fileManager.attributesOfItem(atPath: destURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        Self.logger.debug("File copied successfully, size: \(fileSize, privacy: .public) bytes")

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

            // Load set of already-imported test book filenames from UserDefaults
            let defaults = UserDefaults.standard
            var importedFiles = Set(defaults.stringArray(forKey: "ImportedTestBooks") ?? [])
            Self.logger.debug("Already imported: \(importedFiles.count) test books")

            var newImports = 0
            for epubURL in epubFiles {
                let filename = epubURL.lastPathComponent

                // Check if we've already imported this file
                if importedFiles.contains(filename) {
                    Self.logger.debug("Skipping already imported: \(filename, privacy: .public)")
                    continue
                }

                do {
                    let book = try importBook(from: epubURL, startAccessing: false)
                    Self.logger.info("Imported test book: \(book.title, privacy: .public)")
                    newImports += 1

                    // Mark this file as imported
                    importedFiles.insert(filename)
                    defaults.set(Array(importedFiles), forKey: "ImportedTestBooks")
                } catch {
                    Self.logger.error("Failed to import \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }

            if newImports > 0 {
                Self.logger.info("Imported \(newImports, privacy: .public) new test books")
            }
        } catch {
            Self.logger.error("Failed to scan TestBooks: \(error.localizedDescription, privacy: .public)")
        }
    }
}
