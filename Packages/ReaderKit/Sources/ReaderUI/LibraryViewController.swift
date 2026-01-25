import UIKit
import ReaderCore
import OSLog

public final class LibraryViewController: UITableViewController {
    private static let logger = Log.logger(category: "library-vc")
    private var books: [Book] = []
    private var isOpeningBook = false

    public init() {
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = "Library"
        navigationController?.navigationBar.prefersLargeTitles = true

        tableView.register(BookTableViewCell.self, forCellReuseIdentifier: "BookCell")

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addBook)
        )

        loadBooks()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(loadBooks),
            name: .bookLibraryDidChange,
            object: nil
        )
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadBooks()
    }

    @objc private func loadBooks() {
        books = BookLibraryService.shared.getAllBooks()
        tableView.reloadData()
    }

    @objc private func addBook() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.epub])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    // MARK: - Table View Data Source

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return books.count
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BookCell", for: indexPath) as! BookTableViewCell
        cell.configure(with: books[indexPath.row])
        return cell
    }

    // MARK: - Table View Delegate

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        // Prevent multiple taps while opening a book
        guard !isOpeningBook else { return }

        let book = books[indexPath.row]
        openBook(book)
    }

    public override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let book = books[indexPath.row]
            showDeleteConfirmation(for: book, at: indexPath)
        }
    }

    private func openBook(_ book: Book) {
        isOpeningBook = true

        // Always open the book immediately - indexing happens in background
        // Semantic search will gracefully degrade until embeddings are ready
        Self.logger.info("Opening book: \(book.title)")

        // Kick off background indexing if needed (non-blocking)
        BookLibraryService.shared.ensureIndexedInBackground(book: book)

        navigateToReader(book: book)
    }

    private func navigateToReader(book: Book) {
        let navStart = CFAbsoluteTimeGetCurrent()
        let fileURL = BookLibraryService.shared.getFileURL(for: book)
        let readerVC = ReaderViewController(
            epubURL: fileURL,
            bookId: book.id.uuidString,
            bookTitle: book.title,
            bookAuthor: book.author
        )
        Self.logger.info("PERF: ReaderViewController creation took \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - navStart))s for \(book.title)")

        BookLibraryService.shared.updateLastOpened(bookId: book.id)
        navigationController?.pushViewController(readerVC, animated: true)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Reset the flag when returning to the library
        isOpeningBook = false
    }

    private func showDeleteConfirmation(for book: Book, at indexPath: IndexPath) {
        let alert = UIAlertController(
            title: "Delete Book",
            message: "Are you sure you want to delete \"\(book.title)\"?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteBook(book)
        })

        present(alert, animated: true)
    }

    private func deleteBook(_ book: Book) {
        do {
            try BookLibraryService.shared.deleteBook(id: book.id)
            loadBooks()
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Document Picker Delegate
extension LibraryViewController: UIDocumentPickerDelegate {
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }

        do {
            _ = try BookLibraryService.shared.importBook(from: url, startAccessing: true)
            loadBooks()
        } catch {
            showError(error.localizedDescription)
        }
    }
}

// MARK: - Book Table View Cell
private final class BookTableViewCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        imageView?.image = UIImage(systemName: "book.closed.fill")
        imageView?.tintColor = .systemBlue
        accessoryType = .disclosureIndicator
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with book: Book) {
        textLabel?.text = book.title
        accessibilityLabel = book.title

        if let lastOpened = book.lastOpenedDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relativeDate = formatter.localizedString(for: lastOpened, relativeTo: Date())
            detailTextLabel?.text = "Last opened \(relativeDate) ago"
        } else {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relativeDate = formatter.localizedString(for: book.importDate, relativeTo: Date())
            detailTextLabel?.text = "Imported \(relativeDate) ago"
        }
    }
}

// MARK: - Notification Extension
public extension Notification.Name {
    static let bookLibraryDidChange = Notification.Name("bookLibraryDidChange")
}
