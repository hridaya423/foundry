import Foundation

enum OpenAICompatibleTransport {
    static func respond(profile: AIProviderProfile, messages: [[String: Any]], tools: [AgentTool], credentials: AICredentialStore) async -> AgentModelResponse {
        guard let url = AITransportSupport.endpoint(profile, path: "chat/completions") else { return .failure("Invalid provider endpoint", .configuration) }
        do {
            let apiKey = try AITransportSupport.apiKey(profile, store: credentials)
            if profile.authentication == .apiKey, apiKey == nil { return .failure("Add an API key for \(profile.name) before sending requests.", .configuration) }
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

    static func messages(from messages: [[String: Any]]) -> [[String: Any]] {
        messages.map { message in
            guard let calls = message["tool_calls"] as? [[String: Any]] else { return message }
            var encodedMessage = message
            encodedMessage["tool_calls"] = calls.map { call in
                guard var function = call["function"] as? [String: Any],
                      let arguments = function["arguments"],
                      (arguments is String) == false,
                      JSONSerialization.isValidJSONObject(arguments),
                      let data = try? JSONSerialization.data(withJSONObject: arguments),
                      let json = String(data: data, encoding: .utf8) else { return call }
                var encodedCall = call
                function["arguments"] = json
                encodedCall["function"] = function
                return encodedCall
            }
            return encodedMessage
        }
    }

    private static func decodeStream(bytes: URLSession.AsyncBytes) async throws -> AgentModelResponse {
        var textParts: [String] = []
        var toolID: String?
        var toolName: String?
        var toolArgumentParts: [String] = []
        for try await line in bytes.lines {
            guard Task.isCancelled == false else { return .failure("Cancelled", .cancelled) }
            let value = line.hasPrefix("data:") ? String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces) : line
            guard value.isEmpty == false, value != "[DONE]", let data = value.data(using: .utf8), let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            guard let choice = (root["choices"] as? [[String: Any]])?.first else { continue }
            let delta = choice["delta"] as? [String: Any] ?? [:]
            if let content = delta["content"] as? String { textParts.append(content) }
            if let calls = delta["tool_calls"] as? [[String: Any]], let call = calls.first, let function = call["function"] as? [String: Any] {
                if let name = function["name"] as? String { toolName = name }
                if let id = call["id"] as? String { toolID = id }
                if let arguments = function["arguments"] as? String { toolArgumentParts.append(arguments) }
            }
        }
        let text = textParts.joined()
        if let toolName {
            let arguments = (try? JSONSerialization.jsonObject(with: Data(toolArgumentParts.joined().utf8)) as? [String: Any]) ?? [:]
            var object: [String: Any] = ["name": toolName, "arguments": arguments]
            object["id"] = toolID
            return .toolCall(AgentToolCall.from(json: object) ?? AgentToolCall(id: toolID, name: toolName, arguments: [:]), assistantText: text)
        }
        return .final(AgentProtocolDecoder.displayContent(from: text))
    }
}

enum OllamaTransport {
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

enum AnthropicTransport {
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
        var textParts: [String] = []
        var toolID: String?
        var toolName: String?
        var toolArgumentParts: [String] = []
        var event = ""
        for try await line in bytes.lines {
            guard Task.isCancelled == false else { return .failure("Cancelled", .cancelled) }
            if line.hasPrefix("event:") { event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces); continue }
            guard line.hasPrefix("data:"), let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces).data(using: .utf8), let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if event == "content_block_start", let content = root["content_block"] as? [String: Any], content["type"] as? String == "tool_use" {
                toolID = content["id"] as? String
                toolName = content["name"] as? String
            }
            if event == "content_block_delta", let delta = root["delta"] as? [String: Any] {
                if let value = delta["text"] as? String { textParts.append(value) }
                if let value = delta["partial_json"] as? String { toolArgumentParts.append(value) }
            }
        }
        let text = textParts.joined()
        if let toolName {
            let arguments = (try? JSONSerialization.jsonObject(with: Data(toolArgumentParts.joined().utf8)) as? [String: Any]) ?? [:]
            var object: [String: Any] = ["name": toolName, "arguments": arguments]
            object["id"] = toolID
            return .toolCall(AgentToolCall.from(json: object) ?? AgentToolCall(id: toolID, name: toolName, arguments: [:]), assistantText: text)
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
                    blocks.append(["type": "tool_use", "id": call["id"] as? String ?? "foundry-\(name)", "name": name, "input": function["arguments"] as? [String: Any] ?? [:]])
                }
                return ["role": "assistant", "content": blocks]
            }
            if role == "tool", let name = message["name"] as? String, let content = message["content"] as? String {
                return ["role": "user", "content": [["type": "tool_result", "tool_use_id": message["tool_call_id"] as? String ?? "foundry-\(name)", "content": content]]]
            }
            return ["role": role, "content": message["content"] ?? ""]
        }
    }
}

enum GeminiTransport {
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
        var textParts: [String] = []
        var toolCall: AgentToolCall?
        for try await line in bytes.lines {
            guard Task.isCancelled == false else { return .failure("Cancelled", .cancelled) }
            let value = line.hasPrefix("data:") ? String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces) : line
            guard let data = value.data(using: .utf8), let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let candidate = (root["candidates"] as? [[String: Any]])?.first, let content = candidate["content"] as? [String: Any], let parts = content["parts"] as? [[String: Any]] else { continue }
            for part in parts {
                if let value = part["text"] as? String { textParts.append(value) }
                if let call = part["functionCall"] as? [String: Any], let name = call["name"] as? String { toolCall = AgentToolCall.from(json: ["name": name, "arguments": call["args"] as? [String: Any] ?? [:]]) }
            }
        }
        let text = textParts.joined()
        if let toolCall { return .toolCall(toolCall, assistantText: text) }
        return .final(AgentProtocolDecoder.displayContent(from: text))
    }
}
