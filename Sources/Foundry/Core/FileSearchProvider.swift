import CoreServices
import Foundation
import SQLite3

final class FileSearchProvider: CommandProvider, @unchecked Sendable {
    let id = "foundry.files"

    private let database: FileIndexDatabase
    private var watcher: FileEventWatcher?

    init(diagnostics: DiagnosticsService, indexingStatus: IndexingStatusStore) {
        let database = FileIndexDatabase(diagnostics: diagnostics)
        self.database = database

        Task.detached(priority: .utility) { [database, diagnostics, indexingStatus, id] in
            do {
                try await database.open()
                let prunedCount = (try? await database.pruneSkippedPaths()) ?? 0
                if prunedCount > 0 {
                    diagnostics.log("Pruned \(prunedCount) skipped files from index")
                }
                let existingCount = await database.fileCount()
                indexingStatus.setStatus(existingCount > 0 ? "\(existingCount) files" : "indexing files", for: id)

                guard existingCount == 0 else { return }

                let span = diagnostics.startSpan("files.index")
                let scanStartedAt = Date().timeIntervalSince1970
                var total = 0
                let scanner = FileScanner()
                await scanner.scan(onRootStart: { _ in
                }, onChunk: { chunk in
                    guard Task.isCancelled == false else { return false }
                    do {
                        try await database.upsert(chunk)
                        total += chunk.count
                        indexingStatus.setStatus("indexing files: \(total)", for: id)
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
                indexingStatus.setStatus("\(finalCount) files", for: id)
            } catch {
                diagnostics.log("Failed to open file index: \(error.localizedDescription)")
                indexingStatus.setStatus("files unavailable", for: id)
            }
        }

        let roots = FileScanner.fileSearchRoots()
        self.watcher = FileEventWatcher(paths: roots.map(\.path), diagnostics: diagnostics) { [database, indexingStatus, id] paths in
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

    func results(matching query: String) async -> [CommandResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        do {
            let matches = try await database.search(trimmed, limit: 8)
            guard Task.isCancelled == false else { return [] }
            return matches.map { match in
                CommandResult(
                    id: "file.\(match.record.identity)",
                    title: match.record.name,
                    subtitle: match.record.displayLocation,
                    icon: CommandIcon(fallback: match.record.fallbackIcon, filePath: match.record.path),
                    score: match.score,
                    primaryAction: CommandAction(
                        id: "file.\(match.record.identity).open",
                        title: "Open",
                        kind: .openFile(path: match.record.path)
                    ),
                    secondaryActions: []
                )
            }
        } catch {
            return []
        }
    }
}

actor FileIndexDatabase {
    private let diagnostics: DiagnosticsService
    private var db: OpaquePointer?

    init(diagnostics: DiagnosticsService) {
        self.diagnostics = diagnostics
    }

    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/foundry/files.sqlite")
    }

    func open() throws {
        guard db == nil else { return }

        let url = Self.databaseURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var opened: OpaquePointer?
        guard sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw FileIndexDatabaseError.openFailed(String(cString: sqlite3_errmsg(opened)))
        }

        db = opened
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("PRAGMA temp_store=MEMORY")
        try execute("PRAGMA cache_size=-20000")
        try execute("PRAGMA wal_autocheckpoint=1000")
        try execute("CREATE TABLE IF NOT EXISTS files (path TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, stem TEXT NOT NULL, ext TEXT NOT NULL, parent TEXT NOT NULL, display_parent TEXT NOT NULL, fallback_icon TEXT NOT NULL, indexed_at REAL NOT NULL)")
        try execute("CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(path UNINDEXED, name, stem, ext, parent, tokenize='unicode61')")
        try execute("CREATE INDEX IF NOT EXISTS idx_files_name ON files(name)")
    }

    func fileCount() -> Int {
        guard db != nil else { return 0 }
        return (try? intValue("SELECT COUNT(*) FROM files")) ?? 0
    }

    func upsert(_ records: [FileRecord]) throws {
        guard records.isEmpty == false else { return }
        try open()
        try execute("BEGIN IMMEDIATE")

        do {
            let deleteFTS = try Statement(database: requireDB(), sql: "DELETE FROM files_fts WHERE path = ?")
            let insertFile = try Statement(database: requireDB(), sql: "INSERT OR REPLACE INTO files(path, name, stem, ext, parent, display_parent, fallback_icon, indexed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
            let insertFTS = try Statement(database: requireDB(), sql: "INSERT INTO files_fts(path, name, stem, ext, parent) VALUES (?, ?, ?, ?, ?)")
            let now = Date().timeIntervalSince1970

            for record in records {
                guard Task.isCancelled == false else { break }
                try deleteFTS.bind(record.path).stepReset()

                try insertFile
                    .bind(record.path, record.name, record.stem, record.extensionName, record.parent, record.displayLocation, record.fallbackIcon, now)
                    .stepReset()

                try insertFTS
                    .bind(record.path, record.name, record.stem, record.extensionName, record.parent)
                    .stepReset()
            }

            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func delete(paths: [String]) throws {
        guard paths.isEmpty == false else { return }
        try open()
        try execute("BEGIN IMMEDIATE")

        do {
            let deleteFTS = try Statement(database: requireDB(), sql: "DELETE FROM files_fts WHERE path = ?")
            let deleteFile = try Statement(database: requireDB(), sql: "DELETE FROM files WHERE path = ?")

            for path in paths {
                try deleteFTS.bind(path).stepReset()
                try deleteFile.bind(path).stepReset()
            }

            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func applyChanges(paths: [String]) throws {
        try open()
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

        try delete(paths: deletes)
        try upsert(upserts)
        try optimizeStorage(passive: true)
    }

    func deleteRowsNotIndexed(since timestamp: Double) throws {
        try open()
        try execute("BEGIN IMMEDIATE")

        do {
            try execute("DELETE FROM files_fts WHERE path IN (SELECT path FROM files WHERE indexed_at < \(timestamp))")
            try execute("DELETE FROM files WHERE indexed_at < \(timestamp)")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func pruneSkippedPaths() throws -> Int {
        try open()
        let predicate = FileScanner.skippedPathSQLPredicate()
        guard predicate.isEmpty == false else { return 0 }

        try execute("BEGIN IMMEDIATE")

        do {
            try execute("DELETE FROM files_fts WHERE path IN (SELECT path FROM files WHERE \(predicate))")
            try execute("DELETE FROM files WHERE \(predicate)")
            let deletedCount = Int(sqlite3_changes(try requireDB()))
            try execute("COMMIT")
            if deletedCount > 0 {
                try? optimizeStorage(passive: true)
            }
            return deletedCount
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func optimizeStorage(passive: Bool = false) throws {
        try open()
        try execute("INSERT INTO files_fts(files_fts) VALUES('optimize')")
        try execute(passive ? "PRAGMA wal_checkpoint(PASSIVE)" : "PRAGMA wal_checkpoint(TRUNCATE)")
    }

    func search(_ query: String, limit: Int) throws -> [FileMatch] {
        try open()
        let normalized = SearchScoring.normalize(query)
        let tokens = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.isEmpty == false }
        guard tokens.isEmpty == false else { return [] }

        let ftsQuery = tokens.map { "\($0)*" }.joined(separator: " ")
        let sql = """
        SELECT f.path, f.name, f.stem, f.ext, f.parent, f.display_parent, f.fallback_icon, bm25(files_fts) AS rank
        FROM files_fts
        JOIN files f ON f.path = files_fts.path
        WHERE files_fts MATCH ?
        ORDER BY rank
        LIMIT ?
        """

        let statement = try Statement(database: requireDB(), sql: sql)
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

    private func requireDB() throws -> OpaquePointer {
        guard let db else { throw FileIndexDatabaseError.notOpen }
        return db
    }

    private func execute(_ sql: String) throws {
        let db = try requireDB()
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw FileIndexDatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func intValue(_ sql: String) throws -> Int {
        let statement = try Statement(database: requireDB(), sql: sql)
        guard statement.step() == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement.pointer, 0))
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

private struct FileScanner {
    private let chunkSize = 200
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

    func scan(onRootStart: (URL) -> Void, onChunk: ([FileRecord]) async -> Bool) async {
        var chunk: [FileRecord] = []
        chunk.reserveCapacity(chunkSize)
        var seen = Set<String>()
        let roots = Self.fileSearchRoots()
        let priorityRootPaths = Set(roots.dropLast().map { $0.standardizedFileURL.path })

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard Task.isCancelled == false else { return }
            onRootStart(root)
            let rootPath = root.standardizedFileURL.path
            let isWholeDiskPass = rootPath == "/"

            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                guard Task.isCancelled == false else { return }

                let path = url.standardizedFileURL.path
                if isWholeDiskPass, priorityRootPaths.contains(path) {
                    enumerator.skipDescendants()
                    continue
                }

                if shouldSkip(url: url) {
                    enumerator.skipDescendants()
                    continue
                }

                guard isIndexableFile(url: url) else { continue }
                guard seen.insert(path).inserted else { continue }

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

    static func fileSearchRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Developer"),
            home.appendingPathComponent("Code"),
            home.appendingPathComponent("Projects"),
            URL(fileURLWithPath: "/")
        ]

        var seen = Set<String>()
        return candidates.filter { url in
            let standardized = url.standardizedFileURL.path
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
