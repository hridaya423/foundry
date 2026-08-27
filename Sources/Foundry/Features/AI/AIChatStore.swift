import Foundation
import FoundryServices

protocol AIChatStoring: Sendable {
    func load() -> [AIChatThread]
    func loadAsync() async -> [AIChatThread]
    func loadResult() -> AIChatLoadResult
    func loadResultAsync() async -> AIChatLoadResult
    func save(_ threads: [AIChatThread])
}

enum AIChatLoadResult: Sendable {
    case loaded([AIChatThread])
    case failed
}

extension AIChatStoring {
    func loadResult() -> AIChatLoadResult { .loaded(load()) }
    func loadResultAsync() async -> AIChatLoadResult { .loaded(await loadAsync()) }
}

struct AIChatThread: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var updatedAt: Date
    var providerProfileID: UUID?
    var messages: [AIChatMessage]

    init(id: UUID = UUID(), title: String, updatedAt: Date = .now, providerProfileID: UUID? = nil, messages: [AIChatMessage] = []) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.providerProfileID = providerProfileID
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

final class AIChatStore: @unchecked Sendable, AIChatStoring {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let diagnostics: DiagnosticsService?
    private let saveQueue = DispatchQueue(label: "com.hridya.foundry.ai-chat-save", qos: .utility)

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
        guard case let .loaded(threads) = loadResult() else { return [] }
        return threads
    }

    func loadResult() -> AIChatLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .loaded([]) }
        do {
            let data = try Data(contentsOf: url)
            let threads = try decoder.decode([AIChatThread].self, from: data).map { thread in
                var thread = thread
                thread.messages = compacted(thread.messages)
                return thread
            }
            return .loaded(threads)
        } catch {
            diagnostics?.log("Failed to load AI chats: \(error.localizedDescription)")
            return .failed
        }
    }

    func loadAsync() async -> [AIChatThread] {
        guard case let .loaded(threads) = await loadResultAsync() else { return [] }
        return threads
    }

    func loadResultAsync() async -> AIChatLoadResult {
        let url = url
        let diagnostics = diagnostics
        return await Task.detached(priority: .utility) {
            AIChatStore(url: url, diagnostics: diagnostics).loadResult()
        }.value
    }

    func save(_ threads: [AIChatThread]) {
        saveQueue.sync { write(threads) }
    }

    private func write(_ threads: [AIChatThread]) {
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
                guard let separator = message.content.firstIndex(of: ":") else { continue }
                let payload = message.content[message.content.index(after: separator)...]
                let name = payload.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
                guard name == "web_search" || name == "system_context" else { continue }
                if result.last?.role == .tool, result.last?.content == message.content { continue }
            }
            result.append(message)
        }
        return result
    }
}

final class AIChatPersistenceWriter: @unchecked Sendable {
    private let store: any AIChatStoring
    private let queue = DispatchQueue(label: "com.hridya.foundry.ai-chat-writer", qos: .utility)

    init(store: any AIChatStoring) {
        self.store = store
    }

    func schedule(_ threads: [AIChatThread]) {
        let store = store
        queue.async { store.save(threads) }
    }

    func flush() {
        queue.sync {}
    }
}
