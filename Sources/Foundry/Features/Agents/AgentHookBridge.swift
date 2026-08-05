import Darwin
import Foundation

enum AgentBridgeProvider: String, CaseIterable, Sendable {
    case claude
    case codex
    case cursor
    case opencode

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .opencode: "OpenCode"
        }
    }

    var symbol: String {
        switch self {
        case .claude: "bubble.left.and.bubble.right"
        case .codex: "sparkles"
        case .cursor: "cursorarrow.rays"
        case .opencode: "chevron.left.forwardslash.chevron.right"
        }
    }
}

enum AgentHookBridge {
    static func run(provider: AgentBridgeProvider, input: Data = FileHandle.standardInput.readDataToEndOfFile(), environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard input.count <= 1_048_576,
              let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let envelope = normalize(provider: provider, object: object, environment: environment) else {
            if provider == .cursor || provider == .codex { FileHandle.standardOutput.write(Data(#"{"continue":true}"#.utf8)) }
            return
        }
        _ = send(envelope, socketURL: AgentEventSocketServer.socketURL)
        if provider == .cursor || provider == .codex { FileHandle.standardOutput.write(Data(#"{"continue":true}"#.utf8)) }
    }

    static func normalize(provider: AgentBridgeProvider, object: [String: Any], environment: [String: String] = [:]) -> AgentEventEnvelope? {
        switch provider {
        case .claude:
            return normalizeCommandHook(provider: .claude, object: object, environment: environment)
        case .codex:
            return normalizeCommandHook(provider: .codex, object: object, environment: environment)
        case .cursor:
            return normalizeCursor(object: object, environment: environment)
        case .opencode:
            return normalizeOpenCode(object: object, environment: environment)
        }
    }

    private static func normalizeCommandHook(provider: AgentProviderKind, object: [String: Any], environment: [String: String]) -> AgentEventEnvelope? {
        guard let baseSessionID = string(object, keys: ["session_id", "sessionId"]) else { return nil }
        let hookEvent = string(object, keys: ["hook_event_name", "event", "type"]) ?? ""
        let agentID = string(object, keys: ["agent_id", "agentId"])
        let isSubagent = hookEvent.lowercased().contains("subagent") && agentID != nil
        let sessionID = isSubagent ? "\(baseSessionID):agent:\(agentID!)" : baseSessionID
        let parentSessionID = isSubagent ? baseSessionID : string(object, keys: ["parent_session_id", "parentSessionId"])
        let metadata = commandHookMetadata(provider: provider, object: object, sessionID: baseSessionID, environment: environment)
        let event: AgentEvent

        switch hookEvent.lowercased() {
        case "sessionstart":
            event = .sessionStart(metadata: metadata)
        case "sessionend":
            event = .sessionEnd
        case "subagentstart":
            event = .sessionStart(metadata: metadata)
        case "subagentstop":
            event = .sessionEnd
        case "userpromptsubmit":
            event = .userPrompt(string(object, keys: ["prompt", "message", "user_prompt"]) ?? "")
        case "pretooluse":
            event = .toolActivity(name: string(object, keys: ["tool_name", "toolName"]) ?? "tool", detail: text(object["tool_input"] ?? object["toolInput"]), running: true)
        case "posttooluse", "posttoolusefailure", "posttoolbatch":
            event = .toolActivity(name: string(object, keys: ["tool_name", "toolName"]) ?? "tool", detail: text(object["tool_response"] ?? object["toolResponse"] ?? object["error"]), running: false)
        case "permissionrequest":
            event = .attention(reason: .permission, prompt: string(object, keys: ["prompt", "message", "tool_name"]))
        case "precompact", "postcompact":
            event = .status(.working)
        case "stop":
            event = .status(.recent)
        case "stopfailure":
            event = .completion(success: false)
        case "messagedisplay":
            event = .assistantMessage(string(object, keys: ["message", "text", "content"]) ?? "")
        case "teammateidle":
            event = .status(.idle)
        case "taskcreated":
            event = .status(.working)
        case "taskcompleted":
            event = .status(.recent)
        case "cwdchanged":
            event = .metadata(metadata)
        default:
            return nil
        }

        return AgentEventEnvelope(
            requestID: UUID().uuidString,
            provider: provider,
            sessionID: sessionID,
            parentSessionID: parentSessionID,
            eventID: string(object, keys: ["event_id", "eventId"]),
            timestamp: date(object, keys: ["timestamp", "time"]),
            deadline: Date().addingTimeInterval(2),
            origin: .hook,
            capabilities: [.observe, .jumpTerminal],
            metadata: metadata,
            event: event
        )
    }

    private static func normalizeCursor(object: [String: Any], environment: [String: String]) -> AgentEventEnvelope? {
        guard let sessionID = string(object, keys: ["parent_conversation_id", "conversation_id", "session_id", "generation_id"]) else { return nil }
        let hookEvent = string(object, keys: ["hook_event_name", "event", "type"]) ?? ""
        let cwd = string(object, keys: ["cwd"]) ?? (object["workspace_roots"] as? [String])?.first ?? environment["CURSOR_PROJECT_DIR"] ?? environment["PWD"]
        let metadata = AgentSessionMetadata(
            title: pathComponent(cwd),
            workingDirectory: cwd,
            project: pathComponent(cwd),
            model: string(object, keys: ["model"]),
            terminalLocator: terminalLocator(environment: environment)
        )
        let event: AgentEvent
        switch hookEvent.lowercased() {
        case "sessionstart": event = .sessionStart(metadata: metadata)
        case "sessionend": event = .sessionEnd
        case "beforesubmitprompt": event = .userPrompt(string(object, keys: ["prompt"]) ?? "")
        case "pretooluse", "subagentstart":
            event = .toolActivity(name: string(object, keys: ["tool_name", "subagent_type"]) ?? "tool", detail: text(object["tool_input"] ?? object["task"]), running: true)
        case "posttooluse", "aftershellexecution", "aftermcpexecution", "afterfileedit", "subagentstop":
            event = .toolActivity(name: string(object, keys: ["tool_name"]) ?? "tool", detail: text(object["output"] ?? object["error_message"]), running: false)
        case "posttoolusefailure":
            event = .completion(success: false)
        case "precompact": event = .status(.working)
        case "afteragentresponse": event = .assistantMessage(string(object, keys: ["text"]) ?? "")
        case "stop": event = string(object, keys: ["status"])?.lowercased() == "completed" ? .status(.recent) : .completion(success: false)
        default: return nil
        }
        return AgentEventEnvelope(
            requestID: UUID().uuidString,
            provider: .cursor,
            sessionID: sessionID,
            eventID: string(object, keys: ["event_id"]),
            timestamp: date(object, keys: ["timestamp", "time"]),
            deadline: Date().addingTimeInterval(2),
            origin: .hook,
            capabilities: [.observe, .liveText, .jumpApplication],
            metadata: metadata,
            event: event
        )
    }

    private static func normalizeOpenCode(object: [String: Any], environment: [String: String]) -> AgentEventEnvelope? {
        let properties = (object["properties"] as? [String: Any]) ?? object
        guard let sessionID = nestedString(properties, paths: [
            ["sessionID"], ["sessionId"], ["info", "id"], ["part", "sessionID"], ["threadID"]
        ]) else { return nil }
        let eventName = string(object, keys: ["type", "event", "name"]) ?? ""
        let metadata = openCodeMetadata(properties: properties, environment: environment)
        let event: AgentEvent

        switch eventName.lowercased() {
        case "session.created", "session.updated":
            event = .sessionStart(metadata: metadata)
        case "session.deleted":
            event = .sessionEnd
        case "chat.message":
            event = .userPrompt(string(properties, keys: ["text", "message", "content"]) ?? "")
        case "message.updated", "message.part.updated":
            event = .assistantMessage(text(properties["text"] ?? properties["content"] ?? nestedValue(properties, path: ["part", "text"])) ?? "")
        case "tool.execute.before":
            event = .toolActivity(name: string(properties, keys: ["tool", "name"]) ?? "tool", detail: string(properties, keys: ["input", "args"]), running: true)
        case "tool.execute.after":
            event = .toolActivity(name: string(properties, keys: ["tool", "name"]) ?? "tool", detail: string(properties, keys: ["output", "result"]), running: false)
        case "permission.asked":
            event = .attention(reason: .permission, prompt: string(properties, keys: ["permission", "description", "message"]))
        case "question.asked":
            event = .attention(reason: .question, prompt: string(properties, keys: ["question", "prompt", "message"]))
        case "session.error":
            event = .completion(success: false)
        case "session.idle":
            event = .status(.recent)
        case "session.status":
            let status = nestedString(properties, paths: [["status", "type"]])?.lowercased()
            event = status == "idle" ? .status(.recent) : status == "retry" ? .completion(success: false) : .status(.working)
        case "session.compacted":
            event = .status(.working)
        default:
            return nil
        }

        return AgentEventEnvelope(
            requestID: UUID().uuidString,
            provider: .opencode,
            sessionID: sessionID,
            parentSessionID: nestedString(properties, paths: [["parentID"], ["parentId"]]),
            eventID: nestedString(properties, paths: [["eventID"], ["eventId"]]),
            timestamp: date(object, keys: ["timestamp", "time"]) ?? date(properties, keys: ["timestamp", "time"]),
            deadline: Date().addingTimeInterval(2),
            origin: .plugin,
            capabilities: [.observe, .liveText],
            metadata: metadata,
            event: event
        )
    }

    private static func commandHookMetadata(provider: AgentProviderKind, object: [String: Any], sessionID: String, environment: [String: String]) -> AgentSessionMetadata {
        let cwd = string(object, keys: ["cwd", "working_directory"]) ?? environment["PWD"]
        let command = provider == .codex ? "codex resume \(sessionID)" : "claude --resume \(sessionID)"
        return AgentSessionMetadata(
            title: pathComponent(cwd),
            workingDirectory: cwd,
            project: pathComponent(cwd),
            model: string(object, keys: ["model", "model_name"]),
            terminalCommand: command,
            terminalLocator: terminalLocator(environment: environment)
        )
    }

    private static func openCodeMetadata(properties: [String: Any], environment: [String: String]) -> AgentSessionMetadata {
        let cwd = nestedString(properties, paths: [["directory"], ["cwd"], ["workingDirectory"], ["info", "directory"]]) ?? environment["PWD"]
        return AgentSessionMetadata(
            title: nestedString(properties, paths: [["title"], ["info", "title"]]) ?? pathComponent(cwd),
            workingDirectory: cwd,
            project: pathComponent(cwd),
            model: nestedString(properties, paths: [["model"], ["info", "model"]]),
            terminalCommand: nil,
            terminalLocator: terminalLocator(environment: environment)
        )
    }

    private static func terminalLocator(environment: [String: String]) -> AgentTerminalLocator? {
        let tty = environment["TTY"] ?? environment["SSH_TTY"]
        let terminalName = environment["TERM_PROGRAM"]
        guard tty != nil || terminalName != nil || environment["SSH_CONNECTION"] != nil else { return nil }
        return AgentTerminalLocator(
            tty: tty,
            processID: nil,
            applicationBundleID: nil,
            terminalName: terminalName,
            remoteHost: environment["SSH_CONNECTION"]?.split(separator: " ").last.map(String.init)
        )
    }

    static func send(_ envelope: AgentEventEnvelope, socketURL: URL) -> Bool {
        guard let data = try? JSONEncoder().encode(envelope) else { return false }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var timeout = timeval(tv_sec: 1, tv_usec: 500_000)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketURL.path.utf8) + [0]
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
        }
        let addressLength = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(descriptor, sockaddrPointer, addressLength)
            }
        }
        guard connected == 0 else { return false }
        guard writeAll(data, to: descriptor) else { return false }
        shutdown(descriptor, SHUT_WR)
        var ack = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while ack.count < 16_384 {
            let count = buffer.withUnsafeMutableBytes { bytes in
                read(descriptor, bytes.baseAddress, bytes.count)
            }
            guard count > 0 else { break }
            ack.append(buffer, count: count)
        }
        return (try? JSONDecoder().decode(AgentEventAck.self, from: ack))?.accepted == true
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return false }
            var offset = 0
            while offset < data.count {
                let count = write(descriptor, baseAddress.advanced(by: offset), data.count - offset)
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
    }

    private static func string(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, value.isEmpty == false { return String(value.prefix(32_768)) }
            if let value = object[key] as? NSNumber { return value.stringValue }
        }
        return nil
    }

    private static func text(_ value: Any?) -> String? {
        if let string = value as? String, string.isEmpty == false { return String(string.prefix(32_768)) }
        if let number = value as? NSNumber { return number.stringValue }
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return String(text.prefix(32_768))
    }

    private static func nestedString(_ object: [String: Any], paths: [[String]]) -> String? {
        for path in paths {
            var value: Any = object
            for key in path {
                guard let next = (value as? [String: Any])?[key] else {
                    value = NSNull()
                    break
                }
                value = next
            }
            if let string = value as? String, string.isEmpty == false { return String(string.prefix(32_768)) }
        }
        return nil
    }

    private static func nestedValue(_ object: [String: Any], path: [String]) -> Any? {
        var value: Any = object
        for key in path {
            guard let next = (value as? [String: Any])?[key] else { return nil }
            value = next
        }
        return value
    }

    private static func pathComponent(_ path: String?) -> String? {
        guard let path, path.isEmpty == false else { return nil }
        let component = URL(fileURLWithPath: path).lastPathComponent
        return component.isEmpty ? nil : component
    }

    private static func date(_ object: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let number = object[key] as? NSNumber { return Date(timeIntervalSince1970: number.doubleValue > 10_000_000_000 ? number.doubleValue / 1_000 : number.doubleValue) }
            if let string = object[key] as? String, let date = ISO8601DateFormatter().date(from: string) { return date }
        }
        return nil
    }
}
