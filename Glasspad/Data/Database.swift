import Foundation
import SQLite3

struct DatabaseError: Error, CustomStringConvertible {
    let description: String
}

/// Thin wrapper over the system SQLite library. Entries live in
/// ~/Library/Application Support/Glasspad/glasspad.sqlite.
final class Database {
    private var db: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func defaultURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = support.appendingPathComponent("Glasspad", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("glasspad.sqlite")
    }

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            throw DatabaseError(description: "Could not open database: \(message)")
        }
        try exec("PRAGMA journal_mode = WAL;")
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: Schema

    private func migrate() throws {
        if userVersion() < 1 {
            try exec("""
                CREATE TABLE IF NOT EXISTS entries (
                    id          INTEGER PRIMARY KEY AUTOINCREMENT,
                    body        TEXT NOT NULL DEFAULT '',
                    created_at  REAL NOT NULL,
                    updated_at  REAL NOT NULL
                );
                CREATE INDEX IF NOT EXISTS entries_created_at ON entries(created_at DESC);
                PRAGMA user_version = 1;
                """)
        }
        if userVersion() < 2 {
            try exec("""
                CREATE TABLE IF NOT EXISTS images (
                    id          TEXT PRIMARY KEY,
                    entry_id    INTEGER NOT NULL,
                    data        BLOB NOT NULL,
                    created_at  REAL NOT NULL
                );
                CREATE INDEX IF NOT EXISTS images_entry_id ON images(entry_id);
                """)
            try importImageFiles()
            try exec("PRAGMA user_version = 2;")
        }
    }

    /// Early builds saved pasted images as files and linked them with file:// URLs.
    /// Copy those into the images table and point the links at the copies.
    /// The files themselves are left where they are.
    private func importImageFiles() throws {
        let pattern = try NSRegularExpression(pattern: #"\]\((file://[^)\s]*/Glasspad/Images/[^)\s]+)\)"#)
        for entry in fetchEntries() {
            let body = entry.body as NSString
            var updated = entry.body
            for m in pattern.matches(in: entry.body, range: NSRange(location: 0, length: body.length)) {
                let link = body.substring(with: m.range(at: 1))
                guard let url = URL(string: link), let data = try? Data(contentsOf: url) else { continue }
                let id = UUID().uuidString.lowercased()
                guard insertImage(id: id, entryID: entry.id, data: data) else { continue }
                updated = updated.replacingOccurrences(of: link, with: "glasspad://image/\(id)")
            }
            if updated != entry.body { updateEntry(id: entry.id, body: updated, updatedAt: entry.updatedAt) }
        }
    }

    private func userVersion() -> Int {
        var version = 0
        query("PRAGMA user_version;") { stmt in version = Int(sqlite3_column_int(stmt, 0)) }
        return version
    }

    // MARK: Entries

    func fetchEntries() -> [Entry] {
        var entries: [Entry] = []
        query("SELECT id, body, created_at, updated_at FROM entries ORDER BY created_at DESC;") { stmt in
            let body = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            entries.append(Entry(
                id: sqlite3_column_int64(stmt, 0),
                body: body,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))))
        }
        return entries
    }

    func insertEntry(body: String, date: Date) -> Int64? {
        let ok = run("INSERT INTO entries (body, created_at, updated_at) VALUES (?, ?, ?);") { stmt in
            sqlite3_bind_text(stmt, 1, body, -1, Self.transient)
            sqlite3_bind_double(stmt, 2, date.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 3, date.timeIntervalSince1970)
        }
        return ok ? sqlite3_last_insert_rowid(db) : nil
    }

    func updateEntry(id: Int64, body: String, updatedAt: Date) {
        run("UPDATE entries SET body = ?, updated_at = ? WHERE id = ?;") { stmt in
            sqlite3_bind_text(stmt, 1, body, -1, Self.transient)
            sqlite3_bind_double(stmt, 2, updatedAt.timeIntervalSince1970)
            sqlite3_bind_int64(stmt, 3, id)
        }
    }

    func deleteEntry(id: Int64) {
        run("DELETE FROM entries WHERE id = ?;") { stmt in
            sqlite3_bind_int64(stmt, 1, id)
        }
        run("DELETE FROM images WHERE entry_id = ?;") { stmt in
            sqlite3_bind_int64(stmt, 1, id)
        }
    }

    // MARK: Images

    @discardableResult
    func insertImage(id: String, entryID: Int64, data: Data) -> Bool {
        run("INSERT INTO images (id, entry_id, data, created_at) VALUES (?, ?, ?, ?);") { stmt in
            sqlite3_bind_text(stmt, 1, id, -1, Self.transient)
            sqlite3_bind_int64(stmt, 2, entryID)
            _ = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(stmt, 3, bytes.baseAddress, Int32(bytes.count), Self.transient)
            }
            sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
        }
    }

    func imageData(id: String) -> Data? {
        var data: Data?
        query("SELECT data FROM images WHERE id = '\(id.filter { $0.isHexDigit || $0 == "-" })';") { stmt in
            guard let bytes = sqlite3_column_blob(stmt, 0) else { return }
            data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))
        }
        return data
    }

    // MARK: Helpers

    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(error)
            throw DatabaseError(description: message)
        }
    }

    @discardableResult
    private func run(_ sql: String, bind: (OpaquePointer?) -> Void) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError(sql)
            return false
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            logError(sql)
            return false
        }
        return true
    }

    private func query(_ sql: String, row: (OpaquePointer?) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError(sql)
            return
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW { row(stmt) }
    }

    private func logError(_ sql: String) {
        NSLog("Glasspad SQLite error (%@): %@", sql, String(cString: sqlite3_errmsg(db)))
    }
}
