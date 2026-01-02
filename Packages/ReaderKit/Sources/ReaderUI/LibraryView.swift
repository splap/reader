import SwiftUI
import ReaderCore

public struct LibraryView: View {
    @State private var books: [Book] = []
    @State private var showingDocumentPicker = false
    @State private var errorMessage: String?
    @State private var bookToDelete: Book?

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    emptyStateView
                } else {
                    bookListView
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingDocumentPicker = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker(onPick: handleDocumentPick)
            }
            .alert("Import Error", isPresented: .constant(errorMessage != nil), actions: {
                Button("OK") { errorMessage = nil }
            }, message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            })
            .alert("Delete Book", isPresented: .constant(bookToDelete != nil), actions: {
                Button("Cancel", role: .cancel) { bookToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let book = bookToDelete {
                        deleteBook(book)
                        bookToDelete = nil
                    }
                }
            }, message: {
                if let book = bookToDelete {
                    Text("Are you sure you want to delete \"\(book.title)\"?")
                }
            })
            .onAppear {
                loadBooks()
            }
            .onReceive(NotificationCenter.default.publisher(for: .bookLibraryDidChange)) { _ in
                loadBooks()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No books")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Tap + to add your first book")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var bookListView: some View {
        List {
            ForEach(books) { book in
                NavigationLink(value: book) {
                    BookListRow(book: book)
                }
            }
            .onDelete { indexSet in
                if let index = indexSet.first {
                    bookToDelete = books[index]
                }
            }
        }
        .navigationDestination(for: Book.self) { book in
            ReaderContainerView(book: book)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func loadBooks() {
        books = BookLibraryService.shared.getAllBooks()
    }

    private func handleDocumentPick(url: URL) {
        do {
            _ = try BookLibraryService.shared.importBook(from: url, startAccessing: true)
            loadBooks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteBook(_ book: Book) {
        do {
            try BookLibraryService.shared.deleteBook(id: book.id)
            loadBooks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct BookListRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                if let lastOpened = book.lastOpenedDate {
                    Text("Last opened \(lastOpened, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Imported \(book.importDate, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

public extension Notification.Name {
    static let bookLibraryDidChange = Notification.Name("bookLibraryDidChange")
}
