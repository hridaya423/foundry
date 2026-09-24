import Foundation
import SQLite3

final class ClipboardHistoryStore: ClipboardHistoryPersisting, @unchecked Sendable {
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/foundry")
    }

    let databaseURL: URL
    let imagesURL: URL
    private let legacyURL: URL
    private let lock = NSLock()
    private var db: OpaquePointer?

    init(directory: URL = ClipboardHistoryStore.defaultDirectory, legacyURL: URL = ClipboardHistoryPersistence().url) {
        databaseURL = directory.appendingPathComponent("clipboard.sqlite")
        imagesURL = directory.appendingPathComponent("clipboard-images", isDirectory: true)
        self.legacyURL = legacyURL
    }

    deinit { sqlite3_close(db) }

    func load() throws -> [ClipboardHistoryItem] {
        try lock.withLock {
            try openIfNeeded()
            var items = try selectAll()
            if items.isEmpty, FileManager.default.fileExists(atPath: legacyURL.path) {
                let legacy: [ClipboardHistoryItem]
                do { legacy = try JSONDecoder().decode([ClipboardHistoryItem].self, from: Data(contentsOf: legacyURL)) }
                catch { throw ClipboardHistoryPersistenceError.corruptArchive(error) }
                try write(legacy)
                let migrated = legacyURL.appendingPathExtension("migrated")
                try? FileManager.default.removeItem(at: migrated)
                try FileManager.default.moveItem(at: legacyURL, to: migrated)
                items = try selectAll()
            }
            return items
        }
    }

    func save(_ items: [ClipboardHistoryItem]) throws {
        try lock.withLock {
            do {
                try openIfNeeded()
                try write(items)
            } catch let error as ClipboardHistoryPersistenceError {
                throw error
            } catch {
                throw ClipboardHistoryPersistenceError.writeFailed(error)
            }
        }
    }

    private struct SQLiteError: LocalizedError {
        let message: String
        var errorDescription: String? { "Clipboard database: \(message)" }
    }

    private func openIfNeeded() throws {
        guard db == nil else { return }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw ClipboardHistoryPersistenceError.corruptArchive(SQLiteError(message: message))
        }
        db = handle
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
        try exec("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS items (
                id TEXT PRIMARY KEY, created_at REAL NOT NULL, kind TEXT NOT NULL, text TEXT, files TEXT,
                signature TEXT NOT NULL, pinned INTEGER NOT NULL DEFAULT 0, source TEXT, position INTEGER NOT NULL
            );
            """)
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw SQLiteError(message: String(cString: sqlite3_errmsg(db))) }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw SQLiteError(message: String(cString: sqlite3_errmsg(db))) }
        return statement
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ text: String?) {
        if let text { sqlite3_bind_text(statement, index, text, -1, Self.transient) } else { sqlite3_bind_null(statement, index) }
    }

    private func write(_ items: [ClipboardHistoryItem]) throws {
        try exec("BEGIN IMMEDIATE")
        do {
            let insert = try prepare("""
                INSERT INTO items (id, created_at, kind, text, files, signature, pinned, source, position) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET pinned = excluded.pinned, position = excluded.position
                """)
            defer { sqlite3_finalize(insert) }
            for (position, item) in items.enumerated() {
                var kind = "text", text: String?, files: String?
                switch item.payload {
                case let .text(value): text = value
                case let .files(urls):
                    kind = "files"
                    files = String(decoding: try JSONEncoder().encode(urls.map(\.path)), as: UTF8.self)
                case let .image(data):
                    kind = "image"
                    let file = imagesURL.appendingPathComponent(item.signature)
                    if FileManager.default.fileExists(atPath: file.path) == false {
                        try data.write(to: file, options: [.atomic])
                        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                    }
                }
                sqlite3_reset(insert)
                bind(insert, 1, item.id)
                sqlite3_bind_double(insert, 2, item.createdAt.timeIntervalSinceReferenceDate)
                bind(insert, 3, kind)
                bind(insert, 4, text)
                bind(insert, 5, files)
                bind(insert, 6, item.signature)
                sqlite3_bind_int(insert, 7, item.isPinned ? 1 : 0)
                bind(insert, 8, item.sourceBundleIdentifier)
                sqlite3_bind_int(insert, 9, Int32(position))
                guard sqlite3_step(insert) == SQLITE_DONE else { throw SQLiteError(message: String(cString: sqlite3_errmsg(db))) }
            }
            try exec("CREATE TEMP TABLE IF NOT EXISTS keep (id TEXT PRIMARY KEY); DELETE FROM keep;")
            let keep = try prepare("INSERT OR IGNORE INTO keep (id) VALUES (?)")
            defer { sqlite3_finalize(keep) }
            for item in items {
                sqlite3_reset(keep)
                bind(keep, 1, item.id)
                guard sqlite3_step(keep) == SQLITE_DONE else { throw SQLiteError(message: String(cString: sqlite3_errmsg(db))) }
            }
            try exec("DELETE FROM items WHERE id NOT IN (SELECT id FROM keep)")
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
        removeOrphanedImages(keeping: Set(items.compactMap { if case .image = $0.payload { $0.signature } else { nil } }))
    }

    private func removeOrphanedImages(keeping signatures: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: imagesURL.path)) ?? []
        for name in files where signatures.contains(name) == false {
            try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(name))
        }
    }

    private func selectAll() throws -> [ClipboardHistoryItem] {
        let statement = try prepare("SELECT id, created_at, kind, text, files, signature, pinned, source FROM items ORDER BY position")
        defer { sqlite3_finalize(statement) }
        func column(_ index: Int32) -> String? { sqlite3_column_text(statement, index).map { String(cString: $0) } }
        var items: [ClipboardHistoryItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = column(0), let kind = column(2), let signature = column(5) else { continue }
            let payload: ClipboardPayload
            switch kind {
            case "text": payload = .text(column(3) ?? "")
            case "files":
                let paths = (try? JSONDecoder().decode([String].self, from: Data((column(4) ?? "[]").utf8))) ?? []
                payload = .files(paths.map { URL(fileURLWithPath: $0) })
            default:
                guard let data = try? Data(contentsOf: imagesURL.appendingPathComponent(signature)) else { continue }
                payload = .image(data)
            }
            items.append(ClipboardHistoryItem(
                id: id,
                payload: payload,
                createdAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 1)),
                sourceBundleIdentifier: column(7),
                isPinned: sqlite3_column_int(statement, 6) != 0
            ))
        }
        return items
    }
}
