import Foundation

struct AIConnectionTestResult: Equatable, Sendable {
    let message: String
    var isFailure = false

    static func success(_ message: String) -> AIConnectionTestResult {
        AIConnectionTestResult(message: message)
    }

    static func failure(_ message: String) -> AIConnectionTestResult {
        AIConnectionTestResult(message: message, isFailure: true)
    }
}

enum AITransportError: Error, Equatable, Sendable {
    case configuration(String)
    case authentication
    case rateLimited
    case quotaExhausted
    case unavailable
    case timeout
    case invalidResponse
    case unsupported
    case transient(String)

    var failureKind: AgentFailureKind {
        switch self {
        case .configuration: return .configuration
        case .authentication: return .configuration
        case .rateLimited: return .rateLimited
        case .quotaExhausted: return .rateLimited
        case .unavailable: return .unavailable
        case .timeout: return .transient
        case .invalidResponse: return .transient
        case .unsupported: return .unsupported
        case .transient: return .transient
        }
    }

    var message: String {
        switch self {
        case let .configuration(message): return message
        case .authentication: return "The AI provider rejected the sign-in. Check the API key or account in Settings › AI."
        case .rateLimited: return "The AI provider is rate limiting requests. Try again in a minute."
        case .quotaExhausted: return "This AI account is out of quota. Check billing, or pick another model in Settings › AI."
        case .unavailable: return "Couldn't reach the AI provider. Check your connection or the endpoint in Settings › AI."
        case .timeout: return "The AI provider took too long to answer. Try again."
        case .invalidResponse: return "The AI provider sent a reply Foundry couldn't read. Try again or pick another model."
        case .unsupported: return "This model can't do that. Pick another model in Settings › AI."
        case let .transient(message): return message
        }
    }
}

enum AITransportSupport {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration, delegate: AIProviderSessionDelegate(), delegateQueue: nil)
    }()

    static func endpoint(_ profile: AIProviderProfile, path: String) -> URL? {
        guard let rawEndpoint = profile.endpoint, let normalized = AIEndpointPolicy.normalized(rawEndpoint), var base = URL(string: normalized) else { return nil }
        if profile.kind == .openAI || profile.kind == .openAICompatible {
            let path = base.path.lowercased()
            if path.contains("/v1") == false { base.appendPathComponent("v1") }
        }
        return base.appendingPathComponent(path)
    }

    static func credential(_ profile: AIProviderProfile, store: AICredentialStore) throws -> AICredential? {
        try store.credential(for: profile.id)
    }

    static func apiKey(_ profile: AIProviderProfile, store: AICredentialStore) throws -> String? {
        guard profile.authentication == .apiKey || profile.authentication == .optionalAPIKey else { return nil }
        guard case let .apiKey(value)? = try credential(profile, store: store), value.isEmpty == false else { return nil }
        return value
    }

    static func requestData(_ request: URLRequest, timeout: Double) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AITransportError.invalidResponse }
        return (data, http)
    }

    static func classify(_ response: HTTPURLResponse) -> AITransportError? {
        switch response.statusCode {
        case 200...299: return nil
        case 401, 403: return .authentication
        case 408, 504: return .timeout
        case 429: return .rateLimited
        case 402: return .quotaExhausted
        case 404: return .unsupported
        case 500...599: return .unavailable
        default: return .transient("Provider returned HTTP \(response.statusCode).")
        }
    }

    static func makeFailure(_ error: Error) -> AgentModelResponse {
        if let error = error as? AITransportError { return .failure(error.message, error.failureKind) }
        if error is CancellationError { return .failure("Cancelled", .cancelled) }
        if let urlError = error as? URLError, urlError.code == .timedOut { return .failure(AITransportError.timeout.message, .transient) }
        return .failure("Provider request failed: \(error.localizedDescription)", .transient)
    }

    static func failureMessage(_ error: Error) -> String {
        if let error = error as? AITransportError { return error.message }
        if error is CancellationError { return "Cancelled" }
        return "Provider request failed: \(error.localizedDescription)"
    }

    static func toolDefinitions(_ tools: [AgentTool]) -> [[String: Any]] {
        tools.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.parameters]] }
    }
}
