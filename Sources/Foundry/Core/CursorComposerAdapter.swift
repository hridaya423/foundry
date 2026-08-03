import Foundation

struct CursorComposerSnapshot: Equatable, Sendable {
    let id: String
    let title: String?
    let subtitle: String?
    let workspaceID: String?
    let createdAt: Date?
    let updatedAt: Date?
    let status: String?
    let isDraft: Bool
    let hasBlockingPendingActions: Bool
    let hasPendingPlan: Bool
    let hasUnreadMessages: Bool
    let filesChangedCount: Int
    let totalLinesAdded: Int
    let totalLinesRemoved: Int
}

struct CursorComposerDiscoveryResult: Equatable, Sendable {
    let snapshots: [CursorComposerSnapshot]
    let isAvailable: Bool
}

struct CursorComposerAdapter: Sendable {
    typealias QueryRunner = @Sendable (String, String) -> String?

    private let databaseURL: URL?
    private let queryRunner: QueryRunner

    init(
        databaseURL: URL? = Self.defaultDatabaseURL(),
        queryRunner: @escaping QueryRunner = Self.runSQLite
    ) {
        self.databaseURL = databaseURL
        self.queryRunner = queryRunner
    }

    func discover() -> [CursorComposerSnapshot] {
        discoverResult().snapshots
    }

    func discoverResult() -> CursorComposerDiscoveryResult {
        guard let databaseURL, FileManager.default.fileExists(atPath: databaseURL.path),
              let output = queryRunner(Self.query, databaseURL.path) else {
            return CursorComposerDiscoveryResult(snapshots: [], isAvailable: false)
        }
        return CursorComposerDiscoveryResult(snapshots: Self.snapshots(from: output), isAvailable: true)
    }

    static let query = """
    SELECT hex(json_extract(value, '$.composerId')),
           hex(json_extract(value, '$.name')),
           hex(json_extract(value, '$.subtitle')),
           hex(json_extract(value, '$.workspaceIdentifier.id')),
           json_extract(value, '$.createdAt'),
           json_extract(value, '$.lastUpdatedAt'),
           hex(json_extract(value, '$.status')),
           json_extract(value, '$.isDraft'),
           json_extract(value, '$.hasBlockingPendingActions'),
           json_extract(value, '$.hasPendingPlan'),
           json_extract(value, '$.hasUnreadMessages'),
           COALESCE(json_extract(value, '$.filesChangedCount'), 0),
           COALESCE(json_extract(value, '$.totalLinesAdded'), 0),
           COALESCE(json_extract(value, '$.totalLinesRemoved'), 0)
    FROM cursorDiskKV
    WHERE key LIKE 'composerData:%'
      AND json_valid(value) = 1
      AND json_extract(value, '$.composerId') IS NOT NULL
    ORDER BY CAST(COALESCE(json_extract(value, '$.lastUpdatedAt'), json_extract(value, '$.createdAt'), 0) AS INTEGER) DESC
    LIMIT 32;
    """

    static func snapshots(from output: String) -> [CursorComposerSnapshot] {
        var result: [CursorComposerSnapshot] = []
        var seenIDs: Set<String> = []
        for row in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 14,
                  let id = decodeHex(fields[0], maximum: 256),
                  seenIDs.insert(id).inserted else { continue }
            result.append(CursorComposerSnapshot(
                id: id,
                title: decodeHex(fields[1], maximum: 256).flatMap(nonEmpty),
                subtitle: decodeHex(fields[2], maximum: 512).flatMap(nonEmpty),
                workspaceID: decodeHex(fields[3], maximum: 256).flatMap(nonEmpty),
                createdAt: millisecondsDate(fields[4]),
                updatedAt: millisecondsDate(fields[5]),
                status: decodeHex(fields[6], maximum: 64).flatMap(nonEmpty),
                isDraft: fields[7] == "1",
                hasBlockingPendingActions: fields[8] == "1",
                hasPendingPlan: fields[9] == "1",
                hasUnreadMessages: fields[10] == "1",
                filesChangedCount: Int(fields[11]) ?? 0,
                totalLinesAdded: Int(fields[12]) ?? 0,
                totalLinesRemoved: Int(fields[13]) ?? 0
            ))
        }
        return result
    }

    static func defaultDatabaseURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    private static func runSQLite(query: String, databasePath: String) -> String? {
        let result = ProcessRunner.runSynchronously(
            path: "/usr/bin/sqlite3",
            arguments: ["-readonly", "-separator", "\t", databasePath, query]
        )
        guard let result, result.succeeded else { return nil }
        return result.stdout
    }

    private static func millisecondsDate(_ value: String) -> Date? {
        guard let milliseconds = Double(value), milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    private static func decodeHex(_ value: String, maximum: Int) -> String? {
        guard value.isEmpty == false, value.count.isMultiple(of: 2), value.count <= maximum * 2 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return String(data: Data(bytes), encoding: .utf8)
    }

    private static func nonEmpty(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
