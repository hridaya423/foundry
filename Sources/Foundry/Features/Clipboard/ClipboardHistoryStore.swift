import Foundation
import FoundryServices
import SQLite3
import os

final class ClipboardHistoryStore: ClipboardHistoryPersisting, Sendable {
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/foundry")
    }

    let databaseURL: URL
    let imagesURL: URL
    private let legacyURL: URL
    /// The SQLite handle is the lock state — every access happens inside
    /// `withLockUnchecked`, mirroring the previous NSLock discipline.
    private let lock = OSAllocatedUnfairLock<OpaquePointer?>(uncheckedState: nil)

    init(directory: URL = ClipboardHistoryStore.defaultDirectory, legacyURL: URL = ClipboardHistoryPersistence().url) {
        databaseURL = directory.appendingPathComponent("clipboard.sqlite")
        imagesURL = directory.appendingPathComponent("clipboard-images", isDirectory: true)
        self.legacyURL = legacyURL
    }

    deinit { _ = lock.withLockUnchecked { sqlite3_close($0) } }

    func load() throws -> [ClipboardHistoryItem] {
        try lock.withLockUnchecked { db in
            try openIfNeeded(&db)
            var items = try selectAll(db)
            if items.isEmpty, FileManager.default.fileExists(atPath: legacyURL.path) {
                let legacy: [ClipboardHistoryItem]
                do { legacy = try JSONDecoder().decode([ClipboardHistoryItem].self, from: Data(contentsOf: legacyURL)) }
                catch { throw ClipboardHistoryPersistenceError.corruptArchive(error) }
                try write(legacy, db: db)
                let migrated = legacyURL.appendingPathExtension("migrated")
                BestEffort.attempt("clipboard migration cleanup") { try FileManager.default.removeItem(at: migrated) }
                try FileManager.default.moveItem(at: legacyURL, to: migrated)
                items = try selectAll(db)
            }
            return items
        }
    }

    func save(_ items: [ClipboardHistoryItem]) throws {
        try lock.withLockUnchecked { db in
            do {
                try openIfNeeded(&db)
                try write(items, db: db)
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

    private func openIfNeeded(_ db: inout OpaquePointer?) throws {
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
        BestEffort.attempt("chmod clipboard database") {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
        }
        try exec(db, """
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS items (
                id TEXT PRIMARY KEY, created_at REAL NOT NULL, kind TEXT NOT NULL, text TEXT, files TEXT,
                signature TEXT NOT NULL, pinned INTEGER NOT NULL DEFAULT 0, source TEXT, position INTEGER NOT NULL
            );
            """)
    }

    private func exec(_ db: OpaquePointer?, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw SQLiteError(message: String(cString: sqlite3_errmsg(db))) }
    }

    private func prepare(_ db: OpaquePointer?, _ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw SQLiteError(message: String(cString: sqlite3_errmsg(db))) }
        return statement
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ text: String?) {
        if let text { sqlite3_bind_text(statement, index, text, -1, Self.transient) } else { sqlite3_bind_null(statement, index) }
    }

    private func write(_ items: [ClipboardHistoryItem], db: OpaquePointer?) throws {
        try exec(db, "BEGIN IMMEDIATE")
        var deletedRows = 0
        do {
            // Diff against what is already stored — a routine capture touches
            // one row, not the whole history.
            let existing = try storedStates(db)
            let insert = try prepare(db, """
                INSERT INTO items (id, created_at, kind, text, files, signature, pinned, source, position) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """)
            defer { sqlite3_finalize(insert) }
            let updateRow = try prepare(db, "UPDATE items SET pinned = ?, position = ? WHERE id = ?")
            defer { sqlite3_finalize(updateRow) }
            for (position, item) in items.enumerated() {
                guard let stored = existing[item.id] else {
                    var kind = "text", text: String?, files: String?
                    switch item.payload {
                    case let .text(value): text = value
                    case let .files(urls):
                        kind = "files"
                        files = String(decoding: try JSONEncoder().encode(urls.map(\.path)), as: UTF8.self)
                    case let .image(data):
                        kind = "image"
                        // Lazily-loaded rows carry no bytes — the file on
                        // disk is the data. Write it only when it is new.
                        let file = imagesURL.appendingPathComponent(item.signature)
                        if data.isEmpty == false, FileManager.default.fileExists(atPath: file.path) == false {
                            try data.write(to: file, options: [.atomic])
                            BestEffort.attempt("chmod clipboard image") {
                                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                            }
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
                    continue
                }
                if stored.pinned != (item.isPinned ? 1 : 0) || stored.position != position {
                    sqlite3_reset(updateRow)
                    sqlite3_bind_int(updateRow, 1, item.isPinned ? 1 : 0)
                    sqlite3_bind_int(updateRow, 2, Int32(position))
                    bind(updateRow, 3, item.id)
                    guard sqlite3_step(updateRow) == SQLITE_DONE else { throw SQLiteError(message: String(cString: sqlite3_errmsg(db))) }
                }
            }
            try exec(db, "CREATE TEMP TABLE IF NOT EXISTS keep (id TEXT PRIMARY KEY); DELETE FROM keep;")
            let keep = try prepare(db, "INSERT OR IGNORE INTO keep (id) VALUES (?)")
            defer { sqlite3_finalize(keep) }
            for item in items {
                sqlite3_reset(keep)
                bind(keep, 1, item.id)
                guard sqlite3_step(keep) == SQLITE_DONE else { throw SQLiteError(message: String(cString: sqlite3_errmsg(db))) }
            }
            try exec(db, "DELETE FROM items WHERE id NOT IN (SELECT id FROM keep)")
            deletedRows = Int(sqlite3_changes(db))
            try exec(db, "COMMIT")
        } catch {
            BestEffort.attempt("clipboard history rollback") { try exec(db, "ROLLBACK") }
            throw error
        }
        if deletedRows > 0 {
            removeOrphanedImages(keeping: Set(items.compactMap { if case .image = $0.payload { $0.signature } else { nil } }))
        }
    }

    private func storedStates(_ db: OpaquePointer?) throws -> [String: (pinned: Int, position: Int)] {
        let statement = try prepare(db, "SELECT id, pinned, position FROM items")
        defer { sqlite3_finalize(statement) }
        var rows: [String: (pinned: Int, position: Int)] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                rows[String(cString: text)] = (Int(sqlite3_column_int(statement, 1)), Int(sqlite3_column_int(statement, 2)))
            }
        }
        return rows
    }

    /// Image bytes live on disk, keyed by content signature — hydrate on
    /// demand instead of holding every screenshot ever copied in memory.
    func imageData(signature: String) throws -> Data? {
        try lock.withLockUnchecked { db in
            try openIfNeeded(&db)
            return BestEffort.attempt("read clipboard image") {
                try Data(contentsOf: imagesURL.appendingPathComponent(signature))
            }
        }
    }

    private func removeOrphanedImages(keeping signatures: Set<String>) {
        let files = FileManager.default.contentsOfDirectoryIfPresent(atPath: imagesURL.path) ?? []
        for name in files where signatures.contains(name) == false {
            try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(name))
        }
    }

    /// Number of image payloads hydrated eagerly on load — the rest carry
    /// an empty placeholder and are read from disk on demand.
    static let eagerImageLimit = 24

    private func selectAll(_ db: OpaquePointer?) throws -> [ClipboardHistoryItem] {
        let statement = try prepare(db, "SELECT id, created_at, kind, text, files, signature, pinned, source FROM items ORDER BY position")
        defer { sqlite3_finalize(statement) }
        func column(_ index: Int32) -> String? { sqlite3_column_text(statement, index).map { String(cString: $0) } }
        var items: [ClipboardHistoryItem] = []
        var hydratedImages = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = column(0), let kind = column(2), let signature = column(5) else { continue }
            let payload: ClipboardPayload
            switch kind {
            case "text": payload = .text(column(3) ?? "")
            case "files":
                let paths = BestEffort.attempt("decode clipboard file paths") {
                    try JSONDecoder().decode([String].self, from: Data((column(4) ?? "[]").utf8))
                } ?? []
                payload = .files(paths.map { URL(fileURLWithPath: $0) })
            default:
                hydratedImages += 1
                if hydratedImages <= Self.eagerImageLimit,
                   let data = BestEffort.attempt("hydrate clipboard image", {
                       try Data(contentsOf: imagesURL.appendingPathComponent(signature))
                   }) {
                    payload = .image(data)
                } else {
                    payload = .image(Data())
                }
            }
            items.append(ClipboardHistoryItem(
                id: id,
                payload: payload,
                createdAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 1)),
                sourceBundleIdentifier: column(7),
                isPinned: sqlite3_column_int(statement, 6) != 0,
                signature: signature
            ))
        }
        return items
    }
}
