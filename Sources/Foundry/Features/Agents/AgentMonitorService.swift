import Foundation
import FoundryServices

enum AgentMonitorService {
    private static let recentSessionWindow: TimeInterval = 24 * 60 * 60
    private static let defaultProcessSnapshotProvider = NativeProcessSnapshotProvider()

    static func collect() -> [AgentSessionCard] {
        var cache = AgentMonitorCache()
        return collect(using: &cache)
    }

    static func collect(using cache: inout AgentMonitorCache) -> [AgentSessionCard] {
        collect(using: &cache, processProvider: defaultProcessSnapshotProvider)
    }

    static func collect(using cache: inout AgentMonitorCache, processProvider: any ProcessSnapshotProviding) -> [AgentSessionCard] {
        let processes = processProvider.capture()
        return (openCodeSessions(processes: processes, cache: &cache)
            + claudeSessions(processes: processes, cache: &cache)
            + cursorSessions(processes: processes, cache: &cache)
            + codexSessions(processes: processes, cache: &cache)
            + processAgentSessions(processes: processes))
            .deduped()
            .map { enrichWithWorkspaceDiff($0, cache: &cache) }
            .sorted { lhs, rhs in
                if lhs.status.sortPriority != rhs.status.sortPriority { return lhs.status.sortPriority < rhs.status.sortPriority }
                return (lhs.updatedAt ?? lhs.startedAt ?? .distantPast) > (rhs.updatedAt ?? rhs.startedAt ?? .distantPast)
            }
    }

    private static func openCodeSessions(processes: [ProcessInfoRow], cache: inout AgentMonitorCache) -> [AgentSessionCard] {
        let rows = openCodeDatabasePaths().flatMap { db in
            let stamp = sourceStamp(for: db)
            if let stamp, let cached = cache.openCode[db], cached.stamp == stamp {
                return cached.rows
            }
            guard let rows = sqlite(db, "select id,title,directory,model,agent,time_created,time_updated,time_archived from session where time_archived is null order by time_updated desc limit 16;") else {
                return cache.openCode[db]?.rows ?? []
            }
            if let stamp {
                cache.openCode[db] = AgentMonitorCachedRows(stamp: stamp, rows: rows)
            }
            return rows
        }
        .sorted {
            let lhsDate = date(milliseconds: $0.count > 6 ? $0[6] : "") ?? .distantPast
            let rhsDate = date(milliseconds: $1.count > 6 ? $1[6] : "") ?? .distantPast
            return lhsDate > rhsDate
        }
        .reduce(into: [[String]]()) { uniqueRows, row in
            guard let id = row.first, uniqueRows.contains(where: { $0.first == id }) == false else { return }
            uniqueRows.append(row)
        }
        .prefix(8)
        return rows.compactMap { row in
            guard row.count >= 7 else { return nil }
            let updatedAt = date(milliseconds: row[6])
            guard isRecent(updatedAt, within: recentSessionWindow) else { return nil }
            let title = row[1].isEmpty ? "OpenCode Session" : row[1]
            let directory = row[2]
            let model = openCodeModelLabel(row[3])
            let matchingProcess = processes.first { process in
                process.executableName == "opencode" && process.args.split(separator: " ").contains(Substring(row[0]))
            }
            return AgentSessionCard(
                id: "opencode.\(row[0])",
                provider: .opencode,
                title: title,
                subtitle: model ?? row[4].nilIfEmpty ?? "",
                project: directory.lastPathComponent,
                workingDirectory: directory.nilIfEmpty,
                model: model,
                status: openCodeCatalogStatus(sessionID: row[0], processes: processes),
                startedAt: matchingProcess?.startedAt,
                updatedAt: updatedAt,
                openTarget: .terminal(command: "opencode", cwd: directory.isEmpty ? nil : directory),
                key: AgentSessionKey(provider: .opencode, rawSessionID: row[0]),
                origin: .catalog,
                capabilities: [.observe, .jumpTerminal]
            )
        }
    }

    static func openCodeCatalogStatus(sessionID: String, processes: [ProcessInfoRow]) -> AgentSessionStatus {
        processes.contains { process in
            process.executableName == "opencode" && process.args.split(separator: " ").contains(Substring(sessionID))
        } ? .running : .recent
    }

    private static func claudeSessions(processes: [ProcessInfoRow], cache: inout AgentMonitorCache) -> [AgentSessionCard] {
        let running: [AgentSessionCard] = processes.compactMap { process in
            guard process.args.contains("--session-id"), process.args.contains("--resume") else { return nil }
            guard isRecent(process.startedAt, within: 60 * 60) else { return nil }
            guard let sessionID = value(after: "--session-id", in: process.args) else { return nil }
            let cwd = cwdFromClaudeArgs(process.args)
            let model = value(after: "--model", in: process.args)
            let title = cwd?.lastPathComponent ?? "Claude Session"
            let subtitle = [model, value(after: "--permission-mode", in: process.args)].compactMap { $0 }.joined(separator: " · ")
            return AgentSessionCard(
                id: "claude.\(sessionID)",
                provider: .claude,
                title: title,
                subtitle: subtitle,
                project: cwd?.lastPathComponent,
                workingDirectory: cwd,
                model: model,
                status: .working,
                startedAt: process.startedAt,
                updatedAt: process.startedAt,
                openTarget: .terminal(command: "claude --resume \(sessionID.shellQuoted)", cwd: cwd),
                capabilities: [.observe, .jumpTerminal]
            )
        }
        return running + claudeHistorySessions(cache: &cache)
    }

    private static func claudeHistorySessions(cache: inout AgentMonitorCache) -> [AgentSessionCard] {
        let historyURL = URL(fileURLWithPath: home(".claude/history.jsonl"))
        guard let stamp = sourceStamp(for: historyURL.path) else { return [] }
        if let cached = cache.claudeHistory, cached.stamp == stamp {
            return cached.cards.filter { isRecent($0.updatedAt, within: 7 * 24 * 60 * 60) }
        }
        guard let data = try? Data(contentsOf: historyURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let cards = claudeHistorySessions(from: text)
        cache.claudeHistory = AgentMonitorCachedCards(stamp: stamp, cards: cards)
        return cards
    }

    static func claudeHistorySessions(from text: String, now: Date = Date()) -> [AgentSessionCard] {
        var latestBySession: [String: ClaudeHistoryEntry] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = line.data(using: .utf8),
                   let entry = try? JSONDecoder().decode(ClaudeHistoryEntry.self, from: data),
                   entry.sessionId.nilIfEmpty != nil,
                   isRecent(date(milliseconds: entry.timestamp), within: 7 * 24 * 60 * 60, now: now),
                   isClaudeProbe(entry) == false else { continue }
            if latestBySession[entry.sessionId]?.timestamp ?? 0 < entry.timestamp {
                latestBySession[entry.sessionId] = entry
            }
        }

        return latestBySession.values
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(16)
            .compactMap { entry in
                let workingDirectory = entry.project.nilIfEmpty
                let project = workingDirectory?.lastPathComponent
                let title = claudeHistoryTitle(entry.display) ?? project ?? "Claude Session"
                let updatedAt = date(milliseconds: entry.timestamp)
                return AgentSessionCard(
                    id: "claude.\(entry.sessionId)",
                    provider: .claude,
                    title: title,
                    subtitle: project ?? "",
                    project: project,
                    workingDirectory: workingDirectory,
                    model: nil,
                    status: .recent,
                    startedAt: nil,
                    updatedAt: updatedAt,
                    openTarget: .terminal(command: "claude --resume \(entry.sessionId.shellQuoted)", cwd: workingDirectory),
                    key: AgentSessionKey(provider: .claude, rawSessionID: entry.sessionId),
                    origin: .catalog,
                    capabilities: [.observe, .jumpTerminal]
                )
            }
    }

    private static func isClaudeProbe(_ entry: ClaudeHistoryEntry) -> Bool {
        let projectPath = URL(fileURLWithPath: entry.project)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
            .lowercased()
        let isCodexBarProbeProject = projectPath.hasSuffix("/library/application support/codexbar/claudeprobe")
        let display = entry.display.trimmingCharacters(in: .whitespacesAndNewlines)
        return isCodexBarProbeProject && display.hasPrefix("/")
    }

    private static func claudeHistoryTitle(_ display: String) -> String? {
        let title = display
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false, title.hasPrefix("/") == false else { return nil }
        return String(title.prefix(80))
    }

    private static func cursorSessions(processes: [ProcessInfoRow], cache: inout AgentMonitorCache) -> [AgentSessionCard] {
        let cursorRunning = processes.contains { process in
            process.args.hasPrefix("/Applications/Cursor.app/Contents/MacOS/Cursor") || process.executableName == "cursor-agent"
        }
        let cursorDatabase = CursorComposerAdapter.defaultDatabaseURL().path
        let composers: [CursorComposerSnapshot]
        if let stamp = sourceStamp(for: cursorDatabase), let cached = cache.cursorComposers, cached.stamp == stamp {
            composers = cached.snapshots
        } else {
            let discovery = CursorComposerAdapter().discoverResult()
            composers = discovery.snapshots
            if discovery.isAvailable, let stamp = sourceStamp(for: cursorDatabase) {
                cache.cursorComposers = AgentMonitorCachedComposers(stamp: stamp, snapshots: composers)
            }
        }
        let workspaceRoot = home("Library/Application Support/Cursor/User/workspaceStorage")
        let workspaces: [String: String]
        if let stamp = sourceStamp(for: workspaceRoot), let cached = cache.cursorWorkspaces, cached.stamp == stamp {
            workspaces = cached.workspaces
        } else {
            workspaces = cursorWorkspaces(root: workspaceRoot)
            if let stamp = sourceStamp(for: workspaceRoot) {
                cache.cursorWorkspaces = AgentMonitorCachedWorkspaces(stamp: stamp, workspaces: workspaces)
            }
        }

        let cards = composers.prefix(8).compactMap { composer -> AgentSessionCard? in
            guard composer.isDraft == false else { return nil }
            let updatedAt = composer.updatedAt ?? composer.createdAt
            guard composer.hasBlockingPendingActions || isRecent(updatedAt, within: recentSessionWindow) else { return nil }
            let title = composer.title?.nilIfEmpty ?? "Cursor Agent"
            let folder = composer.workspaceID.flatMap { workspaces[$0] }
            let status: AgentSessionStatus
            if composer.hasBlockingPendingActions {
                status = .needsInput
            } else if composer.hasPendingPlan {
                status = .planning
            } else if composer.hasUnreadMessages || composer.filesChangedCount > 0 {
                status = .reviewReady
            } else {
                status = .recent
            }
            let activity = cursorActivitySummary(composer)
            let subtitle = activity ?? ""
            return AgentSessionCard(
                id: "cursor.\(composer.id)",
                provider: .cursor,
                title: title,
                subtitle: subtitle,
                project: folder?.lastPathComponent,
                workingDirectory: folder,
                model: nil,
                status: status,
                startedAt: composer.createdAt,
                updatedAt: updatedAt,
                openTarget: .application(name: "Cursor", path: "/Applications/Cursor.app", argument: folder),
                key: AgentSessionKey(provider: .cursor, rawSessionID: composer.id),
                origin: .catalog,
                capabilities: [.observe, .jumpApplication]
            )
        }
        return cards.isEmpty && cursorRunning ? cursorProcessCards(processes) : cards
    }

    private static func cursorActivitySummary(_ composer: CursorComposerSnapshot) -> String? {
        if composer.filesChangedCount > 0 || composer.totalLinesAdded > 0 || composer.totalLinesRemoved > 0 {
            let files = composer.filesChangedCount == 1 ? "1 file" : "\(composer.filesChangedCount) files"
            return "Edited \(files) · +\(composer.totalLinesAdded) −\(composer.totalLinesRemoved)"
        }
        if composer.hasPendingPlan { return "Plan available" }
        if let subtitle = composer.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), subtitle.lowercased().hasPrefix("read ") {
            let fileText = String(subtitle.dropFirst(5))
            let count = fileText.split(separator: ",").count
            return count == 1 ? "Inspected 1 file" : "Inspected \(count) files"
        }
        return composer.subtitle?.nilIfEmpty
    }

    private static func enrichWithWorkspaceDiff(_ card: AgentSessionCard, cache: inout AgentMonitorCache) -> AgentSessionCard {
        guard card.provider != .cursor,
              let directory = card.workingDirectory else { return card }
        let now = Date()
        if let cached = cache.workspaceDiffs[directory], now.timeIntervalSince(cached.checkedAt) < 90 {
            guard let summary = cached.summary else { return card }
            var enriched = card
            enriched.subtitle = summary
            return enriched
        }
        let summary = workspaceDiffSummary(directory: directory)
        cache.workspaceDiffs[directory] = AgentMonitorCachedDiff(checkedAt: now, summary: summary)
        guard let summary else { return card }
        var enriched = card
        enriched.subtitle = summary
        return enriched
    }

    static func workspaceDiffSummary(directory: String) -> String? {
        let gitTimeout: TimeInterval = 10
        let status = run("/usr/bin/git", ["-C", directory, "status", "--porcelain=v1", "--untracked-files=all"], timeout: gitTimeout)
        let statusLines = status.split(whereSeparator: \.isNewline)
        let files = statusLines.count
        guard files > 0 else { return nil }
        let untrackedFiles = statusLines.count { $0.hasPrefix("?? ") }
        let summaries = [
            run("/usr/bin/git", ["-C", directory, "diff", "--shortstat"], timeout: gitTimeout),
            run("/usr/bin/git", ["-C", directory, "diff", "--cached", "--shortstat"], timeout: gitTimeout)
        ]
        let additions = summaries.reduce(0) { $0 + (firstInteger(in: $1, pattern: #"(\d+) insertions?\(\+\)"#) ?? 0) }
        let removals = summaries.reduce(0) { $0 + (firstInteger(in: $1, pattern: #"(\d+) deletions?\(-\)"#) ?? 0) }
        let fileLabel = files == 1 ? "1 file" : "\(files) files"
        let untrackedLabel = untrackedFiles == 0 ? "" : " · \(untrackedFiles) untracked"
        return "Workspace diff · \(fileLabel) · +\(additions) −\(removals)\(untrackedLabel)"
    }

    private static func firstInteger(in value: String, pattern: String) -> Int? {
        guard let match = value.range(of: pattern, options: .regularExpression) else { return nil }
        let number = value[match].split(whereSeparator: { $0 < "0" || $0 > "9" }).first
        return number.flatMap { Int($0) }
    }

    private static func codexSessions(processes: [ProcessInfoRow], cache: inout AgentMonitorCache) -> [AgentSessionCard] {
        let app = processes.first { $0.args.hasPrefix("/Applications/Codex.app/Contents/MacOS/Codex") }
        let server = processes.first { $0.args.contains("/codex app-server") || $0.args.contains("/Codex.app/Contents/Resources/codex app-server") }
        let computerUse = processes.first { $0.args.contains("Codex Computer Use.app") || $0.args.contains("SkyComputerUse") || $0.args.contains("Codex for Chrome") }
        let process = app ?? server ?? computerUse
        let databasePath = CodexDesktopThreadAdapter.latestDatabaseURL()?.path
        let discovery: CodexDesktopDiscoveryResult
        if let databasePath,
           let stamp = sourceStamp(for: databasePath),
           let cached = cache.codexDiscovery,
           cached.stamp == stamp {
            discovery = cached.discovery
        } else {
            discovery = CodexDesktopThreadAdapter().discoverResult()
            if let databasePath, let stamp = sourceStamp(for: databasePath) {
                cache.codexDiscovery = AgentMonitorCachedCodex(stamp: stamp, discovery: discovery)
            }
        }
        let now = Date()
        let snapshots = discovery.snapshots.map { thread -> CodexDesktopThreadSnapshot in
            guard thread.isProcessing || now.timeIntervalSince(thread.updatedAt) <= CodexDesktopThreadAdapter.liveActivityWindow else { return thread }
            let processing = CodexDesktopThreadAdapter.isRolloutProcessing(rolloutPath: thread.rolloutPath, updatedAt: thread.updatedAt, now: now)
            guard processing != thread.isProcessing else { return thread }
            return CodexDesktopThreadSnapshot(
                id: thread.id,
                title: thread.title,
                preview: thread.preview,
                cwd: thread.cwd,
                rolloutPath: thread.rolloutPath,
                createdAt: thread.createdAt,
                updatedAt: thread.updatedAt,
                modelProvider: thread.modelProvider,
                model: thread.model,
                gitBranch: thread.gitBranch,
                threadSource: thread.threadSource,
                isProcessing: processing,
                titleIsPrompt: thread.titleIsPrompt
            )
        }
        guard snapshots.isEmpty == false else {
            guard let process else { return [] }
            return [AgentSessionCard(
                id: "codex.app",
                provider: .codex,
                title: "Codex",
                subtitle: "",
                project: nil,
                model: nil,
                status: .running,
                startedAt: process.startedAt,
                updatedAt: process.startedAt,
                openTarget: .application(name: "Codex", path: "/Applications/Codex.app"),
                capabilities: [.observe, .jumpApplication]
            )]
        }

        return snapshots.filter { thread in
            thread.isProcessing || now.timeIntervalSince(thread.updatedAt) <= recentSessionWindow
        }.map { thread in
            let target: AgentOpenTarget = if let url = URL(string: "codex://threads/\(thread.id)") {
                .deepLink(url)
            } else {
                .application(name: "Codex", path: "/Applications/Codex.app")
            }
            let model = [thread.modelProvider, thread.model].compactMap { $0?.nilIfEmpty }.joined(separator: " · ").nilIfEmpty
            let project = thread.cwd.lastPathComponent
            let detail = [model, thread.gitBranch].compactMap { $0?.nilIfEmpty }.joined(separator: " · ")
            return AgentSessionCard(
                id: "codex.\(thread.id)",
                provider: .codex,
                title: thread.title,
                subtitle: detail,
                project: project,
                workingDirectory: thread.cwd,
                model: model,
                status: thread.isProcessing ? .working : .recent,
                startedAt: thread.createdAt,
                updatedAt: thread.updatedAt,
                openTarget: target,
                key: AgentSessionKey(provider: .codex, rawSessionID: thread.id),
                origin: .catalog,
                capabilities: [.observe, .jumpTask],
                needsTitleGeneration: thread.titleIsPrompt
            )
        }
    }

    private static func cursorProcessCards(_ processes: [ProcessInfoRow]) -> [AgentSessionCard] {
        processes.filter { $0.args.hasPrefix("/Applications/Cursor.app/Contents/MacOS/Cursor") || $0.executableName == "cursor-agent" }.prefix(1).map { process in
            AgentSessionCard(id: "cursor.process", provider: .cursor, title: "Cursor", subtitle: "running", project: nil, model: nil, status: .running, startedAt: process.startedAt, updatedAt: process.startedAt, openTarget: .application(name: "Cursor", path: "/Applications/Cursor.app"), capabilities: [.observe, .jumpApplication])
        }
    }

    private static func processAgentSessions(processes: [ProcessInfoRow]) -> [AgentSessionCard] {
        processAgentDescriptors.compactMap { descriptor in
            guard let process = processes.first(where: { descriptor.matches($0) }) else { return nil }
            let capabilities: AgentSessionCapabilities
            switch descriptor.openTarget {
            case .application:
                capabilities = [.observe, .jumpApplication]
            case .terminal:
                capabilities = [.observe, .jumpTerminal]
            case .deepLink:
                capabilities = [.observe, .jumpTask]
            }
            return AgentSessionCard(
                id: "process.\(descriptor.provider.rawValue.replacingOccurrences(of: " ", with: "-").lowercased())",
                provider: descriptor.provider,
                title: descriptor.title,
                subtitle: process.executableName,
                project: nil,
                model: nil,
                status: .running,
                startedAt: process.startedAt,
                updatedAt: process.startedAt,
                openTarget: descriptor.openTarget,
                capabilities: capabilities
            )
        }
    }

    private static func claudeSessionsFromJSON(_ text: String) -> [AgentSessionCard] {
        guard let data = text.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            let id = (item["id"] as? String) ?? (item["sessionId"] as? String) ?? UUID().uuidString
            let cwd = item["cwd"] as? String
            let state = (item["state"] as? String) ?? (item["status"] as? String)
            let name = (item["name"] as? String)?.nilIfEmpty ?? cwd?.lastPathComponent ?? "Claude Session"
            let waitingFor = item["waitingFor"] as? String
            let status = claudeStatus(state: state, waitingFor: waitingFor)
            let startedAt = date(any: item["startedAt"])
            let subtitle = [waitingFor, state, cwd?.lastPathComponent].compactMap { $0?.nilIfEmpty }.joined(separator: " · ")
            return AgentSessionCard(id: "claude.\(id)", provider: .claude, title: name, subtitle: subtitle, project: cwd?.lastPathComponent, workingDirectory: cwd, model: nil, status: status, startedAt: startedAt, updatedAt: startedAt, openTarget: .terminal(command: "claude attach \(id.shellQuoted)", cwd: cwd), capabilities: [.observe, .jumpTerminal])
        }
    }

    private static func claudeStatus(state: String?, waitingFor: String?) -> AgentSessionStatus {
        if waitingFor?.isEmpty == false { return .needsInput }
        switch state?.lowercased() {
        case "working": return .working
        case "blocked": return .needsInput
        case "done": return .completed
        case "failed": return .failed
        case "stopped": return .idle
        default: return .running
        }
    }

    private static func openCodeModelLabel(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return json.nilIfEmpty }
        let id = object["id"] as? String
        let variant = object["variant"] as? String
        return [id, variant == "none" ? nil : variant].compactMap { $0?.nilIfEmpty }.joined(separator: " ").nilIfEmpty
    }

    private static func cursorStats(_ composer: [String: Any]) -> String? {
        let files = int(composer["filesChangedCount"])
        let added = int(composer["totalLinesAdded"])
        let removed = int(composer["totalLinesRemoved"])
        if let files, files > 0 { return "\(files) files · +\(added ?? 0) -\(removed ?? 0)" }
        return nil
    }

    private static func cursorModel(_ composer: [String: Any]) -> String? {
        for key in ["model", "modelName", "selectedModel", "forceMode"] {
            if let value = composer[key] as? String, let label = value.nilIfEmpty { return label }
        }
        return nil
    }

    private static func cursorWorkspaces(root: String) -> [String: String] {
        let root = URL(fileURLWithPath: root)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [:] }
        var result: [String: String] = [:]
        for entry in entries {
            let file = entry.appendingPathComponent("workspace.json")
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let folder = json["folder"] as? String,
                  let url = URL(string: folder) else { continue }
            result[entry.lastPathComponent] = url.path.removingPercentEncoding ?? url.path
        }
        return result
    }

    private static func sqlite(_ db: String, _ sql: String) -> [[String]]? {
        guard let result = ProcessRunner.runSynchronously(
            path: "/usr/bin/sqlite3",
            arguments: ["-readonly", "-separator", "\t", db, sql]
        ), result.succeeded else { return nil }
        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
            .filter { $0.isEmpty == false && ($0.count > 1 || $0.first?.isEmpty == false) }
    }

    private static func openCodeDatabasePaths() -> [String] {
        [
            home(".local/share/opencode/opencode-local.db"),
            home(".local/share/opencode/opencode.db"),
            home(".local/share/opencode/opencode-ghost-del.db")
        ].filter { FileManager.default.fileExists(atPath: $0) }
    }

    private static func sourceStamp(for path: String) -> AgentSourceStamp? {
        let candidatePaths = [path, "\(path)-wal", "\(path)-shm"]
        let attributes = candidatePaths.compactMap { candidate in
            try? FileManager.default.attributesOfItem(atPath: candidate)
        }
        guard attributes.isEmpty == false,
              let modificationDate = attributes.compactMap({ $0[.modificationDate] as? Date }).max() else { return nil }
        let size = attributes.reduce(UInt64(0)) { total, values in
            total + ((values[.size] as? NSNumber)?.uint64Value ?? 0)
        }
        return AgentSourceStamp(modificationDate: modificationDate, size: size)
    }

    private static func run(_ path: String, _ args: [String], timeout: TimeInterval = 2) -> String {
        guard let result = ProcessRunner.runSynchronously(path: path, arguments: args, timeout: timeout), result.succeeded else { return "" }
        return result.stdout
    }

    private static func home(_ path: String) -> String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path).path
    }

    private static func firstExisting(_ paths: [String]) -> String? {
        paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func date(milliseconds value: String) -> Date? {
        guard let number = Double(value), number > 0 else { return nil }
        return Date(timeIntervalSince1970: number / 1000)
    }

    private static func date(milliseconds value: Any?) -> Date? {
        if let number = value as? Double { return Date(timeIntervalSince1970: number / 1000) }
        if let number = value as? Int { return Date(timeIntervalSince1970: Double(number) / 1000) }
        if let string = value as? String { return date(milliseconds: string) }
        return nil
    }

    private static func date(any value: Any?) -> Date? {
        if let date = date(milliseconds: value), date.timeIntervalSince1970 > 1_000_000_000 { return date }
        if let string = value as? String { return ISO8601DateFormatter().date(from: string) }
        return nil
    }

    private static func isRecent(_ date: Date?, within seconds: TimeInterval, now: Date = Date()) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) <= seconds
    }

    private static func value(after flag: String, in args: String) -> String? {
        let parts = args.split(separator: " ").map(String.init)
        guard let index = parts.firstIndex(of: flag), index + 1 < parts.count else { return nil }
        return parts[index + 1]
    }

    private static func cwdFromClaudeArgs(_ args: String) -> String? {
        guard let resume = value(after: "--resume", in: args) else { return nil }
        let marker = "/.claude/projects/"
        guard let range = resume.range(of: marker) else { return nil }
        let suffix = resume[range.upperBound...].split(separator: "/").first.map(String.init) ?? ""
        guard suffix.isEmpty == false else { return nil }
        return "/" + suffix.replacingOccurrences(of: "-", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        return nil
    }
}

private struct ClaudeHistoryEntry: Decodable {
    let display: String
    let timestamp: Double
    let project: String
    let sessionId: String
}

private struct ProcessAgentDescriptor {
    let provider: AgentProviderKind
    let title: String
    let commandNames: Set<String>
    let appPrefixes: [String]
    let openTarget: AgentOpenTarget

    func matches(_ process: ProcessInfoRow) -> Bool {
        commandNames.contains(process.executableName) || appPrefixes.contains { process.args.hasPrefix($0) }
    }
}

private let processAgentDescriptors: [ProcessAgentDescriptor] = [
    ProcessAgentDescriptor(provider: .gemini, title: "Gemini", commandNames: ["gemini"], appPrefixes: [], openTarget: .terminal(command: "gemini")),
    ProcessAgentDescriptor(provider: .aider, title: "Aider", commandNames: ["aider"], appPrefixes: [], openTarget: .terminal(command: "aider")),
    ProcessAgentDescriptor(provider: .goose, title: "Goose", commandNames: ["goose"], appPrefixes: ["/Applications/Goose.app/Contents/MacOS/Goose"], openTarget: .application(name: "Goose", path: "/Applications/Goose.app")),
    ProcessAgentDescriptor(provider: .amp, title: "Amp", commandNames: ["amp"], appPrefixes: ["/Applications/Amp.app/Contents/MacOS/Amp"], openTarget: .terminal(command: "amp")),
    ProcessAgentDescriptor(provider: .qwen, title: "Qwen", commandNames: ["qwen", "qwen-code"], appPrefixes: [], openTarget: .terminal(command: "qwen")),
    ProcessAgentDescriptor(provider: .t3code, title: "T3 Code", commandNames: ["t3", "t3code"], appPrefixes: ["/Applications/T3 Code.app/Contents/MacOS/T3 Code"], openTarget: .application(name: "T3 Code", path: "/Applications/T3 Code.app")),
    ProcessAgentDescriptor(provider: .synara, title: "Synara", commandNames: ["synara"], appPrefixes: ["/Applications/Synara.app/Contents/MacOS/Synara"], openTarget: .application(name: "Synara", path: "/Applications/Synara.app")),
    ProcessAgentDescriptor(provider: .devin, title: "Devin", commandNames: ["devin"], appPrefixes: ["/Applications/Devin.app/Contents/MacOS/Devin"], openTarget: .terminal(command: "devin")),
    ProcessAgentDescriptor(provider: .factory, title: "Factory Droid", commandNames: ["droid"], appPrefixes: ["/Applications/Factory.app/Contents/MacOS/Factory"], openTarget: .terminal(command: "droid")),
]

protocol AgentMonitorCollecting: Sendable {
    func collect() -> [AgentSessionCard]
}

final class AgentMonitorCollector: @unchecked Sendable, AgentMonitorCollecting {
    private let lock = NSLock()
    private let processProvider: any ProcessSnapshotProviding
    private var cache = AgentMonitorCache()

    init(processProvider: any ProcessSnapshotProviding = NativeProcessSnapshotProvider()) {
        self.processProvider = processProvider
    }

    func collect() -> [AgentSessionCard] {
        lock.lock()
        defer { lock.unlock() }
        return AgentMonitorService.collect(using: &cache, processProvider: processProvider)
    }
}

struct AgentMonitorCache {
    var openCode: [String: AgentMonitorCachedRows] = [:]
    var claudeHistory: AgentMonitorCachedCards?
    var cursorComposers: AgentMonitorCachedComposers?
    var cursorWorkspaces: AgentMonitorCachedWorkspaces?
    var codexDiscovery: AgentMonitorCachedCodex?
    var workspaceDiffs: [String: AgentMonitorCachedDiff] = [:]
}

struct AgentSourceStamp: Equatable {
    let modificationDate: Date
    let size: UInt64
}

struct AgentMonitorCachedRows {
    let stamp: AgentSourceStamp
    let rows: [[String]]
}

struct AgentMonitorCachedCards {
    let stamp: AgentSourceStamp
    let cards: [AgentSessionCard]
}

struct AgentMonitorCachedComposers {
    let stamp: AgentSourceStamp
    let snapshots: [CursorComposerSnapshot]
}

struct AgentMonitorCachedWorkspaces {
    let stamp: AgentSourceStamp
    let workspaces: [String: String]
}

struct AgentMonitorCachedCodex {
    let stamp: AgentSourceStamp
    let discovery: CodexDesktopDiscoveryResult
}

struct AgentMonitorCachedDiff {
    let checkedAt: Date
    let summary: String?
}

private extension Array where Element == AgentSessionCard {
    func deduped() -> [AgentSessionCard] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var lastPathComponent: String? {
        guard isEmpty == false else { return nil }
        return URL(fileURLWithPath: self).lastPathComponent.nilIfEmpty
    }

    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    var sqlEscaped: String {
        replacingOccurrences(of: "'", with: "''")
    }
}
