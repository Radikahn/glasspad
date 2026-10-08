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
