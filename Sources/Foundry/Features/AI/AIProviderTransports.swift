import Foundation
import FoundryServices

enum OpenAICompatibleTransport {
    static func respond(profile: AIProviderProfile, messages: [[String: Any]], tools: [AgentTool], credentials: AICredentialStore) async -> AgentModelResponse {
        guard let url = AITransportSupport.endpoint(profile,
            path: "chat/completions") else { return .failure("The endpoint URL isn't valid. Fix it in Settings › AI.", .configuration) }
        do {
            let apiKey = try AITransportSupport.apiKey(profile, store: credentials)
            if profile.authentication == .apiKey, apiKey == nil { return .failure("Add an API key for \(profile.name) before sending requests.",
                .configuration) }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            var body: [String: Any] = ["model": profile.model, "stream": true, "messages": Self.messages(from: messages)]
            if profile.capabilities.tools && tools.isEmpty == false { body["tools"] = AITransportSupport.toolDefinitions(tools) }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (bytes, response) = try await AITransportSupport.session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return .failure("Provider returned an invalid response.", .transient) }
            if let error = AITransportSupport.classify(httpResponse) {
                return .failure(error.message, error.failureKind)
            }
            return try await decodeStream(lines: bytes.lines)
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
            guard (BestEffort.attempt("provider model catalog") { try JSONSerialization.jsonObject(with: data) }) != nil else {
                return .failure("Provider returned invalid model data.")
            }
            return .success("Connected to \(profile.name).")
        } catch {
            return .failure(AITransportSupport.failureMessage(error))
        }
    }

    static func models(profile: AIProviderProfile, credentials: AICredentialStore) async -> AIModelListResult {
        guard let url = AITransportSupport.endpoint(profile, path: "models") else { return .failed(String(localized: "Enter a valid endpoint.")) }
        do {
            let apiKey = try AITransportSupport.apiKey(profile, store: credentials)
            if profile.authentication == .apiKey, apiKey == nil { return .failed(String(localized: "Add an API key before listing models.")) }
            var request = URLRequest(url: url)
            if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            let (data, response) = try await AITransportSupport.requestData(request, timeout: profile.requestOptions.timeoutSeconds)
            if let error = AITransportSupport.classify(response) { return .failed(error.message) }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let rows = object["data"] as? [[String: Any]] else { return .failed(String(localized: "The provider returned invalid model data.")) }
            return .loaded(rows.compactMap { row in
                guard let id = row["id"] as? String, id.isEmpty == false else { return nil }
                return AIModel(id: id, displayName: id)
            }.sorted { $0.id < $1.id })
        } catch {
            return .failed(AITransportSupport.failureMessage(error))
        }
    }

    static func messages(from messages: [[String: Any]]) -> [[String: Any]] {
        messages.map { message in
            guard let calls = message["tool_calls"] as? [[String: Any]] else { return message }
            var encodedMessage = message
            encodedMessage["tool_calls"] = calls.map { call in
                guard var function = call["function"] as? [String: Any],
                      let arguments = function["arguments"],
                      (arguments is String) == false,
                      JSONSerialization.isValidJSONObject(arguments),
                      let data = (BestEffort.attempt("tool call arguments") { try JSONSerialization.data(withJSONObject: arguments) }),
                      let json = String(data: data, encoding: .utf8) else { return call }
                var encodedCall = call
                function["arguments"] = json
                encodedCall["function"] = function
                return encodedCall
            }
            return encodedMessage
        }
    }

    static func decodeStream<Lines: AsyncSequence>(lines: Lines) async throws -> AgentModelResponse where Lines.Element == String {
        var textParts: [String] = []
        var calls: [Int: StreamedToolCall] = [:]
        for try await line in lines {
            guard Task.isCancelled == false else { return .failure("Cancelled", .cancelled) }
            let value = line.hasPrefix("data:") ? String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces) : line
            guard value != "[DONE]", let root = StreamedToolCall.object(value) else { continue }
            if let failure = StreamedToolCall.failure(root) { return failure }
            guard let choice = (root["choices"] as? [[String: Any]])?.first else { continue }
            let delta = choice["delta"] as? [String: Any] ?? [:]
            if let content = delta["content"] as? String { textParts.append(content) }
            for call in delta["tool_calls"] as? [[String: Any]] ?? [] {
                let index = call["index"] as? Int ?? 0
                let function = call["function"] as? [String: Any] ?? [:]
                calls[index, default: StreamedToolCall()].append(id: call["id"] as? String, name: function["name"] as? String,
                    arguments: function["arguments"] as? String)
            }
        }
        return StreamedToolCall.response(text: textParts.joined(), calls: calls)
    }
}

enum OllamaTransport {
    static func test(profile: AIProviderProfile) async -> AIConnectionTestResult {
        guard let endpoint = profile.endpoint,
            let url = URL(string: endpoint)?.appendingPathComponent("api/tags") else { return .failure("Enter a valid Ollama endpoint.") }
        do {
            let request = URLRequest(url: url)
            let (_, response) = try await AITransportSupport.requestData(request, timeout: profile.requestOptions.timeoutSeconds)
            if let error = AITransportSupport.classify(response) { return .failure(error.message) }
            return .success("Connected to Ollama.")
        } catch {
            return .failure(AITransportSupport.failureMessage(error))
        }
    }

    static func models(profile: AIProviderProfile) async -> AIModelListResult {
        guard let endpoint = profile.endpoint, let url = URL(string: endpoint)?.appendingPathComponent("api/tags") else {
            return .failed(String(localized: "Enter a valid Ollama endpoint."))
        }
        do {
            let request = URLRequest(url: url)
            let (data, response) = try await AITransportSupport.requestData(request, timeout: profile.requestOptions.timeoutSeconds)
            if let error = AITransportSupport.classify(response) { return .failed(error.message) }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let rows = object["models"] as? [[String: Any]] else { return .failed(String(localized: "Ollama returned invalid model data.")) }
            return .loaded(rows.compactMap { row in
                guard let name = row["name"] as? String, name.isEmpty == false else { return nil }
                return AIModel(id: name, displayName: name)
            }.sorted { $0.id < $1.id })
        } catch {
            return .failed(AITransportSupport.failureMessage(error))
        }
    }
}

enum AnthropicTransport {
    static func respond(profile: AIProviderProfile, messages: [[String: Any]], tools: [AgentTool], credentials: AICredentialStore) async -> AgentModelResponse {
        guard let url = AITransportSupport.endpoint(profile,
            path: "messages") else { return .failure("The Anthropic endpoint URL isn't valid. Fix it in Settings › AI.", .configuration) }
        do {
            guard let apiKey = try AITransportSupport.apiKey(profile,
                store: credentials) else { return .failure("Add an Anthropic API key before sending requests.", .configuration) }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            var body: [String: Any] = ["model": profile.model, "max_tokens": profile.requestOptions.maxOutputTokens ?? 4096, "stream": true,
                "messages": anthropicMessages(messages)]
            if let system = messages.first(where: { ($0["role"] as? String) == "system" })?["content"] { body["system"] = system }
            if profile.capabilities.tools && tools.isEmpty == false { body["tools"] = tools.map { ["name": $0.name, "description": $0.description,
                "input_schema": $0.parameters] } }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (bytes, response) = try await AITransportSupport.session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return .failure("Provider returned an invalid response.", .transient) }
            if let error = AITransportSupport.classify(httpResponse) { return .failure(error.message, error.failureKind) }
            return try await decodeStream(lines: bytes.lines)
        } catch {
            return AITransportSupport.makeFailure(error)
        }
    }

    static func test(profile: AIProviderProfile, credentials: AICredentialStore) async -> AIConnectionTestResult {
        do {
            guard try AITransportSupport.apiKey(profile,
                store: credentials) != nil else { return .failure("Add an Anthropic API key before testing this provider.") }
        } catch {
            return .failure(AITransportSupport.failureMessage(error))
        }
        return .success("Anthropic credentials are stored. Send a request to verify model access.")
    }

    static func decodeStream<Lines: AsyncSequence>(lines: Lines) async throws -> AgentModelResponse where Lines.Element == String {
        var textParts: [String] = []
        var calls: [Int: StreamedToolCall] = [:]
        var event = ""
        for try await line in lines {
            guard Task.isCancelled == false else { return .failure("Cancelled", .cancelled) }
            if line.hasPrefix("event:") { event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces); continue }
            guard line.hasPrefix("data:"), let root = StreamedToolCall.object(String(line.dropFirst(5))) else { continue }
            if let failure = StreamedToolCall.failure(root) { return failure }
            let index = root["index"] as? Int ?? 0
            if event == "content_block_start", let content = root["content_block"] as? [String: Any], content["type"] as? String == "tool_use" {
                calls[index, default: StreamedToolCall()].append(id: content["id"] as? String, name: content["name"] as? String, arguments: nil)
            }
            if event == "content_block_delta", let delta = root["delta"] as? [String: Any] {
                if let value = delta["text"] as? String { textParts.append(value) }
                if let value = delta["partial_json"] as? String { calls[index]?.append(id: nil, name: nil, arguments: value) }
            }
        }
        return StreamedToolCall.response(text: textParts.joined(), calls: calls)
    }

    static func anthropicMessages(_ messages: [[String: Any]]) -> [[String: Any]] {
        let converted: [[String: Any]] = messages.compactMap { message in
            guard let role = message["role"] as? String, role != "system" else { return nil }
            if role == "assistant", let calls = message["tool_calls"] as? [[String: Any]] {
                var blocks: [[String: Any]] = []
                if let text = message["content"] as? String, text.isEmpty == false { blocks.append(["type": "text", "text": text]) }
                for call in calls {
                    guard let function = call["function"] as? [String: Any], let name = function["name"] as? String else { continue }
                    blocks.append(["type": "tool_use", "id": call["id"] as? String ?? "foundry-\(name)", "name": name,
                        "input": function["arguments"] as? [String: Any] ?? [:]])
                }
                return ["role": "assistant", "content": blocks]
            }
            if role == "tool", let name = message["name"] as? String, let content = message["content"] as? String {
                return ["role": "user", "content": [["type": "tool_result", "tool_use_id": message["tool_call_id"] as? String ?? "foundry-\(name)",
                    "content": content]]]
            }
            return ["role": role, "content": message["content"] ?? ""]
        }
        return converted.reduce(into: []) { merged, message in
            if let blocks = message["content"] as? [[String: Any]], blocks.allSatisfy({ $0["type"] as? String == "tool_result" }),
                let last = merged.last, last["role"] as? String == "user", let previous = last["content"] as? [[String: Any]],
                previous.allSatisfy({ $0["type"] as? String == "tool_result" }) {
                merged[merged.count - 1]["content"] = previous + blocks
            } else {
                merged.append(message)
            }
        }
    }
}

enum GeminiTransport {
    static func respond(profile: AIProviderProfile, messages: [[String: Any]], tools: [AgentTool], credentials: AICredentialStore) async -> AgentModelResponse {
        guard let endpoint = profile.endpoint,
              let base = URL(string: endpoint),
              var components = URLComponents(
                url: base.appendingPathComponent("models/\(profile.model):streamGenerateContent"),
                resolvingAgainstBaseURL: false
              )
        else {
            return .failure("The Gemini endpoint URL isn't valid. Fix it in Settings › AI.", .configuration)
        }
        components.queryItems = [URLQueryItem(name: "alt", value: "sse")]
        guard let url = components.url else { return .failure("The Gemini endpoint URL isn't valid. Fix it in Settings › AI.", .configuration) }
        do {
            guard let apiKey = try AITransportSupport.apiKey(profile,
                store: credentials) else { return .failure("Add a Gemini API key before sending requests.", .configuration) }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            var body: [String: Any] = ["contents": geminiContents(messages)]
            if profile.capabilities.tools && tools.isEmpty == false {
                body["tools"] = [["function_declarations": tools.map { ["name": $0.name, "description": $0.description, "parameters": $0.parameters] }]]
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (bytes, response) = try await AITransportSupport.session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return .failure("Provider returned an invalid response.", .transient) }
            if let error = AITransportSupport.classify(httpResponse) { return .failure(error.message, error.failureKind) }
            return try await decodeStream(lines: bytes.lines)
        } catch {
            return AITransportSupport.makeFailure(error)
        }
    }

    static func geminiContents(_ messages: [[String: Any]]) -> [[String: Any]] {
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
                let part: [String: Any] = ["functionResponse": ["name": name, "response": ["content": result]]]
                if var last = contents.last, var parts = last["parts"] as? [[String: Any]], parts.allSatisfy({ $0["functionResponse"] != nil }) {
                    parts.append(part)
                    last["parts"] = parts
                    contents[contents.count - 1] = last
                } else {
                    contents.append(["role": "user", "parts": [part]])
                }
            } else if let content = message["content"] as? String {
                contents.append(["role": geminiRole, "parts": [["text": content]]])
            }
        }
        return contents
    }

    static func test(profile: AIProviderProfile, credentials: AICredentialStore) async -> AIConnectionTestResult {
        do {
            guard try AITransportSupport.apiKey(profile,
                store: credentials) != nil else { return .failure("Add a Gemini API key before testing this provider.") }
        } catch {
            return .failure(AITransportSupport.failureMessage(error))
        }
        return .success("Gemini credentials are stored. Send a request to verify model access.")
    }

    static func decodeStream<Lines: AsyncSequence>(lines: Lines) async throws -> AgentModelResponse where Lines.Element == String {
        var textParts: [String] = []
        var toolCalls: [AgentToolCall] = []
        for try await line in lines {
            guard Task.isCancelled == false else { return .failure("Cancelled", .cancelled) }
            let value = line.hasPrefix("data:") ? String(line.dropFirst(5)) : line
            guard let root = StreamedToolCall.object(value) else { continue }
            if let failure = StreamedToolCall.failure(root) { return failure }
            guard let candidate = (root["candidates"] as? [[String: Any]])?.first,
                  let content = candidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]]
            else { continue }
            for part in parts {
                if let value = part["text"] as? String { textParts.append(value) }
                if let call = part["functionCall"] as? [String: Any], let name = call["name"] as? String,
                    let toolCall = AgentToolCall.from(json: ["name": name, "arguments": call["args"] as? [String: Any] ?? [:]]) {
                    toolCalls.append(toolCall)
                }
            }
        }
        let text = textParts.joined()
        if toolCalls.isEmpty == false { return .toolCalls(toolCalls, assistantText: text) }
        return .final(AgentProtocolDecoder.displayContent(from: text))
    }
}

struct StreamedToolCall {
    private var id: String?
    private var name: String?
    private var argumentParts: [String] = []

    mutating func append(id: String?, name: String?, arguments: String?) {
        if let id { self.id = id }
        if let name { self.name = name }
        if let arguments { argumentParts.append(arguments) }
    }

    static func object(_ value: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(value.trimmingCharacters(in: .whitespaces).utf8)) as? [String: Any]
    }

    static func failure(_ root: [String: Any]) -> AgentModelResponse? {
        guard let error = root["error"] as? [String: Any] else { return nil }
        let code = ["type", "code", "status"].compactMap { error[$0].map { "\($0)" } }.joined(separator: " ").lowercased()
        let kind: AgentFailureKind
        if code.contains("rate") || code.contains("429") || code.contains("resource_exhausted") {
            kind = .rateLimited
        } else if code.contains("overloaded") || code.contains("503") || code.contains("unavailable") {
            kind = .unavailable
        } else {
            kind = .transient
        }
        let detail = (error["message"] as? String).map { " \($0.prefix(400))" } ?? ""
        return .failure("The AI provider stopped with an error.\(detail)", kind)
    }

    static func response(text: String, calls: [Int: StreamedToolCall]) -> AgentModelResponse {
        let toolCalls = calls.sorted { $0.key < $1.key }.compactMap { $0.value.toolCall }
        if toolCalls.isEmpty == false { return .toolCalls(toolCalls, assistantText: text) }
        return .final(AgentProtocolDecoder.displayContent(from: text))
    }

    private var toolCall: AgentToolCall? {
        guard let name else { return nil }
        let arguments = (BestEffort.attempt("decode tool call arguments") {
            try JSONSerialization.jsonObject(with: Data(argumentParts.joined().utf8))
        }) as? [String: Any] ?? [:]
        var object: [String: Any] = ["name": name, "arguments": arguments]
        object["id"] = id
        return AgentToolCall.from(json: object)
    }
}
