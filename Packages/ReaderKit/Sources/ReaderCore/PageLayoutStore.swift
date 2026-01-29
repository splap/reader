import Foundation
import OSLog
import SQLite3

/// Persistent storage for page layout calculations
public actor PageLayoutStore {
    private static let logger = Logger(subsystem: "com.splap.reader", category: "PageLayoutStore")

    /// Shared instance
    public static let shared = PageLayoutStore()

    /// SQLite database handle
    private var db: OpaquePointer?

    /// Database file path
    private let dbPath: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let readerDir = appSupport.appendingPathComponent("com.splap.reader", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: readerDir, withIntermediateDirectories: true)

        dbPath = readerDir.appendingPathComponent("page_layouts.sqlite")
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
            Self.logger.error("Failed to open database: \(error)")
            throw PageLayoutStoreError.databaseError("Failed to open: \(error)")
        }

        try createTables()
        Self.logger.info("PageLayoutStore opened at \(self.dbPath.path)")
    }

    /// Closes the database
    public func close() {
        if let db {
            sqlite3_close(db)
            self.db = nil
            Self.logger.info("PageLayoutStore closed")
        }
    }

    /// Creates the page_layouts table
    private func createTables() throws {
        let createTable = """
        CREATE TABLE IF NOT EXISTS page_layouts (
            layout_key TEXT PRIMARY KEY,
            book_id TEXT NOT NULL,
            spine_item_id TEXT NOT NULL,
            config_json TEXT NOT NULL,
            offsets_json TEXT NOT NULL,
            computed_at INTEGER NOT NULL,
            version INTEGER NOT NULL
        );
        """

        let createBookIndex = """
        CREATE INDEX IF NOT EXISTS idx_layouts_book
        ON page_layouts(book_id);
        """

        let createSpineIndex = """
        CREATE INDEX IF NOT EXISTS idx_layouts_spine
        ON page_layouts(book_id, spine_item_id);
        """

        for sql in [createTable, createBookIndex, createSpineIndex] {
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
            Self.logger.error("SQL error: \(error)")
            throw PageLayoutStoreError.databaseError(error)
        }
    }

    // MARK: - CRUD Operations

    /// Loads a layout from the cache
    public func loadLayout(bookId: String, spineItemId: String, config: LayoutConfig) throws -> ChapterLayout? {
        if db == nil {
            try open()
        }

        let layoutKey = ChapterLayout.generateLayoutKey(bookId: bookId, spineItemId: spineItemId, config: config)

        let sql = "SELECT config_json, offsets_json, computed_at, version FROM page_layouts WHERE layout_key = ?;"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw PageLayoutStoreError.databaseError("Failed to prepare select statement")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, layoutKey, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        if sqlite3_step(stmt) == SQLITE_ROW {
            guard let configCStr = sqlite3_column_text(stmt, 0),
                  let offsetsCStr = sqlite3_column_text(stmt, 1)
            else {
                return nil
            }

            let configJSON = String(cString: configCStr)
            let offsetsJSON = String(cString: offsetsCStr)
            let computedAtTimestamp = sqlite3_column_int64(stmt, 2)
            let version = Int(sqlite3_column_int(stmt, 3))

            // Check version compatibility
            guard version == ChapterLayout.formatVersion else {
                Self.logger.info("Layout version mismatch: stored=\(version), current=\(ChapterLayout.formatVersion)")
                return nil
            }

            // Decode JSON
            let decoder = JSONDecoder()
            guard let configData = configJSON.data(using: .utf8),
                  let offsetsData = offsetsJSON.data(using: .utf8),
                  let storedConfig = try? decoder.decode(LayoutConfig.self, from: configData),
                  let pageOffsets = try? decoder.decode([PageOffset].self, from: offsetsData)
            else {
                Self.logger.warning("Failed to decode layout JSON")
                return nil
            }

            let computedAt = Date(timeIntervalSince1970: TimeInterval(computedAtTimestamp))

            return ChapterLayout(
                bookId: bookId,
                spineItemId: spineItemId,
                config: storedConfig,
                pageOffsets: pageOffsets,
                computedAt: computedAt
            )
        }

        return nil
    }

    /// Saves a layout to the cache
    public func saveLayout(_ layout: ChapterLayout) throws {
        if db == nil {
            try open()
        }

        let encoder = JSONEncoder()
        guard let configData = try? encoder.encode(layout.config),
              let configJSON = String(data: configData, encoding: .utf8),
              let offsetsData = try? encoder.encode(layout.pageOffsets),
              let offsetsJSON = String(data: offsetsData, encoding: .utf8)
        else {
            throw PageLayoutStoreError.databaseError("Failed to encode layout to JSON")
        }

        let sql = """
        INSERT OR REPLACE INTO page_layouts
        (layout_key, book_id, spine_item_id, config_json, offsets_json, computed_at, version)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw PageLayoutStoreError.databaseError("Failed to prepare insert statement")
        }
        defer { sqlite3_finalize(stmt) }

        let computedAtTimestamp = Int64(layout.computedAt.timeIntervalSince1970)

        sqlite3_bind_text(stmt, 1, layout.layoutKey, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 2, layout.bookId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 3, layout.spineItemId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 4, configJSON, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 5, offsetsJSON, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int64(stmt, 6, computedAtTimestamp)
        sqlite3_bind_int(stmt, 7, Int32(layout.version))

        if sqlite3_step(stmt) != SQLITE_DONE {
            let error = String(cString: sqlite3_errmsg(db))
            throw PageLayoutStoreError.databaseError("Insert failed: \(error)")
        }

        Self.logger.info("Saved layout for \(layout.spineItemId) with \(layout.pageOffsets.count) pages")
    }

    /// Checks if a layout exists in the cache
    public func hasLayout(bookId: String, spineItemId: String, config: LayoutConfig) throws -> Bool {
        if db == nil {
            try open()
        }

        let layoutKey = ChapterLayout.generateLayoutKey(bookId: bookId, spineItemId: spineItemId, config: config)

        let sql = "SELECT version FROM page_layouts WHERE layout_key = ?;"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw PageLayoutStoreError.databaseError("Failed to prepare exists statement")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, layoutKey, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        if sqlite3_step(stmt) == SQLITE_ROW {
            let version = Int(sqlite3_column_int(stmt, 0))
            return version == ChapterLayout.formatVersion
        }

        return false
    }

    /// Deletes all layouts for a book
    public func deleteLayouts(bookId: String) throws {
        if db == nil {
            try open()
        }

        let sql = "DELETE FROM page_layouts WHERE book_id = ?;"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw PageLayoutStoreError.databaseError("Failed to prepare delete statement")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, bookId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        if sqlite3_step(stmt) != SQLITE_DONE {
            let error = String(cString: sqlite3_errmsg(db))
            throw PageLayoutStoreError.databaseError("Delete failed: \(error)")
        }

        Self.logger.info("Deleted layouts for book \(bookId)")
    }

    /// Deletes a specific layout
    public func deleteLayout(bookId: String, spineItemId: String, config: LayoutConfig) throws {
        if db == nil {
            try open()
        }

        let layoutKey = ChapterLayout.generateLayoutKey(bookId: bookId, spineItemId: spineItemId, config: config)

        let sql = "DELETE FROM page_layouts WHERE layout_key = ?;"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw PageLayoutStoreError.databaseError("Failed to prepare delete statement")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, layoutKey, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        if sqlite3_step(stmt) != SQLITE_DONE {
            let error = String(cString: sqlite3_errmsg(db))
            throw PageLayoutStoreError.databaseError("Delete failed: \(error)")
        }
    }

    /// Gets count of cached layouts for a book
    public func layoutCount(bookId: String) throws -> Int {
        if db == nil {
            try open()
        }

        let sql = "SELECT COUNT(*) FROM page_layouts WHERE book_id = ?;"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw PageLayoutStoreError.databaseError("Failed to prepare count statement")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, bookId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }

        return 0
    }
}

/// Errors that can occur in PageLayoutStore operations
public enum PageLayoutStoreError: Error, LocalizedError {
    case databaseError(String)
    case notFound

    public var errorDescription: String? {
        switch self {
        case let .databaseError(message):
            "Database error: \(message)"
        case .notFound:
            "Layout not found"
        }
    }
}
