import CoreServices
import Foundation
import SQLite3

final class FileSearchProvider: CommandProvider, @unchecked Sendable {
    let id = "foundry.files"

    private let database: FileIndexDatabase
    private let diagnostics: DiagnosticsService
    private let indexingStatus: IndexingStatusStore
    private let maintenanceState = FileIndexMaintenanceState()
    private var watcher: FileEventWatcher?

    init(diagnostics: DiagnosticsService, indexingStatus: IndexingStatusStore) {
        let database = FileIndexDatabase(diagnostics: diagnostics)
        self.database = database
        self.diagnostics = diagnostics
        self.indexingStatus = indexingStatus

        Task.detached(priority: .utility) { [database, diagnostics, indexingStatus, maintenanceState, id] in
            await Self.refreshIndex(
                database: database,
                diagnostics: diagnostics,
                indexingStatus: indexingStatus,
                maintenanceState: maintenanceState,
                providerID: id,
                forceFullScan: false
            )
        }

        let roots = FileScanner.fileSearchRoots()
        self.watcher = FileEventWatcher(paths: roots.map(\.url.path), diagnostics: diagnostics) { [database, indexingStatus, id] paths in
            Task.detached(priority: .utility) {
                do {
                    try await database.applyChanges(paths: paths)
                    let count = await database.fileCount()
                    indexingStatus.setStatus("\(count) files", for: id)
                } catch {
                    indexingStatus.setStatus("file index update failed", for: id)
                }
            }
        }
        self.watcher?.start()
    }

    func rebuildIndex() {
        Task.detached(priority: .utility) { [database, diagnostics, indexingStatus, maintenanceState, id] in
            await Self.refreshIndex(
                database: database,
                diagnostics: diagnostics,
                indexingStatus: indexingStatus,
                maintenanceState: maintenanceState,
                providerID: id,
                forceFullScan: true
            )
        }
    }

    func results(matching query: String) async -> [CommandResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        do {
            let matches = try await database.search(trimmed, limit: 8)
            guard Task.isCancelled == false else { return [] }
            return matches.map { match in
                let path = match.record.path
                return CommandResult(
                    id: "file.\(match.record.identity)",
                    title: match.record.name,
                    subtitle: match.record.displayLocation,
                    icon: CommandIcon(fallback: match.record.fallbackIcon, filePath: path),
                    score: match.score,
                    primaryAction: CommandAction(
                        id: "file.\(match.record.identity).open",
                        title: "Open",
                        kind: .openFile(path: path)
                    ),
                    secondaryActions: [
                        CommandAction(id: "file.\(match.record.identity).reveal", title: "Reveal in Finder", kind: .revealInFinder(path: path)),
                        CommandAction(id: "file.\(match.record.identity).copy-path", title: "Copy Path", kind: .copyToClipboard(path))
                    ]
                )
            }
        } catch {
            return []
        }
    }

    private static func refreshIndex(
        database: FileIndexDatabase,
        diagnostics: DiagnosticsService,
        indexingStatus: IndexingStatusStore,
        maintenanceState: FileIndexMaintenanceState,
        providerID: String,
        forceFullScan: Bool
    ) async {
        guard await maintenanceState.tryStart() else {
            diagnostics.log("File index maintenance already running")
            return
        }

        do {
            try await database.open()
            let prunedCount = (try? await database.pruneSkippedPaths()) ?? 0
            if prunedCount > 0 {
                diagnostics.log("Pruned \(prunedCount) skipped files from index")
            }

            let existingCount = await database.fileCount()
            if forceFullScan == false {
                indexingStatus.setStatus(existingCount > 0 ? "\(existingCount) files" : "indexing files", for: providerID)
                guard existingCount == 0 else {
                    await maintenanceState.finish()
                    return
                }
            } else {
                indexingStatus.setStatus("rebuilding file index", for: providerID)
            }

            let span = diagnostics.startSpan(forceFullScan ? "files.rebuild" : "files.index")
            let scanStartedAt = Date().timeIntervalSince1970
            var total = 0
            let shouldReplaceExistingFTS = forceFullScan || existingCount > 0
            let scanner = FileScanner()
            await scanner.scan(onRootStart: { root in
                indexingStatus.setStatus("indexing \(root.label): \(total)", for: providerID)
            }, onChunk: { chunk in
                guard Task.isCancelled == false else { return false }
                do {
                    try await database.upsert(chunk, replaceExistingFTS: shouldReplaceExistingFTS)
                    total += chunk.count
                    indexingStatus.setStatus("indexing files: \(total)", for: providerID)
                    await Task.yield()
                    return true
                } catch {
                    diagnostics.log("Failed to index file chunk: \(error.localizedDescription)")
                    return true
                }
            })

            diagnostics.endSpan(span)
            try? await database.deleteRowsNotIndexed(since: scanStartedAt)
            try? await database.optimizeStorage()
            let finalCount = await database.fileCount()
            diagnostics.log("Indexed \(finalCount) files")
            indexingStatus.setStatus("\(finalCount) files", for: providerID)
            await maintenanceState.finish()
        } catch {
            diagnostics.log("Failed to open file index: \(error.localizedDescription)")
            indexingStatus.setStatus("files unavailable", for: providerID)
            await maintenanceState.finish()
        }
    }
}

private actor FileIndexMaintenanceState {
    private var isRunning = false

    func tryStart() -> Bool {
        guard isRunning == false else { return false }
        isRunning = true
        return true
    }

    func finish() {
        isRunning = false
    }
}

final class FileIndexDatabase: @unchecked Sendable {
    private let diagnostics: DiagnosticsService
    private let openLock = NSLock()
    private let readLock = NSLock()
    private let writeLock = NSLock()
    private var readDB: OpaquePointer?
    private var writeDB: OpaquePointer?

    init(diagnostics: DiagnosticsService) {
        self.diagnostics = diagnostics
    }

    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/foundry/files.sqlite")
    }

    func open() async throws {
        try openLock.withLock {
            guard readDB == nil || writeDB == nil else { return }

            let url = Self.databaseURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

            var openedWriteDB: OpaquePointer?
            guard sqlite3_open_v2(url.path, &openedWriteDB, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let openedWriteDB else {
                throw FileIndexDatabaseError.openFailed(String(cString: sqlite3_errmsg(openedWriteDB)))
            }

            var openedReadDB: OpaquePointer?
            guard sqlite3_open_v2(url.path, &openedReadDB, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let openedReadDB else {
                sqlite3_close(openedWriteDB)
                throw FileIndexDatabaseError.openFailed(String(cString: sqlite3_errmsg(openedReadDB)))
            }

            writeDB = openedWriteDB
            readDB = openedReadDB

            try execute("PRAGMA journal_mode=WAL", database: openedWriteDB)
            try execute("PRAGMA synchronous=NORMAL", database: openedWriteDB)
            try execute("PRAGMA temp_store=MEMORY", database: openedWriteDB)
            try execute("PRAGMA cache_size=-64000", database: openedWriteDB)
            try execute("PRAGMA mmap_size=134217728", database: openedWriteDB)
            try execute("PRAGMA busy_timeout=250", database: openedWriteDB)
            try execute("PRAGMA wal_autocheckpoint=4000", database: openedWriteDB)
            try prepareSchema(database: openedWriteDB)

            try execute("CREATE TABLE IF NOT EXISTS files (id INTEGER PRIMARY KEY, path TEXT UNIQUE NOT NULL, name TEXT NOT NULL, stem TEXT NOT NULL, ext TEXT NOT NULL, parent TEXT NOT NULL, display_parent TEXT NOT NULL, fallback_icon TEXT NOT NULL, indexed_at REAL NOT NULL)", database: openedWriteDB)
            try execute("CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(name, stem, ext, parent, tokenize='unicode61', prefix='2 3 4')", database: openedWriteDB)
            try execute("CREATE INDEX IF NOT EXISTS idx_files_name ON files(name)", database: openedWriteDB)
            try execute("CREATE INDEX IF NOT EXISTS idx_files_path ON files(path)", database: openedWriteDB)
            try execute("PRAGMA user_version=2", database: openedWriteDB)

            try execute("PRAGMA query_only=ON", database: openedReadDB)
            try execute("PRAGMA temp_store=MEMORY", database: openedReadDB)
            try execute("PRAGMA cache_size=-32000", database: openedReadDB)
            try execute("PRAGMA mmap_size=134217728", database: openedReadDB)
            try execute("PRAGMA busy_timeout=100", database: openedReadDB)
        }
    }

    func fileCount() async -> Int {
        do {
            try await open()
            return try readLock.withLock {
                try intValue("SELECT COUNT(*) FROM files", database: requireReadDB())
            }
        } catch {
            return 0
        }
    }

    func upsert(_ records: [FileRecord], replaceExistingFTS: Bool = true) async throws {
        guard records.isEmpty == false else { return }
        try await open()
        try writeLock.withLock {
            let db = try requireWriteDB()
            try execute("BEGIN IMMEDIATE", database: db)

            do {
                let existingID = try Statement(database: db, sql: "SELECT id FROM files WHERE path = ?")
                let deleteFTS = replaceExistingFTS ? try Statement(database: db, sql: "DELETE FROM files_fts WHERE rowid = ?") : nil
                let insertFile = try Statement(database: db, sql: "INSERT INTO files(path, name, stem, ext, parent, display_parent, fallback_icon, indexed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(path) DO UPDATE SET name = excluded.name, stem = excluded.stem, ext = excluded.ext, parent = excluded.parent, display_parent = excluded.display_parent, fallback_icon = excluded.fallback_icon, indexed_at = excluded.indexed_at")
                let insertFTS = try Statement(database: db, sql: "INSERT INTO files_fts(rowid, name, stem, ext, parent) VALUES (?, ?, ?, ?, ?)")
                let now = Date().timeIntervalSince1970

                for record in records {
                    guard Task.isCancelled == false else { break }
                    let previousRowID = try existingID.bind(record.path).int64Value()

                    try insertFile
                        .bind(record.path, record.name, record.stem, record.extensionName, record.parent, record.displayLocation, record.fallbackIcon, now)
                        .stepReset()

                    let rowID = previousRowID ?? sqlite3_last_insert_rowid(db)
                    try deleteFTS?.bind(rowID).stepReset()

                    try insertFTS
                        .bind(rowID, record.name, record.stem, record.extensionName, record.parent)
                        .stepReset()
                }

                try execute("COMMIT", database: db)
            } catch {
                try? execute("ROLLBACK", database: db)
                throw error
            }
        }
    }

    func delete(paths: [String]) async throws {
        guard paths.isEmpty == false else { return }
        try await open()
        try writeLock.withLock {
            let db = try requireWriteDB()
            try execute("BEGIN IMMEDIATE", database: db)

            do {
                let existingID = try Statement(database: db, sql: "SELECT id FROM files WHERE path = ?")
                let deleteFTS = try Statement(database: db, sql: "DELETE FROM files_fts WHERE rowid = ?")
                let deleteFile = try Statement(database: db, sql: "DELETE FROM files WHERE path = ?")

                for path in paths {
                    if let rowID = try existingID.bind(path).int64Value() {
                        try deleteFTS.bind(rowID).stepReset()
                    }
                    try deleteFile.bind(path).stepReset()
                }

                try execute("COMMIT", database: db)
            } catch {
                try? execute("ROLLBACK", database: db)
                throw error
            }
        }
    }

    func applyChanges(paths: [String]) async throws {
        try await open()
        let scanner = FileScanner()
        var upserts: [FileRecord] = []
        var deletes: [String] = []

        for path in Set(paths) {
            guard Task.isCancelled == false else { break }
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                deletes.append(path)
                continue
            }

            if scanner.shouldSkip(url: url) {
                deletes.append(path)
                continue
            }

            if isDirectory.boolValue {
                scanner.scan(root: url) { chunk in
                    upserts.append(contentsOf: chunk)
                    return upserts.count < 5_000
                }
            } else if let record = FileRecord(fileURLIfIndexable: url, scanner: scanner) {
                upserts.append(record)
            }
        }

        try await delete(paths: deletes)
        try await upsert(upserts)
    }

    func deleteRowsNotIndexed(since timestamp: Double) async throws {
        try await open()
        try writeLock.withLock {
            let db = try requireWriteDB()
            try execute("BEGIN IMMEDIATE", database: db)

            do {
                try execute("DELETE FROM files_fts WHERE rowid IN (SELECT id FROM files WHERE indexed_at < \(timestamp))", database: db)
                try execute("DELETE FROM files WHERE indexed_at < \(timestamp)", database: db)
                try execute("COMMIT", database: db)
            } catch {
                try? execute("ROLLBACK", database: db)
                throw error
            }
        }
    }

    func pruneSkippedPaths() async throws -> Int {
        try await open()
        let predicate = FileScanner.skippedPathSQLPredicate()
        guard predicate.isEmpty == false else { return 0 }

        let deletedCount = try writeLock.withLock {
            let db = try requireWriteDB()
            try execute("BEGIN IMMEDIATE", database: db)

            do {
                try execute("DELETE FROM files_fts WHERE rowid IN (SELECT id FROM files WHERE \(predicate))", database: db)
                try execute("DELETE FROM files WHERE \(predicate)", database: db)
                let deletedCount = Int(sqlite3_changes(db))
                try execute("COMMIT", database: db)
                return deletedCount
            } catch {
                try? execute("ROLLBACK", database: db)
                throw error
            }
        }

        if deletedCount > 0 {
            try? await optimizeStorage(passive: true)
        }
        return deletedCount
    }

    func optimizeStorage(passive: Bool = false) async throws {
        try await open()
        try writeLock.withLock {
            let db = try requireWriteDB()
            if passive == false {
                try execute("INSERT INTO files_fts(files_fts) VALUES('optimize')", database: db)
            }
            try execute(passive ? "PRAGMA wal_checkpoint(PASSIVE)" : "PRAGMA wal_checkpoint(TRUNCATE)", database: db)
        }
    }

    func search(_ query: String, limit: Int) async throws -> [FileMatch] {
        try await open()
        let normalized = SearchScoring.normalize(query)
        let tokens = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.isEmpty == false }
        guard tokens.isEmpty == false else { return [] }

        let ftsQuery = tokens.map { "\($0)*" }.joined(separator: " ")
        let sql = """
        SELECT f.path, f.name, f.stem, f.ext, f.parent, f.display_parent, f.fallback_icon, bm25(files_fts) AS rank
        FROM files_fts
        JOIN files f ON f.id = files_fts.rowid
        WHERE files_fts MATCH ?
        ORDER BY rank
        LIMIT ?
        """

        return try readLock.withLock {
            let statement = try Statement(database: requireReadDB(), sql: sql)
            try statement.bind(ftsQuery, limit)

            var matches: [FileMatch] = []
            while statement.step() == SQLITE_ROW {
                guard Task.isCancelled == false else { return [] }
                let record = FileRecord(
                    path: statement.text(at: 0),
                    name: statement.text(at: 1),
                    stem: statement.text(at: 2),
                    extensionName: statement.text(at: 3),
                    parent: statement.text(at: 4),
                    displayLocation: statement.text(at: 5),
                    fallbackIcon: statement.text(at: 6)
                )
                let rank = statement.double(at: 7)
                matches.append(FileMatch(record: record, score: 88 - rank))
            }

            return matches
        }
    }

    private func requireReadDB() throws -> OpaquePointer {
        guard let readDB else { throw FileIndexDatabaseError.notOpen }
        return readDB
    }

    private func requireWriteDB() throws -> OpaquePointer {
        guard let writeDB else { throw FileIndexDatabaseError.notOpen }
        return writeDB
    }

    private func prepareSchema(database: OpaquePointer) throws {
        let version = try intValue("PRAGMA user_version", database: database)
        guard version < 2 else { return }

        diagnostics.log("Migrating file index schema to v2")
        try execute("DROP TABLE IF EXISTS files_fts", database: database)
        try execute("DROP TABLE IF EXISTS files", database: database)
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw FileIndexDatabaseError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func intValue(_ sql: String, database: OpaquePointer) throws -> Int {
        let statement = try Statement(database: database, sql: sql)
        guard statement.step() == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement.pointer, 0))
    }

    deinit {
        if let readDB {
            sqlite3_close(readDB)
        }
        if let writeDB {
            sqlite3_close(writeDB)
        }
    }
}

private final class Statement {
    let pointer: OpaquePointer

    init(database: OpaquePointer, sql: String) throws {
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &prepared, nil) == SQLITE_OK, let prepared else {
            throw FileIndexDatabaseError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        self.pointer = prepared
    }

    deinit {
        finalize()
    }

    func finalize() {
        sqlite3_finalize(pointer)
    }

    @discardableResult
    func bind(_ values: Any...) throws -> Statement {
        sqlite3_clear_bindings(pointer)
        sqlite3_reset(pointer)

        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case let string as String:
                sqlite3_bind_text(pointer, position, string, -1, SQLITE_TRANSIENT)
            case let int64 as Int64:
                sqlite3_bind_int64(pointer, position, sqlite3_int64(int64))
            case let int as Int:
                sqlite3_bind_int64(pointer, position, sqlite3_int64(int))
            case let double as Double:
                sqlite3_bind_double(pointer, position, double)
            default:
                throw FileIndexDatabaseError.unsupportedBinding
            }
        }

        return self
    }

    @discardableResult
    func step() -> Int32 {
        sqlite3_step(pointer)
    }

    func stepReset() throws {
        let result = sqlite3_step(pointer)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw FileIndexDatabaseError.queryFailed("SQLite step failed: \(result)")
        }
        sqlite3_reset(pointer)
    }

    func int64Value() throws -> Int64? {
        let result = sqlite3_step(pointer)
        guard result == SQLITE_ROW else {
            guard result == SQLITE_DONE else {
                throw FileIndexDatabaseError.queryFailed("SQLite step failed: \(result)")
            }
            sqlite3_reset(pointer)
            return nil
        }

        let value = sqlite3_column_int64(pointer, 0)
        sqlite3_reset(pointer)
        return Int64(value)
    }

    func text(at index: Int32) -> String {
        guard let value = sqlite3_column_text(pointer, index) else { return "" }
        return String(cString: value)
    }

    func double(at index: Int32) -> Double {
        sqlite3_column_double(pointer, index)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private enum FileIndexDatabaseError: Error, LocalizedError {
    case openFailed(String)
    case queryFailed(String)
    case notOpen
    case unsupportedBinding

    var errorDescription: String? {
        switch self {
        case let .openFailed(message): "Failed to open SQLite database: \(message)"
        case let .queryFailed(message): "SQLite query failed: \(message)"
        case .notOpen: "SQLite database is not open"
        case .unsupportedBinding: "Unsupported SQLite binding value"
        }
    }
}

private final class FileEventWatcher: @unchecked Sendable {
    private let paths: [String]
    private let diagnostics: DiagnosticsService
    private let onBatch: @Sendable ([String]) -> Void
    private let eventQueue = DispatchQueue(label: "foundry.file-events", qos: .utility)
    private let lock = NSLock()
    private var pendingPaths = Set<String>()
    private var debounceWorkItem: DispatchWorkItem?
    private var stream: FSEventStreamRef?

    init(paths: [String], diagnostics: DiagnosticsService, onBatch: @escaping @Sendable ([String]) -> Void) {
        self.paths = paths
        self.diagnostics = diagnostics
        self.onBatch = onBatch
    }

    func start() {
        guard stream == nil, paths.isEmpty == false else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, eventCount, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileEventWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            watcher.enqueue(Array(paths.prefix(eventCount)))
        }

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream else {
            diagnostics.log("Failed to start file event watcher")
            return
        }

        FSEventStreamSetDispatchQueue(stream, eventQueue)
        if FSEventStreamStart(stream) == false {
            diagnostics.log("File event watcher did not start")
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func enqueue(_ paths: [String]) {
        guard paths.isEmpty == false else { return }

        lock.lock()
        pendingPaths.formUnion(paths)
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.flush()
        }
        debounceWorkItem = workItem
        lock.unlock()

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func flush() {
        lock.lock()
        let paths = Array(pendingPaths)
        pendingPaths.removeAll(keepingCapacity: true)
        lock.unlock()

        guard paths.isEmpty == false else { return }
        onBatch(paths)
    }
}

private struct ScanRoot: Sendable {
    let url: URL
    let label: String
    let isWholeDisk: Bool
}

private struct FileScanner {
    private let chunkSize = 2_000
    private static let skippedNames: Set<String> = [
        ".git", ".svn", ".hg",
        ".build", ".swiftpm", "DerivedData", "target", "dist", "build", "Build",
        "node_modules", "bower_components", "jspm_packages", ".pnpm-store",
        "Pods", "Carthage", "vendor", "Vendor",
        ".venv", "venv", "env", ".env", "virtualenv", "__pypackages__", "site-packages", "__pycache__", ".mypy_cache", ".pytest_cache", ".ruff_cache", ".tox", ".nox",
        ".gradle", ".m2", ".cargo", ".rustup", "pkg", ".pub-cache", "pub-cache", ".dart_tool", ".plugin_symlinks", "ephemeral",
        "Library", "Cache", "Caches", "cache", "tmp", "temp", ".next", ".turbo", ".cache",
        ".Trash", ".Trashes", ".Spotlight-V100", ".fseventsd",
        ".packages", ".flutter-plugins", ".flutter-plugins-dependencies"
    ]
    private static let skippedPathPrefixes = [
        "/dev", "/Network", "/System/Volumes", "/private/tmp", "/private/var", "/tmp", "/var", "/Volumes/.timemachine",
        "/Users/Shared/Relocated Items"
    ]

    func scan(onRootStart: (ScanRoot) -> Void, onChunk: ([FileRecord]) async -> Bool) async {
        var chunk: [FileRecord] = []
        chunk.reserveCapacity(chunkSize)
        let roots = Self.fileSearchRoots()
        let priorityRootPaths = Set(roots.filter { $0.isWholeDisk == false }.map { $0.url.standardizedFileURL.path })

        for root in roots where FileManager.default.fileExists(atPath: root.url.path) {
            guard Task.isCancelled == false else { return }
            onRootStart(root)

            guard let enumerator = FileManager.default.enumerator(
                at: root.url,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                guard Task.isCancelled == false else { return }

                let path = url.standardizedFileURL.path
                if root.isWholeDisk, priorityRootPaths.contains(path) {
                    enumerator.skipDescendants()
                    continue
                }

                if shouldSkip(url: url) {
                    enumerator.skipDescendants()
                    continue
                }

                guard isIndexableFile(url: url) else { continue }

                chunk.append(FileRecord(url: url))
                if chunk.count >= chunkSize {
                    guard await onChunk(chunk) else { return }
                    chunk.removeAll(keepingCapacity: true)
                }
            }

            if chunk.isEmpty == false {
                guard await onChunk(chunk) else { return }
                chunk.removeAll(keepingCapacity: true)
            }
        }

        if chunk.isEmpty == false {
            _ = await onChunk(chunk)
        }
    }

    func scan(root: URL, onChunk: ([FileRecord]) -> Bool) {
        var chunk: [FileRecord] = []
        chunk.reserveCapacity(chunkSize)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return }

        while let url = enumerator.nextObject() as? URL {
            if shouldSkip(url: url) {
                enumerator.skipDescendants()
                continue
            }

            guard isIndexableFile(url: url) else { continue }
            chunk.append(FileRecord(url: url))
            if chunk.count >= chunkSize {
                guard onChunk(chunk) else { return }
                chunk.removeAll(keepingCapacity: true)
            }
        }

        if chunk.isEmpty == false {
            _ = onChunk(chunk)
        }
    }

    static func fileSearchRoots() -> [ScanRoot] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            ScanRoot(url: URL(fileURLWithPath: FileManager.default.currentDirectoryPath), label: "workspace", isWholeDisk: false),
            ScanRoot(url: home.appendingPathComponent("Desktop"), label: "Desktop", isWholeDisk: false),
            ScanRoot(url: home.appendingPathComponent("Downloads"), label: "Downloads", isWholeDisk: false),
            ScanRoot(url: home.appendingPathComponent("Documents"), label: "Documents", isWholeDisk: false),
            ScanRoot(url: home.appendingPathComponent("Developer"), label: "Developer", isWholeDisk: false),
            ScanRoot(url: home.appendingPathComponent("Code"), label: "Code", isWholeDisk: false),
            ScanRoot(url: home.appendingPathComponent("Projects"), label: "Projects", isWholeDisk: false),
            ScanRoot(url: URL(fileURLWithPath: "/"), label: "Mac", isWholeDisk: true)
        ]

        var seen = Set<String>()
        return candidates.filter { root in
            let standardized = root.url.standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: standardized) else { return false }
            return seen.insert(standardized).inserted
        }
    }

    func shouldSkip(url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let name = url.lastPathComponent

        if Self.skippedNames.contains(name) { return true }
        if Self.skippedPathPrefixes.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        if name.hasSuffix(".app") { return true }
        if name.hasSuffix(".xcarchive") { return true }
        if name.hasSuffix(".framework") { return true }
        if name.hasSuffix(".bundle") { return true }
        if name.hasSuffix(".plugin") { return true }
        if name.hasSuffix(".egg-info") { return true }
        if name.hasSuffix(".dist-info") { return true }
        return false
    }

    static func skippedPathSQLPredicate() -> String {
        let namePredicates = skippedNames.map { name in
            "path GLOB '\(sqlStringLiteral("*/\(name)/*"))'"
        }
        let prefixPredicates = skippedPathPrefixes.flatMap { prefix in
            [
                "path = '\(sqlStringLiteral(prefix))'",
                "path GLOB '\(sqlStringLiteral("\(prefix)/*"))'"
            ]
        }
        let exactFilePredicates = [
            "name IN ('.packages', '.flutter-plugins', '.flutter-plugins-dependencies')"
        ]
        let suffixPredicates = [
            "name GLOB '*.app'",
            "name GLOB '*.xcarchive'",
            "name GLOB '*.framework'",
            "name GLOB '*.bundle'",
            "name GLOB '*.plugin'",
            "name GLOB '*.egg-info'",
            "name GLOB '*.dist-info'"
        ]

        return (namePredicates + prefixPredicates + exactFilePredicates + suffixPredicates).joined(separator: " OR ")
    }

    private static func sqlStringLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    func isIndexableFile(url: URL) -> Bool {
        guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]) else { return false }
        if resourceValues.isDirectory == true { return false }
        guard resourceValues.isRegularFile == true else { return false }
        return true
    }
}

struct FileRecord: Sendable, Hashable {
    let path: String
    let name: String
    let stem: String
    let extensionName: String
    let parent: String
    let displayLocation: String
    let fallbackIcon: String

    var identity: String {
        path.replacingOccurrences(of: "/", with: ".")
    }

    init(url: URL) {
        let parent = url.deletingLastPathComponent().path
        self.init(
            path: url.path,
            name: url.lastPathComponent,
            stem: url.deletingPathExtension().lastPathComponent,
            extensionName: url.pathExtension,
            parent: parent,
            displayLocation: Self.displayLocation(for: parent),
            fallbackIcon: url.pathExtension.isEmpty ? "FI" : String(url.pathExtension.uppercased().prefix(3))
        )
    }

    fileprivate init?(fileURLIfIndexable url: URL, scanner: FileScanner) {
        guard scanner.isIndexableFile(url: url), scanner.shouldSkip(url: url) == false else { return nil }
        self.init(url: url)
    }

    init(path: String, name: String, stem: String, extensionName: String, parent: String, displayLocation: String, fallbackIcon: String) {
        self.path = path
        self.name = name
        self.stem = stem
        self.extensionName = extensionName
        self.parent = parent
        self.displayLocation = displayLocation
        self.fallbackIcon = fallbackIcon
    }

    private static func displayLocation(for parent: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if parent == home { return "~" }
        if parent.hasPrefix(home + "/") { return "~" + parent.dropFirst(home.count) }
        return parent
    }
}

struct FileMatch: Sendable, Hashable {
    let record: FileRecord
    let score: Double
}
