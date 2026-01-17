import Foundation
import SQLite3
import OSLog

/// Persistent storage for book chunks with FTS5 full-text search
public actor ChunkStore {
    private static let logger = Logger(subsystem: "com.splap.reader", category: "ChunkStore")

    /// Shared instance
    public static let shared = ChunkStore()

    /// SQLite database handle
    private var db: OpaquePointer?

    /// Database file path
    private let dbPath: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let readerDir = appSupport.appendingPathComponent("com.splap.reader", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: readerDir, withIntermediateDirectories: true)

        self.dbPath = readerDir.appendingPathComponent("book_index.sqlite")
    }

    /// Opens the database and creates tables if needed
    public func open() throws {
        guard db == nil else { return }

        // Ensure directory exists
        let dir = dbPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let result = sqlite3_open(dbPath.path, &db)
        guard result == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            Self.logger.error("Failed to open database: \(error, privacy: .public)")
            throw ChunkStoreError.databaseError("Failed to open: \(error)")
        }

        try createTables()
        Self.logger.info("ChunkStore opened at \(self.dbPath.path, privacy: .public)")
    }

    /// Closes the database
    public func close() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
            Self.logger.info("ChunkStore closed")
        }
    }

    /// Creates the chunks table and FTS5 virtual table
    private func createTables() throws {
        // Main chunks table
        let createChunks = """
            CREATE TABLE IF NOT EXISTS chunks (
                id TEXT PRIMARY KEY,
                book_id TEXT NOT NULL,
                chapter_id TEXT NOT NULL,
                text TEXT NOT NULL,
                token_count INTEGER NOT NULL,
                block_ids TEXT NOT NULL,
                start_offset INTEGER NOT NULL,
                end_offset INTEGER NOT NULL,
                ordinal INTEGER NOT NULL
            );
            """

        // Index for scoped queries
        let createIndex = """
            CREATE INDEX IF NOT EXISTS idx_chunks_book_chapter
            ON chunks(book_id, chapter_id);
            """

        // FTS5 virtual table for full-text search
        // Note: content= makes this a "contentless" FTS table that references chunks
        let createFTS = """
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
                text,
                content='chunks',
                content_rowid='rowid'
            );
            """

        // Triggers to keep FTS in sync with chunks table
        let triggerInsert = """
            CREATE TRIGGER IF NOT EXISTS chunks_ai AFTER INSERT ON chunks BEGIN
                INSERT INTO chunks_fts(rowid, text) VALUES (new.rowid, new.text);
            END;
            """

        let triggerDelete = """
            CREATE TRIGGER IF NOT EXISTS chunks_ad AFTER DELETE ON chunks BEGIN
                INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES('delete', old.rowid, old.text);
            END;
            """

        let triggerUpdate = """
            CREATE TRIGGER IF NOT EXISTS chunks_au AFTER UPDATE ON chunks BEGIN
                INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES('delete', old.rowid, old.text);
                INSERT INTO chunks_fts(rowid, text) VALUES (new.rowid, new.text);
            END;
            """

        for sql in [createChunks, createIndex, createFTS, triggerInsert, triggerDelete, triggerUpdate] {
            try execute(sql)
        }
    }

    /// Executes a SQL statement
    private func execute(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errMsg)

        if result != SQLITE_OK {
            let error = errMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errMsg)
            Self.logger.error("SQL error: \(error, privacy: .public)")
            throw ChunkStoreError.databaseError(error)
        }
    }

    // MARK: - Indexing

    /// Indexes all chunks for a book
    /// - Parameters:
    ///   - chunks: The chunks to index
    ///   - bookId: The book identifier
    public func indexBook(chunks: [Chunk], bookId: String) throws {
        if db == nil {
            try open()
        }

        Self.logger.info("Indexing \(chunks.count, privacy: .public) chunks for book \(bookId, privacy: .public)")

        // Delete existing chunks for this book
        try deleteBook(bookId: bookId)

        // Insert all chunks
        let insertSQL = """
            INSERT INTO chunks (id, book_id, chapter_id, text, token_count, block_ids, start_offset, end_offset, ordinal)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw ChunkStoreError.databaseError("Failed to prepare insert statement")
        }
        defer { sqlite3_finalize(stmt) }

        // Use a transaction for performance
        try execute("BEGIN TRANSACTION;")

        do {
            for chunk in chunks {
                sqlite3_reset(stmt)

                let blockIdsJSON = try JSONEncoder().encode(chunk.blockIds)
                let blockIdsString = String(data: blockIdsJSON, encoding: .utf8) ?? "[]"

                sqlite3_bind_text(stmt, 1, chunk.id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 2, chunk.bookId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 3, chunk.chapterId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 4, chunk.text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int(stmt, 5, Int32(chunk.tokenCount))
                sqlite3_bind_text(stmt, 6, blockIdsString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int(stmt, 7, Int32(chunk.startOffset))
                sqlite3_bind_int(stmt, 8, Int32(chunk.endOffset))
                sqlite3_bind_int(stmt, 9, Int32(chunk.ordinal))

                if sqlite3_step(stmt) != SQLITE_DONE {
                    let error = String(cString: sqlite3_errmsg(db))
                    throw ChunkStoreError.databaseError("Insert failed: \(error)")
                }
            }

            try execute("COMMIT;")
            Self.logger.info("Successfully indexed \(chunks.count, privacy: .public) chunks")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    /// Deletes all chunks for a book
    public func deleteBook(bookId: String) throws {
        guard db != nil else { return }

        let sql = "DELETE FROM chunks WHERE book_id = ?;"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ChunkStoreError.databaseError("Failed to prepare delete statement")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, bookId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        if sqlite3_step(stmt) != SQLITE_DONE {
            let error = String(cString: sqlite3_errmsg(db))
            throw ChunkStoreError.databaseError("Delete failed: \(error)")
        }

        Self.logger.info("Deleted chunks for book \(bookId, privacy: .public)")
    }

    // MARK: - Search

    /// Searches for chunks matching a query
    /// - Parameters:
    ///   - query: The search query (supports FTS5 syntax)
    ///   - bookId: The book to search in
    ///   - chapterIds: Optional list of chapters to scope the search
    ///   - limit: Maximum number of results (default 10)
    /// - Returns: Array of matching chunks with scores
    public func search(query: String, bookId: String, chapterIds: [String]? = nil, limit: Int = 10) throws -> [ChunkMatch] {
        if db == nil {
            try open()
        }

        // Escape special FTS5 characters in query
        let escapedQuery = escapeFTSQuery(query)

        var sql: String
        var params: [String]

        if let chapterIds = chapterIds, !chapterIds.isEmpty {
            // Scoped search with chapter filter
            let placeholders = chapterIds.map { _ in "?" }.joined(separator: ", ")
            sql = """
                SELECT c.*, bm25(chunks_fts) as score
                FROM chunks c
                JOIN chunks_fts ON c.rowid = chunks_fts.rowid
                WHERE chunks_fts MATCH ?
                AND c.book_id = ?
                AND c.chapter_id IN (\(placeholders))
                ORDER BY score
                LIMIT ?;
                """
            params = [escapedQuery, bookId] + chapterIds + [String(limit)]
        } else {
            // Book-wide search
            sql = """
                SELECT c.*, bm25(chunks_fts) as score
                FROM chunks c
                JOIN chunks_fts ON c.rowid = chunks_fts.rowid
                WHERE chunks_fts MATCH ?
                AND c.book_id = ?
                ORDER BY score
                LIMIT ?;
                """
            params = [escapedQuery, bookId, String(limit)]
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            throw ChunkStoreError.databaseError("Search prepare failed: \(error)")
        }
        defer { sqlite3_finalize(stmt) }

        // Bind parameters
        for (index, param) in params.enumerated() {
            if let intValue = Int32(param), index == params.count - 1 {
                sqlite3_bind_int(stmt, Int32(index + 1), intValue)
            } else {
                sqlite3_bind_text(stmt, Int32(index + 1), param, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }

        var matches: [ChunkMatch] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let chunk = parseChunkRow(stmt) {
                let score = sqlite3_column_double(stmt, 9)  // bm25 score
                let snippet = generateSnippet(text: chunk.text, query: query)
                matches.append(ChunkMatch(chunk: chunk, score: -score, snippet: snippet))  // Negate because bm25 returns negative
            }
        }

        Self.logger.debug("Search for '\(query, privacy: .public)' returned \(matches.count, privacy: .public) results")
        return matches
    }

    /// Escapes special FTS5 query characters
    private func escapeFTSQuery(_ query: String) -> String {
        // For simple queries, wrap in double quotes to do exact phrase matching
        // For more complex queries, the caller should handle FTS5 syntax
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("\"") || trimmed.contains("AND") || trimmed.contains("OR") || trimmed.contains("NOT") {
            // Looks like intentional FTS5 syntax, pass through
            return trimmed
        }
        // Simple query - escape as phrase
        return "\"\(trimmed.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// Generates a snippet with the query highlighted
    private func generateSnippet(text: String, query: String, contextLength: Int = 100) -> String? {
        let lowercaseText = text.lowercased()
        let lowercaseQuery = query.lowercased()

        guard let range = lowercaseText.range(of: lowercaseQuery) else {
            // No exact match, return beginning of text
            let endIndex = text.index(text.startIndex, offsetBy: min(contextLength * 2, text.count))
            return String(text[..<endIndex]) + "..."
        }

        // Calculate snippet bounds
        let matchStart = text.distance(from: text.startIndex, to: range.lowerBound)
        let snippetStart = max(0, matchStart - contextLength)
        let snippetEnd = min(text.count, matchStart + query.count + contextLength)

        let startIndex = text.index(text.startIndex, offsetBy: snippetStart)
        let endIndex = text.index(text.startIndex, offsetBy: snippetEnd)

        var snippet = String(text[startIndex..<endIndex])
        if snippetStart > 0 { snippet = "..." + snippet }
        if snippetEnd < text.count { snippet = snippet + "..." }

        return snippet
    }

    /// Parses a chunk from a SQLite row
    private func parseChunkRow(_ stmt: OpaquePointer?) -> Chunk? {
        guard let stmt = stmt else { return nil }

        guard let idCStr = sqlite3_column_text(stmt, 0),
              let bookIdCStr = sqlite3_column_text(stmt, 1),
              let chapterIdCStr = sqlite3_column_text(stmt, 2),
              let textCStr = sqlite3_column_text(stmt, 3),
              let blockIdsCStr = sqlite3_column_text(stmt, 5) else {
            return nil
        }

        let id = String(cString: idCStr)
        let bookId = String(cString: bookIdCStr)
        let chapterId = String(cString: chapterIdCStr)
        let text = String(cString: textCStr)
        let tokenCount = Int(sqlite3_column_int(stmt, 4))
        let blockIdsString = String(cString: blockIdsCStr)
        let startOffset = Int(sqlite3_column_int(stmt, 6))
        let endOffset = Int(sqlite3_column_int(stmt, 7))
        let ordinal = Int(sqlite3_column_int(stmt, 8))

        let blockIds: [String]
        if let data = blockIdsString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            blockIds = decoded
        } else {
            blockIds = []
        }

        return Chunk(
            id: id,
            bookId: bookId,
            chapterId: chapterId,
            text: text,
            tokenCount: tokenCount,
            blockIds: blockIds,
            startOffset: startOffset,
            endOffset: endOffset,
            ordinal: ordinal
        )
    }

    // MARK: - Direct Access

    /// Gets a chunk by ID
    public func getChunk(id: String) throws -> Chunk? {
        if db == nil {
            try open()
        }

        let sql = "SELECT * FROM chunks WHERE id = ?;"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ChunkStoreError.databaseError("Failed to prepare select statement")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        if sqlite3_step(stmt) == SQLITE_ROW {
            return parseChunkRow(stmt)
        }
        return nil
    }

    /// Gets all chunks for a chapter
    public func getChunks(bookId: String, chapterId: String) throws -> [Chunk] {
        if db == nil {
            try open()
        }

        let sql = "SELECT * FROM chunks WHERE book_id = ? AND chapter_id = ? ORDER BY ordinal;"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ChunkStoreError.databaseError("Failed to prepare select statement")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, bookId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 2, chapterId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        var chunks: [Chunk] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let chunk = parseChunkRow(stmt) {
                chunks.append(chunk)
            }
        }
        return chunks
    }

    /// Gets all chunks for a book
    public func getChunks(bookId: String) throws -> [Chunk] {
        if db == nil {
            try open()
        }

        let sql = "SELECT * FROM chunks WHERE book_id = ? ORDER BY chapter_id, ordinal;"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ChunkStoreError.databaseError("Failed to prepare select statement")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, bookId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        var chunks: [Chunk] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let chunk = parseChunkRow(stmt) {
                chunks.append(chunk)
            }
        }
        return chunks
    }

    /// Checks if a book has been indexed
    public func isBookIndexed(bookId: String) throws -> Bool {
        if db == nil {
            try open()
        }

        let sql = "SELECT COUNT(*) FROM chunks WHERE book_id = ?;"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ChunkStoreError.databaseError("Failed to prepare count statement")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, bookId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int(stmt, 0) > 0
        }
        return false
    }
}

/// Errors that can occur in ChunkStore operations
public enum ChunkStoreError: Error, LocalizedError {
    case databaseError(String)
    case notFound

    public var errorDescription: String? {
        switch self {
        case .databaseError(let message):
            return "Database error: \(message)"
        case .notFound:
            return "Chunk not found"
        }
    }
}
