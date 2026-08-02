import Foundation
import Security

enum AIProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleFoundationModels
    case openAI
    case anthropic
    case gemini
    case openAICompatible
    case ollama
    case openAISubscription

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleFoundationModels: return "Apple Intelligence"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .openAICompatible: return "OpenAI-compatible"
        case .ollama: return "Ollama"
        case .openAISubscription: return "ChatGPT subscription"
        }
    }

    var requiresNetwork: Bool {
        self != .appleFoundationModels
    }
}

enum AIAuthenticationKind: String, Codable, CaseIterable, Sendable {
    case none
    case apiKey
    case optionalAPIKey
    case oauth
}

struct AIProviderCapabilities: Codable, Equatable, Hashable, Sendable {
    var streaming: Bool
    var tools: Bool
    var vision: Bool
    var structuredOutput: Bool
    var modelDiscovery: Bool

    static let full = AIProviderCapabilities(streaming: true, tools: true, vision: true, structuredOutput: true, modelDiscovery: true)
    static let textOnly = AIProviderCapabilities(streaming: true, tools: false, vision: false, structuredOutput: false, modelDiscovery: false)
}

struct AIRequestOptions: Codable, Equatable, Hashable, Sendable {
    var timeoutSeconds: Double
    var temperature: Double?
    var maxOutputTokens: Int?
    var reasoningEffort: String?

    static let `default` = AIRequestOptions(timeoutSeconds: 60, temperature: nil, maxOutputTokens: nil, reasoningEffort: nil)
    static let codexDefault = AIRequestOptions(timeoutSeconds: 60, temperature: nil, maxOutputTokens: nil, reasoningEffort: "low")
}

struct AIModel: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let displayName: String
}

struct AIProviderProfile: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var kind: AIProviderKind
    var authentication: AIAuthenticationKind
    var endpoint: String?
    var model: String
    var presetID: String?
    var enabled: Bool
    var capabilities: AIProviderCapabilities
    var requestOptions: AIRequestOptions

    init(
        id: UUID = UUID(),
        name: String,
        kind: AIProviderKind,
        authentication: AIAuthenticationKind,
        endpoint: String? = nil,
        model: String,
        presetID: String? = nil,
        enabled: Bool = true,
        capabilities: AIProviderCapabilities = .full,
        requestOptions: AIRequestOptions = .default
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.authentication = authentication
        self.endpoint = endpoint
        self.model = model
        self.presetID = presetID
        self.enabled = enabled
        self.capabilities = capabilities
        self.requestOptions = requestOptions
    }

    static let appleID = UUID(uuidString: "4A3F65E8-0CB5-4F7E-9B42-6AF5F9AFB201")!
    static let ollamaID = UUID(uuidString: "4A3F65E8-0CB5-4F7E-9B42-6AF5F9AFB202")!

    static var appleDefault: AIProviderProfile {
        AIProviderProfile(
            id: appleID,
            name: "Apple Intelligence",
            kind: .appleFoundationModels,
            authentication: .none,
            model: "on-device",
            presetID: "apple",
            capabilities: AIProviderCapabilities(streaming: true, tools: true, vision: true, structuredOutput: true, modelDiscovery: false)
        )
    }

    static var ollamaDefault: AIProviderProfile {
        AIProviderProfile(
            id: ollamaID,
            name: "Ollama",
            kind: .ollama,
            authentication: .none,
            endpoint: "http://127.0.0.1:11434",
            model: "llama3.1",
            presetID: "ollama",
            enabled: false,
            capabilities: .full
        )
    }
}

struct AIProviderPreset: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: AIProviderKind
    let authentication: AIAuthenticationKind
    let endpoint: String?
    let defaultModel: String
    let defaultEnabled: Bool
    let capabilities: AIProviderCapabilities

    init(id: String, name: String, kind: AIProviderKind, authentication: AIAuthenticationKind, endpoint: String?, defaultModel: String, defaultEnabled: Bool = true, capabilities: AIProviderCapabilities) {
        self.id = id
        self.name = name
        self.kind = kind
        self.authentication = authentication
        self.endpoint = endpoint
        self.defaultModel = defaultModel
        self.defaultEnabled = defaultEnabled
        self.capabilities = capabilities
    }

    static let all: [AIProviderPreset] = [
        AIProviderPreset(id: "openai", name: "OpenAI", kind: .openAI, authentication: .apiKey, endpoint: "https://api.openai.com/v1", defaultModel: "gpt-4.1-mini", capabilities: .full),
        AIProviderPreset(id: "anthropic", name: "Anthropic", kind: .anthropic, authentication: .apiKey, endpoint: "https://api.anthropic.com/v1", defaultModel: "claude-3-5-sonnet-latest", capabilities: AIProviderCapabilities(streaming: true, tools: true, vision: true, structuredOutput: false, modelDiscovery: false)),
        AIProviderPreset(id: "gemini", name: "Google Gemini", kind: .gemini, authentication: .apiKey, endpoint: "https://generativelanguage.googleapis.com/v1beta", defaultModel: "gemini-2.0-flash", capabilities: .full),
        AIProviderPreset(id: "openrouter", name: "OpenRouter", kind: .openAICompatible, authentication: .apiKey, endpoint: "https://openrouter.ai/api/v1", defaultModel: "openai/gpt-4o-mini", capabilities: .full),
        AIProviderPreset(id: "groq", name: "Groq", kind: .openAICompatible, authentication: .apiKey, endpoint: "https://api.groq.com/openai/v1", defaultModel: "llama-3.3-70b-versatile", capabilities: AIProviderCapabilities(streaming: true, tools: true, vision: false, structuredOutput: true, modelDiscovery: true)),
        AIProviderPreset(id: "mistral", name: "Mistral", kind: .openAICompatible, authentication: .apiKey, endpoint: "https://api.mistral.ai/v1", defaultModel: "mistral-small-latest", capabilities: .full),
        AIProviderPreset(id: "together", name: "Together AI", kind: .openAICompatible, authentication: .apiKey, endpoint: "https://api.together.xyz/v1", defaultModel: "meta-llama/Llama-3.3-70B-Instruct-Turbo", capabilities: .full),
        AIProviderPreset(id: "xai", name: "xAI", kind: .openAICompatible, authentication: .apiKey, endpoint: "https://api.x.ai/v1", defaultModel: "grok-3-mini", capabilities: .full),
        AIProviderPreset(id: "deepseek", name: "DeepSeek", kind: .openAICompatible, authentication: .apiKey, endpoint: "https://api.deepseek.com/v1", defaultModel: "deepseek-chat", capabilities: .full),
        AIProviderPreset(id: "fireworks", name: "Fireworks AI", kind: .openAICompatible, authentication: .apiKey, endpoint: "https://api.fireworks.ai/inference/v1", defaultModel: "accounts/fireworks/models/llama-v3p1-8b-instruct", capabilities: .full),
        AIProviderPreset(id: "perplexity", name: "Perplexity", kind: .openAICompatible, authentication: .apiKey, endpoint: "https://api.perplexity.ai", defaultModel: "sonar", capabilities: AIProviderCapabilities(streaming: true, tools: false, vision: false, structuredOutput: false, modelDiscovery: false)),
        AIProviderPreset(id: "cerebras", name: "Cerebras", kind: .openAICompatible, authentication: .apiKey, endpoint: "https://api.cerebras.ai/v1", defaultModel: "llama-3.3-70b", capabilities: .full),
        AIProviderPreset(id: "deepinfra", name: "Deep Infra", kind: .openAICompatible, authentication: .apiKey, endpoint: "https://api.deepinfra.com/v1/openai", defaultModel: "meta-llama/Meta-Llama-3.1-70B-Instruct", capabilities: .full),
        AIProviderPreset(id: "huggingface", name: "Hugging Face", kind: .openAICompatible, authentication: .apiKey, endpoint: "https://router.huggingface.co/v1", defaultModel: "meta-llama/Llama-3.1-8B-Instruct", capabilities: .full),
        AIProviderPreset(id: "lmstudio", name: "LM Studio", kind: .openAICompatible, authentication: .none, endpoint: "http://127.0.0.1:1234/v1", defaultModel: "local-model", capabilities: .full),
        AIProviderPreset(id: "vllm", name: "vLLM", kind: .openAICompatible, authentication: .none, endpoint: "http://127.0.0.1:8000/v1", defaultModel: "local-model", capabilities: .full),
        AIProviderPreset(id: "mlx", name: "MLX server", kind: .openAICompatible, authentication: .none, endpoint: "http://127.0.0.1:8080/v1", defaultModel: "local-model", capabilities: .full),
        AIProviderPreset(id: "llamacpp", name: "llama.cpp", kind: .openAICompatible, authentication: .none, endpoint: "http://127.0.0.1:8080/v1", defaultModel: "local-model", capabilities: .full),
        AIProviderPreset(id: "ollama", name: "Ollama", kind: .ollama, authentication: .none, endpoint: "http://127.0.0.1:11434", defaultModel: "llama3.1", capabilities: .full),
        AIProviderPreset(id: "custom-openai-compatible", name: "Custom OpenAI-compatible endpoint", kind: .openAICompatible, authentication: .optionalAPIKey, endpoint: "http://127.0.0.1:8000/v1", defaultModel: "local-model", capabilities: .full),
        AIProviderPreset(id: "chatgpt-subscription", name: "ChatGPT subscription", kind: .openAISubscription, authentication: .oauth, endpoint: nil, defaultModel: "gpt-5.6-luna", defaultEnabled: false, capabilities: AIProviderCapabilities(streaming: true, tools: true, vision: false, structuredOutput: false, modelDiscovery: true))
    ]

    static func find(_ id: String?) -> AIProviderPreset? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    func makeProfile() -> AIProviderProfile {
        AIProviderProfile(
            name: name,
            kind: kind,
            authentication: authentication,
            endpoint: endpoint,
            model: defaultModel,
            presetID: id,
            enabled: defaultEnabled,
            capabilities: capabilities,
            requestOptions: kind == .openAISubscription ? .codexDefault : .default
        )
    }
}

struct AIOAuthCredential: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var idToken: String?
    var accountID: String
    var expiresAt: Date

    var isUsable: Bool {
        accessToken.isEmpty == false && refreshToken.isEmpty == false && accountID.isEmpty == false
    }
}

enum AICredential: Codable, Equatable, Sendable {
    case apiKey(String)
    case oauth(AIOAuthCredential)

    private enum CodingKeys: String, CodingKey {
        case apiKey
        case oauth
    }

    private struct OAuthPayload: Codable {
        var accessToken: String
        var refreshToken: String?
        var idToken: String?
        var accountID: String?
        var expiresAt: Date?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(String.self, forKey: .apiKey) {
            self = .apiKey(value)
            return
        }
        if let value = try? container.decode([String: String].self, forKey: .apiKey), let apiKey = value["_0"] {
            self = .apiKey(apiKey)
            return
        }
        if let value = try container.decodeIfPresent(OAuthPayload.self, forKey: .oauth) {
            self = .oauth(AIOAuthCredential(
                accessToken: value.accessToken,
                refreshToken: value.refreshToken ?? "",
                idToken: value.idToken,
                accountID: value.accountID ?? "",
                expiresAt: value.expiresAt ?? .distantPast
            ))
            return
        }
        throw DecodingError.dataCorruptedError(forKey: .oauth, in: container, debugDescription: "Unsupported AI credential")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .apiKey(value): try container.encode(value, forKey: .apiKey)
        case let .oauth(value): try container.encode(value, forKey: .oauth)
        }
    }
}

protocol AICredentialStore: Sendable {
    func credential(for profileID: UUID) throws -> AICredential?
    func save(_ credential: AICredential, for profileID: UUID) throws
    func delete(for profileID: UUID) throws
}

final class KeychainAICredentialStore: AICredentialStore, @unchecked Sendable {
    private let service: String

    init(service: String = "com.hridya.foundry.ai") {
        self.service = service
    }

    func credential(for profileID: UUID) throws -> AICredential? {
        var query = baseQuery(for: profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainAICredentialError.status(status) }
        guard let data = result as? Data else { throw KeychainAICredentialError.invalidData }
        return try JSONDecoder().decode(AICredential.self, from: data)
    }

    func save(_ credential: AICredential, for profileID: UUID) throws {
        let data = try JSONEncoder().encode(credential)
        var query = baseQuery(for: profileID)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery(for: profileID) as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainAICredentialError.status(updateStatus) }
        } else if status != errSecSuccess {
            throw KeychainAICredentialError.status(status)
        }
    }

    func delete(for profileID: UUID) throws {
        let status = SecItemDelete(baseQuery(for: profileID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainAICredentialError.status(status) }
    }

    private func baseQuery(for profileID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString
        ]
    }
}

enum KeychainAICredentialError: Error, LocalizedError, Equatable {
    case status(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case let .status(status): return "Keychain error \(status)"
        case .invalidData: return "The saved AI credential is invalid."
        }
    }
}

enum AIEndpointPolicy {
    static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host, host.isEmpty == false, url.user == nil, url.password == nil, url.fragment == nil else {
            return nil
        }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    static func isLoopbackOrPrivate(_ value: String) -> Bool {
        guard let normalized = normalized(value), let host = URL(string: normalized)?.host?.lowercased() else { return false }
        if host == "localhost" || host.hasSuffix(".localhost") || host == "::1" { return true }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        if octets.count == 4 {
            if octets[0] == 127 || octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1])) { return true }
        }
        return false
    }

    static func requiresPlainHTTPWarning(_ value: String) -> Bool {
        guard let normalized = normalized(value), let url = URL(string: normalized) else { return false }
        return url.scheme?.lowercased() == "http" && isLoopbackOrPrivate(normalized) == false
    }
}

enum AIProfileResolver {
    static func profile(for backend: AIBackend, in config: AIConfig) -> AIProviderProfile {
        if let profile = config.profiles.first(where: { profile in
            switch backend {
            case .ollama: return profile.kind == .ollama
            case .appleFoundationModels: return profile.kind == .appleFoundationModels
            case .openAI: return profile.kind == .openAI
            case .anthropic: return profile.kind == .anthropic
            case .gemini: return profile.kind == .gemini
            }
        }) {
            return profile
        }
        switch backend {
        case .ollama: return .ollamaDefault
        case .appleFoundationModels: return .appleDefault
        case .openAI: return AIProviderPreset.find("openai")?.makeProfile() ?? .appleDefault
        case .anthropic: return AIProviderPreset.find("anthropic")?.makeProfile() ?? .appleDefault
        case .gemini: return AIProviderPreset.find("gemini")?.makeProfile() ?? .appleDefault
        }
    }

    static func defaultProfile(in config: AIConfig) -> AIProviderProfile {
        if let id = config.defaultProfileID, let profile = config.profiles.first(where: { $0.id == id && $0.enabled }) { return profile }
        if let profile = config.profiles.first(where: { $0.enabled }) { return profile }
        return .appleDefault
    }
}
