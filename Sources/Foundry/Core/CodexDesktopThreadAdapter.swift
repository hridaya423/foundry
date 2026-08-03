import Foundation

struct CodexDesktopThreadSnapshot: Equatable, Sendable {
    let id: String
    let title: String
    let preview: String?
    let cwd: String
    let rolloutPath: String
    let createdAt: Date
    let updatedAt: Date
    let modelProvider: String?
    let model: String?
    let gitBranch: String?
    let threadSource: String?
    let isProcessing: Bool
    let titleIsPrompt: Bool
}

struct CodexDesktopDiscoveryResult: Equatable, Sendable {
    let snapshots: [CodexDesktopThreadSnapshot]
    let isAvailable: Bool
}

struct CodexDesktopThreadAdapter: Sendable {
    typealias QueryRunner = @Sendable (String, String) -> String?
    typealias ActivityResolver = @Sendable (String, Date, Date) -> Bool

    static let defaultMaximumThreads = 80
    static let liveActivityWindow: TimeInterval = 45
    static let sqliteSeparator = "\u{1F}"

    private let databaseURL: URL?
    private let maximumThreads: Int
    private let now: @Sendable () -> Date
    private let queryRunner: QueryRunner
    private let activityResolver: ActivityResolver

    init(
        databaseURL: URL? = Self.latestDatabaseURL(),
        maximumThreads: Int = Self.defaultMaximumThreads,
        now: @escaping @Sendable () -> Date = Date.init,
        queryRunner: @escaping QueryRunner = Self.runSQLite,
        activityResolver: @escaping ActivityResolver = Self.isRolloutProcessing
    ) {
        self.databaseURL = databaseURL
        self.maximumThreads = min(max(maximumThreads, 1), 128)
        self.now = now
        self.queryRunner = queryRunner
        self.activityResolver = activityResolver
    }

    func discoverResult() -> CodexDesktopDiscoveryResult {
        guard let databaseURL, FileManager.default.fileExists(atPath: databaseURL.path) else {
            return CodexDesktopDiscoveryResult(snapshots: [], isAvailable: false)
        }
        guard let output = queryRunner(Self.threadsQuery(limit: maximumThreads), databaseURL.path) else {
            return CodexDesktopDiscoveryResult(snapshots: [], isAvailable: false)
        }
        return CodexDesktopDiscoveryResult(
            snapshots: Self.snapshots(
                fromSQLiteOutput: output,
                now: now(),
                maximumThreads: maximumThreads,
                activityResolver: activityResolver
            ),
            isAvailable: true
        )
    }

    static func threadsQuery(limit: Int = defaultMaximumThreads) -> String {
        let boundedLimit = min(max(limit, 1), 128)
        return """
        SELECT substr(hex(id), 1, 512), substr(hex(rollout_path), 1, 8192), COALESCE(created_at_ms, created_at * 1000),
               COALESCE(updated_at_ms, updated_at * 1000), substr(hex(title), 1, 320), substr(hex(cwd), 1, 8192),
               archived, substr(hex(model_provider), 1, 320), substr(hex(model), 1, 320), substr(hex(git_branch), 1, 320),
               substr(hex(first_user_message), 1, 8000), substr(hex(preview), 1, 8000), substr(hex(thread_source), 1, 320)
        FROM threads
        WHERE source = 'vscode' AND archived = 0
          AND (title <> '' OR preview <> '' OR first_user_message <> '')
        ORDER BY COALESCE(recency_at_ms, updated_at_ms, updated_at * 1000) DESC
        LIMIT \(boundedLimit);
        """
    }

    static func snapshots(
        fromSQLiteOutput output: String,
        now: Date,
        maximumThreads: Int = defaultMaximumThreads,
        activityResolver: @escaping ActivityResolver = Self.isRolloutProcessing
    ) -> [CodexDesktopThreadSnapshot] {
        var result: [CodexDesktopThreadSnapshot] = []
        var seenIDs: Set<String> = []
        let maximum = min(max(maximumThreads, 1), 128)

        for row in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard result.count < maximum else { break }
            let fields = row.split(separator: Character(sqliteSeparator), omittingEmptySubsequences: false)
            guard fields.count >= 13,
                  let id = decodeHex(String(fields[0]), maximum: 256),
                  let rolloutPath = decodeHex(String(fields[1]), maximum: 4_096),
                  let titleValue = decodeHex(String(fields[4]), maximum: 160),
                  let cwd = decodeHex(String(fields[5]), maximum: 4_096),
                  let createdAt = unixMillisecondsDate(String(fields[2])),
                  let updatedAt = unixMillisecondsDate(String(fields[3])),
                  seenIDs.insert(id).inserted else {
                continue
            }
            let title = firstDisplayLine(titleValue)
                ?? decodeHex(String(fields[10]), maximum: 160).flatMap(firstDisplayLine)
                ?? "Codex thread"
            let firstUserMessage = decodeHex(String(fields[10]), maximum: 4_000).flatMap(firstDisplayLine)
            let preview = decodeHex(String(fields[11]), maximum: 4_000).flatMap(firstDisplayLine)
                ?? decodeHex(String(fields[10]), maximum: 4_000).flatMap(firstDisplayLine)
            result.append(CodexDesktopThreadSnapshot(
                id: id,
                title: title,
                preview: preview,
                cwd: cwd,
                rolloutPath: rolloutPath,
                createdAt: createdAt,
                updatedAt: updatedAt,
                modelProvider: decodeHex(String(fields[7]), maximum: 160).flatMap(nonEmpty),
                model: decodeHex(String(fields[8]), maximum: 160).flatMap(nonEmpty),
                gitBranch: decodeHex(String(fields[9]), maximum: 160).flatMap(nonEmpty),
                threadSource: decodeHex(String(fields[12]), maximum: 160).flatMap(nonEmpty),
                isProcessing: activityResolver(rolloutPath, updatedAt, now),
                titleIsPrompt: firstUserMessage != nil && normalizedForComparison(title) == normalizedForComparison(firstUserMessage!)
            ))
        }
        return result
    }

    static func isRolloutProcessing(rolloutPath: String, updatedAt: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(updatedAt)
        guard age >= -5, age <= liveActivityWindow,
              let handle = FileHandle(forReadingAtPath: rolloutPath) else {
            return false
        }
        defer { try? handle.close() }
        let byteLimit = 96 * 1_024
        guard let end = try? handle.seekToEnd() else { return false }
        let start = end > UInt64(byteLimit) ? end - UInt64(byteLimit) : 0
        try? handle.seek(toOffset: start)
        let data = handle.readData(ofLength: Int(end - start))
        guard data.isEmpty == false else { return false }

        var terminal: Bool?
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  let type = payload["type"] as? String else {
                continue
            }
            switch type {
            case "task_complete", "turn_aborted", "task_failed":
                terminal = true
            case "task_started", "turn_started", "agent_reasoning", "reasoning", "function_call",
                 "function_call_output", "custom_tool_call", "custom_tool_call_output", "message", "token_count":
                terminal = false
            default:
                continue
            }
        }
        return terminal == false
    }

    static func latestDatabaseURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let root = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        let roots = [root, root.appendingPathComponent("sqlite", isDirectory: true)]
        let candidates = roots.flatMap { directory -> [URL] in
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ))?.filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" } ?? []
        }
        return candidates.max { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }
    }

    private static func runSQLite(query: String, databasePath: String) -> String? {
        let result = ProcessRunner.runSynchronously(
            path: "/usr/bin/sqlite3",
            arguments: ["-readonly", "-separator", sqliteSeparator, databasePath, query]
        )
        guard let result, result.succeeded else { return nil }
        return result.stdout
    }

    private static func unixMillisecondsDate(_ raw: String) -> Date? {
        guard let milliseconds = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              milliseconds > 0, milliseconds.isFinite else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    private static func decodeHex(_ value: String, maximum: Int) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
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
        return String(data: Data(bytes), encoding: .utf8).flatMap(nonEmpty)
    }

    private static func firstDisplayLine(_ value: String) -> String? {
        nonEmpty(value.components(separatedBy: .newlines).first ?? value)
    }

    private static func nonEmpty(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func normalizedForComparison(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
