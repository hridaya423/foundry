import Foundation

struct AgentIntegrationStatus: Equatable, Sendable {
    let provider: AgentBridgeProvider
    let path: URL
    let installed: Bool
    let detail: String?
}

enum AgentIntegrationInstallError: LocalizedError, Equatable {
    case invalidSettingsStructure(URL)
    case invalidSettingsJSON(URL)
    case existingPlugin(URL)
    case unsupportedPluginPath(URL)

    var errorDescription: String? {
        switch self {
        case let .invalidSettingsStructure(url): "The provider settings structure is not supported: \(url.path)"
        case let .invalidSettingsJSON(url): "The provider settings file is not valid JSON: \(url.path)"
        case let .existingPlugin(url): "An unrelated OpenCode plugin already exists at \(url.path)"
        case let .unsupportedPluginPath(url): "The OpenCode plugin path is not a regular file: \(url.path)"
        }
    }
}

struct AgentIntegrationInstaller: Sendable {
    static let claudeHookArgument = "--agent-bridge"
    static let managedOpenCodeMarker = "foundry-agent-bridge-v2"
    static let legacyOpenCodeMarker = "foundry-agent-bridge-v1"
    static let managedCodexScriptMarker = "foundry-codex-bridge-v1"
    static let managedCursorCommandMarker = "--agent-bridge cursor"

    let homeDirectory: URL
    let executableURL: URL

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        executableURL: URL = AgentIntegrationInstaller.defaultExecutableURL
    ) {
        self.homeDirectory = homeDirectory
        self.executableURL = executableURL
    }

    static var defaultExecutableURL: URL {
        Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    }

    var claudeSettingsURL: URL {
        homeDirectory.appendingPathComponent(".claude/settings.json")
    }

    var openCodePluginURL: URL {
        homeDirectory.appendingPathComponent(".config/opencode/plugins/foundry-agent-bridge.js")
    }

    var codexHooksURL: URL { homeDirectory.appendingPathComponent(".codex/hooks.json") }
    var codexConfigURL: URL { homeDirectory.appendingPathComponent(".codex/config.toml") }
    var codexScriptURL: URL { homeDirectory.appendingPathComponent(".codex/hooks/foundry-agent-bridge.sh") }
    var cursorHooksURL: URL { homeDirectory.appendingPathComponent(".cursor/hooks.json") }

    func status(for provider: AgentBridgeProvider) -> AgentIntegrationStatus {
        switch provider {
        case .claude:
            guard FileManager.default.fileExists(atPath: claudeSettingsURL.path) else {
                return AgentIntegrationStatus(provider: provider, path: claudeSettingsURL, installed: false, detail: nil)
            }
            guard let root = try? loadJSON(at: claudeSettingsURL), let hooks = root["hooks"] as? [String: Any] else {
                return AgentIntegrationStatus(provider: provider, path: claudeSettingsURL, installed: false, detail: "Settings file could not be inspected")
            }
            let installed = Self.claudeHookEvents.allSatisfy { event in
                guard let groups = hooks[event] as? [Any] else { return false }
                return groups.contains { group in
                    guard let group = group as? [String: Any], let handlers = group["hooks"] as? [Any] else { return false }
                    return handlers.contains { handler in
                        guard let handler = handler as? [String: Any],
                              handler["type"] as? String == "command",
                              handler["args"] as? [String] == [Self.claudeHookArgument, AgentBridgeProvider.claude.rawValue] else { return false }
                        return handler["command"] as? String == executableURL.path  
                    }
                }
            }
            return AgentIntegrationStatus(provider: provider, path: claudeSettingsURL, installed: installed, detail: nil)
        case .opencode:
            guard let data = try? Data(contentsOf: openCodePluginURL), let content = String(data: data, encoding: .utf8) else {
                return AgentIntegrationStatus(provider: provider, path: openCodePluginURL, installed: false, detail: nil)
            }
            let installed = Self.isManagedOpenCodePlugin(content)
            return AgentIntegrationStatus(provider: provider, path: openCodePluginURL, installed: installed, detail: installed ? nil : "An unrelated plugin occupies this path")
        case .codex:
            let scriptInstalled = (try? String(contentsOf: codexScriptURL, encoding: .utf8))?.contains(Self.managedCodexScriptMarker) == true
            let hookInstalled = (try? loadJSON(at: codexHooksURL)).map(codexHooksContainManaged) == true
            let featureEnabled = (try? String(contentsOf: codexConfigURL, encoding: .utf8)).map(Self.codexHooksFeatureEnabled) == true
            return AgentIntegrationStatus(provider: provider, path: codexHooksURL, installed: scriptInstalled && hookInstalled && featureEnabled, detail: nil)
        case .cursor:
            let installed = (try? loadJSON(at: cursorHooksURL)).map(cursorHooksContainManaged) == true
            return AgentIntegrationStatus(provider: provider, path: cursorHooksURL, installed: installed, detail: nil)
        }
    }

    func install(_ provider: AgentBridgeProvider) throws {
        switch provider {
        case .claude:
            try installClaude()
        case .opencode:
            try installOpenCode()
        case .codex:
            try installCodex()
        case .cursor:
            try installCursor()
        }
    }

    private func installCodex() throws {
        let scriptDirectory = codexScriptURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        try codexScriptSource.write(to: codexScriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: codexScriptURL.path)

        var root = FileManager.default.fileExists(atPath: codexHooksURL.path) ? try loadJSON(at: codexHooksURL) : [:]
        let hooks: [String: Any]
        if let existing = root["hooks"] as? [String: Any] {
            hooks = existing
        } else if root["hooks"] == nil {
            hooks = [:]
        } else {
            throw AgentIntegrationInstallError.invalidSettingsStructure(codexHooksURL)
        }
        var updatedHooks = hooks
        for (event, matcher) in [("SessionStart", "startup|resume"), ("UserPromptSubmit", nil), ("Stop", nil)] as [(String, String?)] {
            guard updatedHooks[event] == nil || updatedHooks[event] is [[String: Any]] else {
                throw AgentIntegrationInstallError.invalidSettingsStructure(codexHooksURL)
            }
            let current = updatedHooks[event] as? [[String: Any]] ?? []
            let filtered = current.compactMap { pruneManagedCodexHandlers(from: $0) }
            var group: [String: Any] = ["hooks": [["type": "command", "command": codexScriptURL.path, "timeout": event == "Stop" ? 30 : 2]]]
            if let matcher { group["matcher"] = matcher }
            updatedHooks[event] = filtered + [group]
        }
        root["hooks"] = updatedHooks
        try writeJSON(root, to: codexHooksURL)

        let existing = (try? String(contentsOf: codexConfigURL, encoding: .utf8)) ?? ""
        let updated = Self.upsertCodexHooksFeature(existing)
        try FileManager.default.createDirectory(at: codexConfigURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try updated.write(to: codexConfigURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: codexConfigURL.path)
    }

    private func installCursor() throws {
        var root = FileManager.default.fileExists(atPath: cursorHooksURL.path) ? try loadJSON(at: cursorHooksURL) : [:]
        root["version"] = root["version"] ?? 1
        var hooks: [String: Any]
        if let existing = root["hooks"] as? [String: Any] {
            hooks = existing
        } else if root["hooks"] == nil {
            hooks = [:]
        } else {
            throw AgentIntegrationInstallError.invalidSettingsStructure(cursorHooksURL)
        }
        let command = "\(Self.shellQuote(executableURL.path)) --agent-bridge cursor || printf '%s' '{\"continue\":true}'"
        for event in Self.cursorHookEvents {
            guard hooks[event] == nil || hooks[event] is [[String: Any]] else {
                throw AgentIntegrationInstallError.invalidSettingsStructure(cursorHooksURL)
            }
            let current = hooks[event] as? [[String: Any]] ?? []
            hooks[event] = current.filter { !isManagedCursorHandler($0) } + [["command": command, "timeout": 3]]
        }
        for event in ["beforeShellExecution", "beforeMCPExecution"] {
            guard let current = hooks[event] as? [[String: Any]] else { continue }
            let filtered = current.filter { !isManagedCursorHandler($0) }
            if filtered.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = filtered }
        }
        root["hooks"] = hooks
        try writeJSON(root, to: cursorHooksURL)
    }

    private func installClaude() throws {
        var root: [String: Any]
        if FileManager.default.fileExists(atPath: claudeSettingsURL.path) {
            root = try loadJSON(at: claudeSettingsURL)
        } else {
            root = [:]
        }

        var hooks: [String: Any]
        if let existing = root["hooks"] as? [String: Any] {
            hooks = existing
        } else if root["hooks"] == nil {
            hooks = [:]
        } else {
            throw AgentIntegrationInstallError.invalidSettingsStructure(claudeSettingsURL)
        }

        for event in Self.claudeHookEvents {
            let existingGroups: [Any]
            if let groups = hooks[event] as? [Any] {
                existingGroups = groups
            } else if hooks[event] == nil {
                existingGroups = []
            } else {
                throw AgentIntegrationInstallError.invalidSettingsStructure(claudeSettingsURL)
            }
            var cleanedGroups: [[String: Any]] = []
            for rawGroup in existingGroups {
                guard var group = rawGroup as? [String: Any] else {
                    throw AgentIntegrationInstallError.invalidSettingsStructure(claudeSettingsURL)
                }
                guard let rawHandlers = group["hooks"] as? [Any] else {
                    cleanedGroups.append(group)
                    continue
                }
                let handlers = rawHandlers.filter { rawHandler in
                    !isManagedClaudeHandler(rawHandler as? [String: Any] ?? [:])
                }
                guard handlers.isEmpty == false else { continue }
                group["hooks"] = handlers
                cleanedGroups.append(group)
            }
            var groups = cleanedGroups
            groups.append([
                "hooks": [[
                    "type": "command",
                    "command": executableURL.path,
                    "args": [Self.claudeHookArgument, AgentBridgeProvider.claude.rawValue],
                    "timeout": 2
                ]]
            ])
            hooks[event] = groups
        }

        root["hooks"] = hooks
        try writeJSON(root, to: claudeSettingsURL)
    }

    private func installOpenCode() throws {
        if FileManager.default.fileExists(atPath: openCodePluginURL.path) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: openCodePluginURL.path, isDirectory: &isDirectory), isDirectory.boolValue == false else {
                throw AgentIntegrationInstallError.unsupportedPluginPath(openCodePluginURL)
            }
            let existing = try Data(contentsOf: openCodePluginURL)
            guard let content = String(data: existing, encoding: .utf8), Self.isManagedOpenCodePlugin(content) else {
                throw AgentIntegrationInstallError.existingPlugin(openCodePluginURL)
            }
        }

        let directory = openCodePluginURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try openCodePluginSource.write(to: openCodePluginURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: openCodePluginURL.path)
    }

    private func loadJSON(at url: URL) throws -> [String: Any] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AgentIntegrationInstallError.invalidSettingsJSON(url)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentIntegrationInstallError.invalidSettingsJSON(url)
        }
        return root
    }

    private func writeJSON(_ root: [String: Any], to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func isManagedClaudeHandler(_ handler: [String: Any]) -> Bool {
        guard handler["type"] as? String == "command",
              handler["args"] as? [String] == [Self.claudeHookArgument, AgentBridgeProvider.claude.rawValue],
              let command = handler["command"] as? String else {
            return false
        }
        return command == executableURL.path || URL(fileURLWithPath: command).lastPathComponent == "Foundry"
    }

    private func codexHooksContainManaged(_ root: [String: Any]) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any] else { return false }
        return Self.codexHookEvents.allSatisfy { event in
            (hooks[event] as? [[String: Any]])?.contains { group in
                (group["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String) == codexScriptURL.path } == true
            } == true
        }
    }

    private func pruneManagedCodexHandlers(from group: [String: Any]) -> [String: Any]? {
        guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
        let filtered = handlers.filter { ($0["command"] as? String) != codexScriptURL.path }
        guard filtered.isEmpty == false else { return nil }
        var next = group
        next["hooks"] = filtered
        return next
    }

    private func cursorHooksContainManaged(_ root: [String: Any]) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any] else { return false }
        return Self.cursorHookEvents.allSatisfy { event in
            (hooks[event] as? [[String: Any]])?.contains { handler in
                guard isManagedCursorHandler(handler) else { return false }
                return (handler["command"] as? String)?.contains(Self.shellQuote(executableURL.path)) == true
            } == true
        }
    }

    private func isManagedCursorHandler(_ handler: [String: Any]) -> Bool {
        (handler["command"] as? String)?.contains(Self.managedCursorCommandMarker) == true
    }

    static func upsertCodexHooksFeature(_ contents: String) -> String {
        let line = "hooks = true"
        var lines = contents.components(separatedBy: "\n")
        var featuresIndex: Int?
        var featureEnd = lines.count
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "[features]" {
                featuresIndex = index
                featureEnd = lines[(index + 1)...].firstIndex { candidate in
                    let value = candidate.trimmingCharacters(in: .whitespaces)
                    return value.hasPrefix("[") && value.hasSuffix("]")
                } ?? lines.count
                break
            }
        }
        if let featuresIndex {
            for index in (featuresIndex + 1)..<featureEnd {
                if lines[index].range(of: #"^[ \t]*(hooks|codex_hooks)[ \t]*="#,
                                      options: .regularExpression) != nil {
                    lines[index] = line
                    return lines.joined(separator: "\n")
                }
            }
            lines.insert(line, at: featuresIndex + 1)
            return lines.joined(separator: "\n")
        }
        var updated = contents
        if updated.isEmpty == false && updated.hasSuffix("\n") == false { updated += "\n" }
        return updated + "\n[features]\n\(line)\n"
    }

    private static func codexHooksFeatureEnabled(_ contents: String) -> Bool {
        var inFeatures = false
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                inFeatures = trimmed == "[features]"
                continue
            }
            if inFeatures, trimmed.range(of: #"^(hooks|codex_hooks)[ \t]*=[ \t]*true[ \t]*$"#, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static let claudeHookEvents = [
        "SessionStart",
        "SessionEnd",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PostToolUseFailure",
        "PermissionRequest",
        "SubagentStart",
        "SubagentStop",
        "PreCompact",
        "PostCompact",
        "Stop",
        "StopFailure",
        "MessageDisplay",
        "TeammateIdle",
        "TaskCreated",
        "TaskCompleted",
        "CwdChanged"
    ]

    private static let codexHookEvents = ["SessionStart", "UserPromptSubmit", "Stop"]
    private static let cursorHookEvents = ["sessionStart", "sessionEnd", "subagentStart", "subagentStop", "beforeSubmitPrompt", "preToolUse", "postToolUse", "postToolUseFailure", "afterShellExecution", "afterMCPExecution", "afterFileEdit", "preCompact", "stop", "afterAgentResponse"]

    private var codexScriptSource: String {
        """
        #!/bin/sh
        foundry_codex_bridge="\(Self.managedCodexScriptMarker)"
        response="$(\(Self.shellQuote(executableURL.path)) --agent-bridge codex)"
        if [ $? -ne 0 ] || [ -z "$response" ]; then response='{"continue":true}'; fi
        printf '%s' "$response"
        """
    }

    private static func isManagedOpenCodePlugin(_ content: String) -> Bool {
        content.contains(managedOpenCodeMarker) || content.contains(legacyOpenCodeMarker)
    }

    private var openCodePluginSource: String {
        let executableData = try? JSONSerialization.data(withJSONObject: executableURL.path, options: .fragmentsAllowed)
        let executable = executableData.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return """
        import { spawn } from "node:child_process"

        const foundryAgentBridgeVersion = "foundry-agent-bridge-v2"
        const foundryExecutable = \(executable)
        const maximumPayloadBytes = 1048576

        const send = (event, directory) => {
          if (!event || typeof event !== "object") return Promise.resolve()
          const properties = event.properties && typeof event.properties === "object" ? { ...event.properties } : {}
          if (directory && properties.directory == null) properties.directory = directory
          const payload = JSON.stringify({ ...event, properties })
          if (Buffer.byteLength(payload, "utf8") > maximumPayloadBytes) return Promise.resolve()
          return new Promise((resolve) => {
            let settled = false
            const child = spawn(foundryExecutable, ["--agent-bridge", "opencode"], {
              stdio: ["pipe", "ignore", "ignore"],
              windowsHide: true,
            })
            const finish = () => {
              if (settled) return
              settled = true
              clearTimeout(timer)
              resolve()
            }
            const timer = setTimeout(() => {
              child.kill()
              finish()
            }, 2000)
            child.once("error", finish)
            child.once("exit", finish)
            child.stdin.on("error", finish)
            child.stdin.end(payload)
          })
        }

        export const FoundryAgentBridge = async ({ directory }) => ({
          event: async ({ event }) => send(event, directory),
          "chat.message": async (input, output) => {
            const text = output.parts?.filter((part) => part.type === "text").map((part) => part.text).join("\\n") ?? ""
            await send({ type: "chat.message", properties: { sessionID: input.sessionID, text } }, directory)
          },
          "tool.execute.before": async (input, output) => send({
            type: "tool.execute.before",
            properties: { sessionID: input.sessionID, tool: input.tool, input: output.args },
          }, directory),
          "tool.execute.after": async (input, output) => send({
            type: "tool.execute.after",
            properties: { sessionID: input.sessionID, tool: input.tool, output: output.output },
          }, directory),
        })

        void foundryAgentBridgeVersion
        """
    }
}
