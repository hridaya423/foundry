import Foundation

struct AIChatThread: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var updatedAt: Date
    var messages: [AIChatMessage]

    init(id: UUID = UUID(), title: String, updatedAt: Date = .now, messages: [AIChatMessage] = []) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

struct AIChatMessage: Identifiable, Codable, Hashable, Sendable {
    enum Role: String, Codable, Hashable, Sendable {
        case user
        case assistant
        case tool
        case system
    }

    let id: UUID
    let role: Role
    var content: String
    var createdAt: Date

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = .now) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

enum AIConversationContext {
    static func build(from messages: [AIChatMessage], maxCharacters: Int = 2400) -> String? {
        guard maxCharacters > 0 else { return nil }
        var remaining = maxCharacters
        var lines: [String] = []
        for message in messages.reversed() where message.role == .user || message.role == .assistant {
            let role = message.role == .user ? "User" : "Assistant"
            let prefix = "\(role): "
            guard remaining > prefix.count else { break }
            let content = String(message.content.prefix(remaining - prefix.count))
            lines.append(prefix + content)
            remaining -= prefix.count + content.count + 1
            if remaining <= 0 { break }
        }
        let context = lines.reversed().joined(separator: "\n")
        return context.isEmpty ? nil : context
    }
}

final class AIChatStore {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let diagnostics: DiagnosticsService?

    init(url: URL? = nil, diagnostics: DiagnosticsService? = nil) {
        if let url {
            self.url = url
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.url = home.appendingPathComponent(".config/foundry/ai-chats.json")
        }
        self.diagnostics = diagnostics
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> [AIChatThread] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([AIChatThread].self, from: data).map { thread in
                var thread = thread
                thread.messages = compacted(thread.messages)
                return thread
            }
        } catch {
            diagnostics?.log("Failed to load AI chats: \(error.localizedDescription)")
            return []
        }
    }

    func save(_ threads: [AIChatThread]) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(threads)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            diagnostics?.log("Failed to save AI chats: \(error.localizedDescription)")
        }
    }

    private func compacted(_ messages: [AIChatMessage]) -> [AIChatMessage] {
        var result: [AIChatMessage] = []
        for message in messages {
            if message.role == .tool {
                let payload = message.content.split(separator: ":", maxSplits: 1).last.map(String.init) ?? message.content
                let name = payload.split(separator: ":", maxSplits: 1).first.map(String.init) ?? payload
                guard name == "web_search" || name == "system_context" else { continue }
                if result.last?.role == .tool, result.last?.content == message.content { continue }
            }
            result.append(message)
        }
        return result
    }
}
