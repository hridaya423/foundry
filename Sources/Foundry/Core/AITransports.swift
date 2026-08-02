import Foundation

private final class AIProviderSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @Sendable @escaping (URLRequest?) -> Void) {
        guard let sourceHost = task.currentRequest?.url?.host?.lowercased(), let destinationHost = request.url?.host?.lowercased(), sourceHost == destinationHost else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

enum AITransportRouter {
    private static let credentials: AICredentialStore = KeychainAICredentialStore()

    static func respond(
        profile: AIProviderProfile,
        prompt: String,
        context: String?,
        messages: [[String: Any]],
        tools: [AgentTool],
        sessionID: String?,
        continuation: AsyncStream<AIStreamEvent>.Continuation
    ) async -> AgentModelResponse {
        switch profile.kind {
        case .appleFoundationModels:
            return await AppleAgentClient.respond(request: prompt, context: context, continuation: continuation)
        case .ollama:
            return await OllamaAgentClient.respond(
                host: profile.endpoint ?? "http://127.0.0.1:11434",
                model: profile.model,
                messages: messages,
                tools: tools,
                continuation: continuation
            )
        case .openAI, .openAICompatible:
            return await OpenAICompatibleTransport.respond(profile: profile, messages: messages, tools: tools, credentials: credentials)
        case .anthropic:
            return await AnthropicTransport.respond(profile: profile, messages: messages, tools: tools, credentials: credentials)
        case .gemini:
            return await GeminiTransport.respond(profile: profile, messages: messages, tools: tools, credentials: credentials)
        case .openAISubscription:
            return await OpenAICodexTransport.respond(profile: profile, messages: messages, tools: tools, sessionID: sessionID)
        }
    }

    static func test(profile: AIProviderProfile) async -> AIConnectionTestResult {
        switch profile.kind {
        case .appleFoundationModels:
            return .success("Apple Intelligence is available when the system model is ready.")
        case .openAI, .openAICompatible:
            return await OpenAICompatibleTransport.test(profile: profile, credentials: credentials)
        case .ollama:
            return await OllamaTransport.test(profile: profile)
        case .anthropic:
            return await AnthropicTransport.test(profile: profile, credentials: credentials)
        case .gemini:
            return await GeminiTransport.test(profile: profile, credentials: credentials)
        case .openAISubscription:
            return await OpenAICodexTransport.test(profile: profile)
        }
    }

    static func models(profile: AIProviderProfile) async -> [AIModel] {
        switch profile.kind {
        case .openAI, .openAICompatible:
            return await OpenAICompatibleTransport.models(profile: profile, credentials: credentials)
        case .ollama:
            return await OllamaTransport.models(profile: profile)
        case .openAISubscription:
            return CodexModelPolicy.models
        default:
            return []
        }
    }
}

struct AIConnectionTestResult: Equatable, Sendable {
    let isSuccess: Bool
    let message: String

    static func success(_ message: String) -> AIConnectionTestResult {
        AIConnectionTestResult(isSuccess: true, message: message)
    }

    static func failure(_ message: String) -> AIConnectionTestResult {
        AIConnectionTestResult(isSuccess: false, message: message)
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
        case .authentication: return "Authentication failed. Check the provider credential."
        case .rateLimited: return "The provider is temporarily rate limited. Try again shortly."
        case .quotaExhausted: return "The provider quota is exhausted. Check billing or choose another profile."
        case .unavailable: return "The provider endpoint is unavailable."
        case .timeout: return "The provider request timed out."
        case .invalidResponse: return "The provider returned an invalid response."
        case .unsupported: return "This provider does not support the requested capability."
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

    static func readableError(_ data: Data, fallback: AITransportError) -> AITransportError {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return fallback }
        let candidates = ["message", "error", "detail"]
        for key in candidates {
            if let value = object[key] as? String, value.isEmpty == false { return .transient(String(value.prefix(300))) }
            if let value = object[key] as? [String: Any], let message = value["message"] as? String, message.isEmpty == false { return .transient(String(message.prefix(300))) }
        }
        return fallback
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

private enum OpenAICompatibleTransport {
    static func respond(profile: AIProviderProfile, messages: [[String: Any]], tools: [AgentTool], credentials: AICredentialStore) async -> AgentModelResponse {
        guard let url = AITransportSupport.endpoint(profile, path: "chat/completions") else { return .failure("Invalid provider endpoint", .configuration) }
        do {
            let apiKey = try AITransportSupport.apiKey(profile, store: credentials)
            if profile.authentication == .apiKey, apiKey == nil { return .failure("Add an API key for \(profile.name) before sending requests.", .configuration) }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            var body: [String: Any] = ["model": profile.model, "stream": true, "messages": messages]
            if profile.capabilities.tools && tools.isEmpty == false { body["tools"] = AITransportSupport.toolDefinitions(tools) }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (bytes, response) = try await AITransportSupport.session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return .failure("Provider returned an invalid response.", .transient) }
            if let error = AITransportSupport.classify(httpResponse) {
                return .failure(error.message, error.failureKind)
            }
            return try await decodeStream(bytes: bytes)
        } catch {
            return AITransportSupport.makeFailure(error)
        }
    }

    static func test(profile: AIProviderProfile, credentials: AICredentialStore) async -> AIConnectionTestResult {
        guard let url = AITransportSupport.endpoint(profile, path: "models") else { return .failure("Enter a valid HTTP or HTTPS endpoint.") }
        do {
            let apiKey = try AITransportSupport.apiKey(profile, store: credentials)
            if profile.authentication == .apiKey, apiKey == nil { return .failure("Add an API key before testing this provider.") }
            var request = URLRequest(url: url)
            if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            let (data, response) = try await AITransportSupport.requestData(request, timeout: profile.requestOptions.timeoutSeconds)
            if let error = AITransportSupport.classify(response) { return .failure(error.message) }
            guard (try? JSONSerialization.jsonObject(with: data)) != nil else { return .failure("Provider returned invalid model data.") }
            return .success("Connected to \(profile.name).")
        } catch {
            return .failure(AITransportSupport.failureMessage(error))
        }
    }

    static func models(profile: AIProviderProfile, credentials: AICredentialStore) async -> [AIModel] {
        guard let url = AITransportSupport.endpoint(profile, path: "models") else { return [] }
        do {
            let apiKey = try AITransportSupport.apiKey(profile, store: credentials)
            if profile.authentication == .apiKey, apiKey == nil { return [] }
            var request = URLRequest(url: url)
            if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            let (data, response) = try await AITransportSupport.requestData(request, timeout: profile.requestOptions.timeoutSeconds)
            guard AITransportSupport.classify(response) == nil, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = object["data"] as? [[String: Any]] else { return [] }
            return rows.compactMap { row in
                guard let id = row["id"] as? String, id.isEmpty == false else { return nil }
                return AIModel(id: id, displayName: id)
            }.sorted { $0.id < $1.id }
        } catch {
            return []
        }
    }

    private static func decodeStream(bytes: URLSession.AsyncBytes) async throws -> AgentModelResponse {
        var text = ""
        var toolName: String?
        var toolArguments = ""
        for try await line in bytes.lines {
            guard Task.isCancelled == false else { return .failure("Cancelled", .cancelled) }
            let value = line.hasPrefix("data:") ? String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces) : line
            guard value.isEmpty == false, value != "[DONE]", let data = value.data(using: .utf8), let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            guard let choice = (root["choices"] as? [[String: Any]])?.first else { continue }
            let delta = choice["delta"] as? [String: Any] ?? [:]
            if let content = delta["content"] as? String { text += content }
            if let calls = delta["tool_calls"] as? [[String: Any]], let call = calls.first, let function = call["function"] as? [String: Any] {
                if let name = function["name"] as? String { toolName = name }
                if let arguments = function["arguments"] as? String { toolArguments += arguments }
            }
        }
        if let toolName {
            let arguments = (try? JSONSerialization.jsonObject(with: Data(toolArguments.utf8)) as? [String: Any]) ?? [:]
            return .toolCall(AgentToolCall.from(json: ["name": toolName, "arguments": arguments]) ?? AgentToolCall(name: toolName, arguments: [:]), assistantText: text)
        }
        return .final(AgentProtocolDecoder.displayContent(from: text))
    }
}

private enum OllamaTransport {
    static func test(profile: AIProviderProfile) async -> AIConnectionTestResult {
        guard let endpoint = profile.endpoint, let url = URL(string: endpoint)?.appendingPathComponent("api/tags") else { return .failure("Enter a valid Ollama endpoint.") }
        do {
            let request = URLRequest(url: url)
            let (_, response) = try await AITransportSupport.requestData(request, timeout: profile.requestOptions.timeoutSeconds)
            if let error = AITransportSupport.classify(response) { return .failure(error.message) }
            return .success("Connected to Ollama.")
        } catch {
            return .failure(AITransportSupport.failureMessage(error))
        }
    }

    static func models(profile: AIProviderProfile) async -> [AIModel] {
        guard let endpoint = profile.endpoint, let url = URL(string: endpoint)?.appendingPathComponent("api/tags") else { return [] }
        do {
            let request = URLRequest(url: url)
            let (data, response) = try await AITransportSupport.requestData(request, timeout: profile.requestOptions.timeoutSeconds)
            guard AITransportSupport.classify(response) == nil, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = object["models"] as? [[String: Any]] else { return [] }
            return rows.compactMap { row in
                guard let name = row["name"] as? String, name.isEmpty == false else { return nil }
                return AIModel(id: name, displayName: name)
            }.sorted { $0.id < $1.id }
        } catch {
            return []
        }
    }
}

private enum AnthropicTransport {
    static func respond(profile: AIProviderProfile, messages: [[String: Any]], tools: [AgentTool], credentials: AICredentialStore) async -> AgentModelResponse {
        guard let url = AITransportSupport.endpoint(profile, path: "messages") else { return .failure("Invalid Anthropic endpoint", .configuration) }
        do {
            guard let apiKey = try AITransportSupport.apiKey(profile, store: credentials) else { return .failure("Add an Anthropic API key before sending requests.", .configuration) }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            var body: [String: Any] = ["model": profile.model, "max_tokens": profile.requestOptions.maxOutputTokens ?? 4096, "stream": true, "messages": anthropicMessages(messages)]
            if let system = messages.first(where: { ($0["role"] as? String) == "system" })?["content"] { body["system"] = system }
            if profile.capabilities.tools && tools.isEmpty == false { body["tools"] = tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.parameters] } }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (bytes, response) = try await AITransportSupport.session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return .failure("Provider returned an invalid response.", .transient) }
            if let error = AITransportSupport.classify(httpResponse) { return .failure(error.message, error.failureKind) }
            return try await decodeStream(bytes: bytes)
        } catch {
            return AITransportSupport.makeFailure(error)
        }
    }

    static func test(profile: AIProviderProfile, credentials: AICredentialStore) async -> AIConnectionTestResult {
        guard (try? AITransportSupport.apiKey(profile, store: credentials)) != nil else { return .failure("Add an Anthropic API key before testing this provider.") }
        return .success("Anthropic credentials are stored. Send a request to verify model access.")
    }

    private static func decodeStream(bytes: URLSession.AsyncBytes) async throws -> AgentModelResponse {
        var text = ""
        var toolName: String?
        var toolArguments = ""
        var event = ""
        for try await line in bytes.lines {
            guard Task.isCancelled == false else { return .failure("Cancelled", .cancelled) }
            if line.hasPrefix("event:") { event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces); continue }
            guard line.hasPrefix("data:"), let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces).data(using: .utf8), let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if event == "content_block_start", let content = root["content_block"] as? [String: Any], content["type"] as? String == "tool_use" { toolName = content["name"] as? String }
            if event == "content_block_delta", let delta = root["delta"] as? [String: Any] {
                if let value = delta["text"] as? String { text += value }
                if let value = delta["partial_json"] as? String { toolArguments += value }
            }
        }
        if let toolName {
            let arguments = (try? JSONSerialization.jsonObject(with: Data(toolArguments.utf8)) as? [String: Any]) ?? [:]
            return .toolCall(AgentToolCall.from(json: ["name": toolName, "arguments": arguments]) ?? AgentToolCall(name: toolName, arguments: [:]), assistantText: text)
        }
        return .final(AgentProtocolDecoder.displayContent(from: text))
    }

    private static func anthropicMessages(_ messages: [[String: Any]]) -> [[String: Any]] {
        messages.compactMap { message in
            guard let role = message["role"] as? String, role != "system" else { return nil }
            if role == "assistant", let calls = message["tool_calls"] as? [[String: Any]] {
                var blocks: [[String: Any]] = []
                if let text = message["content"] as? String, text.isEmpty == false { blocks.append(["type": "text", "text": text]) }
                for call in calls {
                    guard let function = call["function"] as? [String: Any], let name = function["name"] as? String else { continue }
                    blocks.append(["type": "tool_use", "id": "foundry-\(name)", "name": name, "input": function["arguments"] as? [String: Any] ?? [:]])
                }
                return ["role": "assistant", "content": blocks]
            }
            if role == "tool", let name = message["name"] as? String, let content = message["content"] as? String {
                return ["role": "user", "content": [["type": "tool_result", "tool_use_id": "foundry-\(name)", "content": content]]]
            }
            return ["role": role, "content": message["content"] ?? ""]
        }
    }
}

private enum GeminiTransport {
    static func respond(profile: AIProviderProfile, messages: [[String: Any]], tools: [AgentTool], credentials: AICredentialStore) async -> AgentModelResponse {
        guard let endpoint = profile.endpoint, let apiKey = try? AITransportSupport.apiKey(profile, store: credentials), let base = URL(string: endpoint), var components = URLComponents(url: base.appendingPathComponent("models/\(profile.model):streamGenerateContent"), resolvingAgainstBaseURL: false) else {
            return .failure("Add a Gemini API key and valid endpoint before sending requests.", .configuration)
        }
        components.queryItems = [URLQueryItem(name: "alt", value: "sse")]
        guard let url = components.url else { return .failure("Invalid Gemini endpoint", .configuration) }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            var contents: [[String: Any]] = []
            for message in messages {
                guard let role = message["role"] as? String else { continue }
                let geminiRole = role == "assistant" ? "model" : "user"
                if role == "assistant", let calls = message["tool_calls"] as? [[String: Any]] {
                    let parts = calls.compactMap { call -> [String: Any]? in
                        guard let function = call["function"] as? [String: Any], let name = function["name"] as? String else { return nil }
                        return ["functionCall": ["name": name, "args": function["arguments"] as? [String: Any] ?? [:]]]
                    }
                    if parts.isEmpty == false { contents.append(["role": geminiRole, "parts": parts]) }
                } else if role == "tool", let name = message["name"] as? String, let result = message["content"] as? String {
                    contents.append(["role": "user", "parts": [["functionResponse": ["name": name, "response": ["content": result]]]]])
                } else if let content = message["content"] as? String {
                    contents.append(["role": geminiRole, "parts": [["text": content]]])
                }
            }
            var body: [String: Any] = ["contents": contents]
            if profile.capabilities.tools && tools.isEmpty == false {
                body["tools"] = [["function_declarations": tools.map { ["name": $0.name, "description": $0.description, "parameters": $0.parameters] }]]
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (bytes, response) = try await AITransportSupport.session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return .failure("Provider returned an invalid response.", .transient) }
            if let error = AITransportSupport.classify(httpResponse) { return .failure(error.message, error.failureKind) }
            return try await decodeStream(bytes: bytes)
        } catch {
            return AITransportSupport.makeFailure(error)
        }
    }

    static func test(profile: AIProviderProfile, credentials: AICredentialStore) async -> AIConnectionTestResult {
        guard (try? AITransportSupport.apiKey(profile, store: credentials)) != nil else { return .failure("Add a Gemini API key before testing this provider.") }
        return .success("Gemini credentials are stored. Send a request to verify model access.")
    }

    private static func decodeStream(bytes: URLSession.AsyncBytes) async throws -> AgentModelResponse {
        var text = ""
        var toolCall: AgentToolCall?
        for try await line in bytes.lines {
            guard Task.isCancelled == false else { return .failure("Cancelled", .cancelled) }
            let value = line.hasPrefix("data:") ? String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces) : line
            guard let data = value.data(using: .utf8), let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let candidate = (root["candidates"] as? [[String: Any]])?.first, let content = candidate["content"] as? [String: Any], let parts = content["parts"] as? [[String: Any]] else { continue }
            for part in parts {
                if let value = part["text"] as? String { text += value }
                if let call = part["functionCall"] as? [String: Any], let name = call["name"] as? String { toolCall = AgentToolCall.from(json: ["name": name, "arguments": call["args"] as? [String: Any] ?? [:]]) }
            }
        }
        if let toolCall { return .toolCall(toolCall, assistantText: text) }
        return .final(AgentProtocolDecoder.displayContent(from: text))
    }
}

enum CodexModelPolicy {
    static let models: [AIModel] = [
        AIModel(id: "gpt-5.6-sol", displayName: "GPT-5.6 Sol"),
        AIModel(id: "gpt-5.6-terra", displayName: "GPT-5.6 Terra"),
        AIModel(id: "gpt-5.6-luna", displayName: "GPT-5.6 Luna"),
        AIModel(id: "gpt-5.5", displayName: "GPT-5.5"),
        AIModel(id: "gpt-5.4", displayName: "GPT-5.4"),
        AIModel(id: "gpt-5.4-mini", displayName: "GPT-5.4 Mini"),
        AIModel(id: "gpt-5.2", displayName: "GPT-5.2")
    ]

    static let defaultModel = "gpt-5.6-luna"

    static func contains(_ model: String) -> Bool {
        models.contains { $0.id == model }
    }
}

struct CodexResponsesStreamFrame: Equatable, Sendable {
    let contentDelta: String
    let toolCall: AgentToolCall?
    let isDone: Bool
    let failureMessage: String?
}

struct CodexResponsesStreamDecoder: Sendable {
    private(set) var text = ""
    private(set) var toolName: String?
    private(set) var toolArguments = ""

    mutating func decode(line: String) -> CodexResponsesStreamFrame? {
        let value = line.hasPrefix("data:") ? String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces) : line.trimmingCharacters(in: .whitespaces)
        guard value.isEmpty == false else { return nil }
        if value == "[DONE]" { return finish() }
        guard let data = value.data(using: .utf8), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let type = root["type"] as? String ?? ""
        switch type {
        case "response.output_text.delta":
            let delta = root["delta"] as? String ?? ""
            text += delta
            return CodexResponsesStreamFrame(contentDelta: delta, toolCall: nil, isDone: false, failureMessage: nil)
        case "response.output_item.added":
            if let item = root["item"] as? [String: Any], item["type"] as? String == "function_call" {
                toolName = item["name"] as? String
            }
            return nil
        case "response.function_call_arguments.delta":
            toolArguments += root["delta"] as? String ?? ""
            return nil
        case "response.function_call_arguments.done":
            if let arguments = root["arguments"] as? String { toolArguments = arguments }
            return nil
        case "response.failed", "error":
            let response = root["response"] as? [String: Any]
            let error = root["error"] as? [String: Any]
            let message = (response?["error"] as? [String: Any])?["message"] as? String
                ?? error?["message"] as? String
                ?? "The Codex backend returned an error."
            return CodexResponsesStreamFrame(contentDelta: "", toolCall: nil, isDone: true, failureMessage: String(message.prefix(400)))
        case "response.completed", "response.incomplete":
            return finish()
        default:
            if let choices = root["choices"] as? [[String: Any]], let delta = choices.first?["delta"] as? [String: Any], let content = delta["content"] as? String {
                text += content
                return CodexResponsesStreamFrame(contentDelta: content, toolCall: nil, isDone: false, failureMessage: nil)
            }
            return nil
        }
    }

    mutating func finish() -> CodexResponsesStreamFrame {
        let call: AgentToolCall?
        if let toolName {
            let arguments = (try? JSONSerialization.jsonObject(with: Data(toolArguments.utf8)) as? [String: Any]) ?? [:]
            call = AgentToolCall.from(json: ["name": toolName, "arguments": arguments]) ?? AgentToolCall(name: toolName, arguments: [:])
        } else {
            call = nil
        }
        return CodexResponsesStreamFrame(contentDelta: "", toolCall: call, isDone: true, failureMessage: nil)
    }
}

private enum OpenAICodexTransport {
    private static let tokenManager = OpenAICodexTokenManager.shared

    static func respond(profile: AIProviderProfile, messages: [[String: Any]], tools: [AgentTool], sessionID: String?) async -> AgentModelResponse {
        guard CodexModelPolicy.contains(profile.model) else { return .failure("The selected model is not available through the ChatGPT subscription connection.", .configuration) }
        do {
            var credential = try await tokenManager.validCredential(profileID: profile.id)
            for attempt in 0...1 {
                guard let url = URL(string: CodexOAuthHTTP.codexEndpoint) else { return .failure("Invalid Codex backend endpoint.", .configuration) }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = profile.requestOptions.timeoutSeconds
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue(credential.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
                request.setValue("foundry", forHTTPHeaderField: "originator")
                request.setValue("Foundry/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
                request.setValue(sessionID ?? UUID().uuidString, forHTTPHeaderField: "session-id")
                var body: [String: Any] = [
                    "model": profile.model,
                    "stream": true,
                    "store": false,
                    "input": codexInput(messages),
                    "tools": codexTools(tools, enabled: profile.capabilities.tools)
                ]
                if let reasoningEffort = profile.requestOptions.reasoningEffort {
                    body["reasoning"] = ["effort": reasoningEffort]
                }
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (bytes, response) = try await AITransportSupport.session.bytes(for: request)
                guard let http = response as? HTTPURLResponse else { return .failure("Codex returned an invalid response.", .transient) }
                if http.statusCode == 401, attempt == 0 {
                    credential = try await tokenManager.forceRefresh(profileID: profile.id)
                    continue
                }
                if let error = AITransportSupport.classify(http) { return .failure(error.message, error.failureKind) }
                return try await decode(bytes: bytes)
            }
            return .failure("Codex authentication failed after refreshing the subscription credential.", .configuration)
        } catch let error as OpenAICodexOAuthError {
            return .failure(error.localizedDescription, error == .cancelled ? .cancelled : .configuration)
        } catch is CancellationError {
            return .failure("Cancelled", .cancelled)
        } catch {
            return .failure("Codex request failed: \(error.localizedDescription)", .transient)
        }
    }

    static func test(profile: AIProviderProfile) async -> AIConnectionTestResult {
        guard CodexModelPolicy.contains(profile.model) else { return .failure("Choose a supported Codex subscription model.") }
        do {
            let credential = try await tokenManager.validCredential(profileID: profile.id)
            let suffix = credential.accountID.count > 8 ? String(credential.accountID.prefix(8)) : credential.accountID
            return .success("ChatGPT subscription credential is valid for account \(suffix)…")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func decode(bytes: URLSession.AsyncBytes) async throws -> AgentModelResponse {
        var decoder = CodexResponsesStreamDecoder()
        for try await line in bytes.lines {
            guard Task.isCancelled == false else { return .failure("Cancelled", .cancelled) }
            guard let frame = decoder.decode(line: line) else { continue }
            if let failure = frame.failureMessage { return .failure(failure, .transient) }
            if frame.isDone {
                if let toolCall = frame.toolCall { return .toolCall(toolCall, assistantText: decoder.text) }
                return .final(AgentProtocolDecoder.displayContent(from: decoder.text))
            }
        }
        let frame = decoder.finish()
        if let toolCall = frame.toolCall { return .toolCall(toolCall, assistantText: decoder.text) }
        return .final(AgentProtocolDecoder.displayContent(from: decoder.text))
    }

    private static func codexInput(_ messages: [[String: Any]]) -> [[String: Any]] {
        var input: [[String: Any]] = []
        for message in messages {
            guard let role = message["role"] as? String else { continue }
            if role == "assistant", let calls = message["tool_calls"] as? [[String: Any]] {
                for call in calls {
                    guard let function = call["function"] as? [String: Any], let name = function["name"] as? String else { continue }
                    let arguments = (try? JSONSerialization.data(withJSONObject: function["arguments"] as? [String: String] ?? [:])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    input.append(["type": "function_call", "call_id": "foundry-\(name)", "name": name, "arguments": arguments])
                }
                if let content = message["content"] as? String, content.isEmpty == false { input.append(["role": role, "content": content]) }
            } else if role == "tool", let name = message["name"] as? String, let content = message["content"] as? String {
                input.append(["type": "function_call_output", "call_id": "foundry-\(name)", "output": content])
            } else if let content = message["content"] as? String {
                input.append(["role": role, "content": content])
            }
        }
        return input
    }

    private static func codexTools(_ tools: [AgentTool], enabled: Bool) -> [[String: Any]] {
        guard enabled else { return [] }
        return tools.map { ["type": "function", "name": $0.name, "description": $0.description, "parameters": $0.parameters, "strict": false] }
    }
}
