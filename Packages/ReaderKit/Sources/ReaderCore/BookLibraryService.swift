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
            return "The selected file could not be found."
        case .invalidEPUB:
            return "The file is not a valid EPUB document."
        case .copyFailed(let error):
            return "Failed to import book: \(error.localizedDescription)"
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
    private static let logger = Logger(subsystem: "com.example.reader", category: "library")

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
        self.booksDirectory = appSupport.appendingPathComponent("Books")

        // Create Books directory if it doesn't exist
        try? fileManager.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Import Operations

    public func importBook(from sourceURL: URL, startAccessing: Bool = false) throws -> Book {
        if startAccessing {
            guard sourceURL.startAccessingSecurityScopedResource() else {
                throw BookLibraryError.fileNotFound
            }
            defer { sourceURL.stopAccessingSecurityScopedResource() }
        }

        // Copy file to library
        let (filePath, _) = try copyToLibrary(from: sourceURL)

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

        try fileManager.createDirectory(at: bookDir, withIntermediateDirectories: true)

        var coordinatorError: NSError?
        var copyError: Error?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: sourceURL, options: .withoutChanges, error: &coordinatorError) { url in
            do {
                try fileManager.copyItem(at: url, to: destURL)
            } catch {
                copyError = error
            }
        }

        if let error = coordinatorError ?? copyError {
            throw BookLibraryError.copyFailed(error)
        }

        let attributes = try fileManager.attributesOfItem(atPath: destURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

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
