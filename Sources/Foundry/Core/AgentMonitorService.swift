import Foundation

enum AgentMonitorService {
    static func collect() -> [AgentSessionCard] {
        let processes = ProcessSnapshot.capture()
        return (openCodeSessions(processes: processes)
            + claudeSessions(processes: processes)
            + cursorSessions(processes: processes)
            + codexSessions(processes: processes)
            + processAgentSessions(processes: processes))
            .deduped()
            .sorted { lhs, rhs in
                if lhs.status.sortPriority != rhs.status.sortPriority { return lhs.status.sortPriority < rhs.status.sortPriority }
                return (lhs.updatedAt ?? lhs.startedAt ?? .distantPast) > (rhs.updatedAt ?? rhs.startedAt ?? .distantPast)
            }
    }

    private static func openCodeSessions(processes: [ProcessInfoRow]) -> [AgentSessionCard] {
        let db = home(".local/share/opencode/opencode.db")
        guard FileManager.default.fileExists(atPath: db) else { return [] }
        let rows = sqlite(db, "select id,title,directory,model,agent,time_created,time_updated,time_archived from session where time_archived is null order by time_updated desc limit 8;")
        guard let opencodeProcess = processes.first(where: { $0.executableName == "opencode" }),
              let row = rows.first,
              row.count >= 7 else { return [] }

        let title = row[1].isEmpty ? "OpenCode Session" : row[1]
        let directory = row[2]
        let updatedAt = date(milliseconds: row[6])
        guard isRecent(updatedAt, within: 60 * 60) else { return [] }
        let model = openCodeModelLabel(row[3])
        let project = directory.lastPathComponent
        return [AgentSessionCard(
            id: "opencode.\(row[0])",
            provider: .opencode,
            title: title,
            subtitle: model ?? row[4].nilIfEmpty ?? "",
            project: project,
            model: model,
            status: .running,
            startedAt: opencodeProcess.startedAt,
            updatedAt: updatedAt,
            openTarget: .terminal(command: "opencode", cwd: directory.isEmpty ? nil : directory)
        )]
    }

    private static func claudeSessions(processes: [ProcessInfoRow]) -> [AgentSessionCard] {
        return processes.compactMap { process in
            guard process.args.contains("--session-id"), process.args.contains("--resume") else { return nil }
            guard isRecent(process.startedAt, within: 60 * 60) else { return nil }
            guard let sessionID = value(after: "--session-id", in: process.args) else { return nil }
            let cwd = cwdFromClaudeArgs(process.args)
            let model = value(after: "--model", in: process.args)
            let title = cwd?.lastPathComponent ?? "Claude Session"
            let subtitle = [model, value(after: "--permission-mode", in: process.args), cwd?.lastPathComponent].compactMap { $0 }.joined(separator: " · ")
            return AgentSessionCard(
                id: "claude.\(sessionID)",
                provider: .claude,
                title: title,
                subtitle: subtitle,
                project: cwd?.lastPathComponent,
                model: model,
                status: .working,
                startedAt: process.startedAt,
                updatedAt: process.startedAt,
                openTarget: .terminal(command: "claude --resume \(sessionID.shellQuoted)", cwd: cwd)
            )
        }
    }

    private static func cursorSessions(processes: [ProcessInfoRow]) -> [AgentSessionCard] {
        let cursorRunning = processes.contains { process in
            process.args.hasPrefix("/Applications/Cursor.app/Contents/MacOS/Cursor") || process.executableName == "cursor-agent"
        }
        guard cursorRunning else { return [] }

        let db = home("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        guard FileManager.default.fileExists(atPath: db) else { return [] }
        let value = sqlite(db, "select value from ItemTable where key='composer.composerHeaders';").first?.first ?? ""
        guard let data = value.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let composers = root["allComposers"] as? [[String: Any]] else { return cursorProcessCards(processes) }
        let workspaces = cursorWorkspaces()

        return composers.prefix(6).compactMap { composer in
            guard (composer["isArchived"] as? Bool) != true else { return nil }
            let id = composer["composerId"] as? String ?? UUID().uuidString
            let title = (composer["name"] as? String)?.nilIfEmpty ?? "Cursor Agent"
            let workspaceID = composer["workspaceId"] as? String
            let folder = workspaceID.flatMap { workspaces[$0] }
            let updatedAt = date(milliseconds: composer["lastUpdatedAt"])
            guard isRecent(updatedAt, within: 60 * 60) || (composer["hasBlockingPendingActions"] as? Bool) == true else { return nil }
            let filesChanged = int(composer["filesChangedCount"]) ?? 0
            let status: AgentSessionStatus
            if (composer["hasBlockingPendingActions"] as? Bool) == true {
                status = .needsInput
            } else if (composer["hasPendingPlan"] as? Bool) == true {
                status = .planning
            } else if (composer["hasUnreadMessages"] as? Bool) == true || filesChanged > 0 {
                status = .reviewReady
            } else {
                status = .recent
            }
            let stats = cursorStats(composer)
            let model = cursorModel(composer)
            let subtitle = [model, composer["subtitle"] as? String, stats, folder?.lastPathComponent].compactMap { $0?.nilIfEmpty }.joined(separator: " · ")
            return AgentSessionCard(
                id: "cursor.\(id)",
                provider: .cursor,
                title: title,
                subtitle: subtitle,
                project: folder?.lastPathComponent,
                model: model,
                status: status,
                startedAt: date(milliseconds: composer["createdAt"]),
                updatedAt: updatedAt,
                openTarget: .application(name: "Cursor", path: "/Applications/Cursor.app", argument: folder)
            )
        }
    }

    private static func codexSessions(processes: [ProcessInfoRow]) -> [AgentSessionCard] {
        let app = processes.first { $0.args.hasPrefix("/Applications/Codex.app/Contents/MacOS/Codex") }
        let server = processes.first { $0.args.contains("/codex app-server") || $0.args.contains("/Codex.app/Contents/Resources/codex app-server") }
        let computerUse = processes.first { $0.args.contains("Codex Computer Use.app") || $0.args.contains("SkyComputerUse") || $0.args.contains("Codex for Chrome") }
        guard let process = app ?? server ?? computerUse else { return [] }
        let thread = codexThread()
        return [AgentSessionCard(
            id: "codex.app",
            provider: .codex,
            title: thread?.title ?? "Codex",
            subtitle: "",
            project: thread?.project,
            model: thread?.model,
            status: .running,
            startedAt: process.startedAt,
            updatedAt: thread?.updatedAt ?? process.startedAt,
            openTarget: .application(name: "Codex", path: "/Applications/Codex.app")
        )]
    }

    private static func codexThread() -> (title: String, project: String?, model: String?, updatedAt: Date?)? {
        let db = home(".codex/sqlite/codex-dev.db")
        guard FileManager.default.fileExists(atPath: db) else { return nil }
        guard let row = sqlite(db, "select display_title,cwd,model_provider,source_detail,source_updated_at from local_thread_catalog order by source_updated_at desc limit 1;").first,
              row.count >= 5,
              let title = row[0].nilIfEmpty else { return nil }
        let updatedAt = TimeInterval(row[4]).map(Date.init(timeIntervalSince1970:))
        guard isRecent(updatedAt, within: 24 * 60 * 60) else { return nil }
        let model = [row[2].nilIfEmpty, row[3].nilIfEmpty].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        return (title, row[1].lastPathComponent, model, updatedAt)
    }

    private static func cursorProcessCards(_ processes: [ProcessInfoRow]) -> [AgentSessionCard] {
        processes.filter { $0.args.hasPrefix("/Applications/Cursor.app/Contents/MacOS/Cursor") || $0.executableName == "cursor-agent" }.prefix(1).map { process in
            AgentSessionCard(id: "cursor.process", provider: .cursor, title: "Cursor", subtitle: "running", project: nil, model: nil, status: .running, startedAt: process.startedAt, updatedAt: process.startedAt, openTarget: .application(name: "Cursor", path: "/Applications/Cursor.app"))
        }
    }

    private static func processAgentSessions(processes: [ProcessInfoRow]) -> [AgentSessionCard] {
        processAgentDescriptors.compactMap { descriptor in
            guard let process = processes.first(where: { descriptor.matches($0) }) else { return nil }
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
                openTarget: descriptor.openTarget
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
            return AgentSessionCard(id: "claude.\(id)", provider: .claude, title: name, subtitle: subtitle, project: cwd?.lastPathComponent, model: nil, status: status, startedAt: startedAt, updatedAt: startedAt, openTarget: .terminal(command: "claude attach \(id.shellQuoted)", cwd: cwd))
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

    private static func cursorWorkspaces() -> [String: String] {
        let root = URL(fileURLWithPath: home("Library/Application Support/Cursor/User/workspaceStorage"))
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

    private static func sqlite(_ db: String, _ sql: String) -> [[String]] {
        run("/usr/bin/sqlite3", ["-readonly", "-separator", "\t", db, sql])
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
            .filter { $0.isEmpty == false && ($0.count > 1 || $0.first?.isEmpty == false) }
    }

    private static func run(_ path: String, _ args: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        let output = LockedDataBuffer()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard chunk.isEmpty == false else { return }
            output.append(chunk)
        }
        do {
            let semaphore = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
                semaphore.signal()
            }
            try process.run()
            if semaphore.wait(timeout: .now() + 2) == .timedOut {
                process.terminate()
                pipe.fileHandleForReading.readabilityHandler = nil
                return ""
            }
            output.append(pipe.fileHandleForReading.readDataToEndOfFile())
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return ""
        }
        return String(data: output.data, encoding: .utf8) ?? ""
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

    private static func isRecent(_ date: Date?, within seconds: TimeInterval) -> Bool {
        guard let date else { return false }
        return Date().timeIntervalSince(date) <= seconds
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

private struct ProcessInfoRow {
    let pid: String
    let startedAt: Date?
    let args: String

    var executableName: String {
        args.split(separator: " ").first.map { URL(fileURLWithPath: String($0)).lastPathComponent } ?? ""
    }
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

private enum ProcessSnapshot {
    static func capture() -> [ProcessInfoRow] {
        let output = runPS()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return output.split(separator: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 6, omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 7 else { return nil }
            let date = formatter.date(from: parts[1...5].joined(separator: " "))
            return ProcessInfoRow(pid: parts[0], startedAt: date, args: parts[6])
        }
    }

    private static func runPS() -> String {
        let process = Process()
        let pipe = Pipe()
        let output = LockedDataBuffer()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,lstart=,args="]
        process.standardOutput = pipe
        process.standardError = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard chunk.isEmpty == false else { return }
            output.append(chunk)
        }
        do {
            let semaphore = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
                semaphore.signal()
            }
            try process.run()
            if semaphore.wait(timeout: .now() + 2) == .timedOut {
                process.terminate()
                pipe.fileHandleForReading.readabilityHandler = nil
                return ""
            }
            output.append(pipe.fileHandleForReading.readDataToEndOfFile())
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return ""
        }
        return String(data: output.data, encoding: .utf8) ?? ""
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }
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
