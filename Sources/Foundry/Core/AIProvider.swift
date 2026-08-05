import Foundation
import FoundryDomain
import FoundryServices

enum AIStreamEvent: Sendable, Equatable {
    case status(String)
    case textDelta(String)
    case toolCallStarted(name: String)
    case toolResult(name: String, result: String)
    case completed
    case failed(String)
}

final class AIProvider: @unchecked Sendable, CommandProvider {
    let id = "foundry.ai"

    var searchPolicy: CommandProviderSearchPolicy { CommandProviderSearchPolicy(tier: .deferred) }

    func isActive(for query: String) -> Bool {
        Self.request(from: query) != nil
    }

    private let config: ConfigService
    private let diagnostics: DiagnosticsService

    init(config: ConfigService, diagnostics: DiagnosticsService) {
        self.config = config
        self.diagnostics = diagnostics
    }

    func search(_ searchRequest: CommandSearchRequest) async -> [CommandResult] {
        guard let request = Self.request(from: searchRequest.query) else { return [] }
        var response = ""
        for await event in stream(prompt: request.prompt, backend: request.backend) {
            switch event {
            case let .textDelta(delta):
                response += delta
            case let .failed(message) where response.isEmpty:
                response = message
            default:
                break
            }
        }
        guard response.isEmpty == false else { return [] }

        return [CommandResult(
            id: AIRequestIdentifier.make(prompt: request.prompt, backend: request.backend),
            title: response,
            subtitle: "AI agent · \(request.backend.displayName)",
            icon: CommandIcon(fallback: "AI", systemName: "sparkles"),
            route: .aiResponse,
            primaryAction: CommandAction(id: "ai.copy", title: "Copy", kind: .copyToClipboard(response)),
            secondaryActions: [CommandAction(id: "ai.log", title: "Log", kind: .log(response))]
        )]
    }

    func stream(prompt: String, context: String? = nil, backend: AIBackend? = nil, profileID: UUID? = nil, sessionID: String? = nil) -> AsyncStream<AIStreamEvent> {
        let selectedProfile = profileID.flatMap { id in config.current.ai.profiles.first { $0.id == id && $0.enabled } }
            ?? backend.map { config.current.ai.profile(for: $0) }
            ?? AIProfileResolver.defaultProfile(in: config.current.ai)
        return AsyncStream { continuation in
            let task = Task { [config, diagnostics] in
                await AgentRunner(config: config, diagnostics: diagnostics).stream(prompt: prompt, context: context, profile: selectedProfile, sessionID: sessionID, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func run(prompt: String, backend: AIBackend? = nil) async -> String {
        var response = ""
        for await event in stream(prompt: prompt, backend: backend) {
            switch event {
            case let .textDelta(delta):
                response += delta
            case let .failed(message) where response.isEmpty:
                response = message
            default:
                break
            }
        }
        return response
    }

    static func request(from query: String) -> AIRequest? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("ollama ") { return makeRequest(prompt: String(trimmed.dropFirst(7)), backend: .ollama) }
        if lower.hasPrefix("ask ") { return makeRequest(prompt: String(trimmed.dropFirst(4)), backend: .appleFoundationModels) }
        if lower.hasPrefix("ai ") { return makeRequest(prompt: String(trimmed.dropFirst(3)), backend: .appleFoundationModels) }
        if lower.hasPrefix("plan ") { return makeRequest(prompt: String(trimmed.dropFirst(5)), backend: .appleFoundationModels) }
        return nil
    }

    private static func makeRequest(prompt: String, backend: AIBackend) -> AIRequest? {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.isEmpty == false else { return nil }
        return AIRequest(prompt: prompt, backend: backend)
    }
}

struct AIRequest: Sendable {
    let prompt: String
    let backend: AIBackend
}

enum AIRequestIdentifier {
    static func make(prompt: String, backend: AIBackend) -> String {
        let input = "\(backend.rawValue):\(prompt.trimmingCharacters(in: .whitespacesAndNewlines))"
        let bytes = Array(input.utf8)
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "ai.\(String(hash, radix: 16))"
    }
}

private extension AIBackend {
    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .appleFoundationModels: return "Apple AI"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Gemini"
        }
    }
}
