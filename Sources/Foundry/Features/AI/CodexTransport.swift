import Foundation

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
    private var textParts: [String] = []
    private(set) var toolName: String?
    private var toolArgumentParts: [String] = []
    var text: String { textParts.joined() }

    mutating func decode(line: String) -> CodexResponsesStreamFrame? {
        let value = line.hasPrefix("data:") ? String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces) : line.trimmingCharacters(in: .whitespaces)
        guard value.isEmpty == false else { return nil }
        if value == "[DONE]" { return finish() }
        guard let data = value.data(using: .utf8), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let type = root["type"] as? String ?? ""
        switch type {
        case "response.output_text.delta":
            let delta = root["delta"] as? String ?? ""
            textParts.append(delta)
            return CodexResponsesStreamFrame(contentDelta: delta, toolCall: nil, isDone: false, failureMessage: nil)
        case "response.output_item.added":
            if let item = root["item"] as? [String: Any], item["type"] as? String == "function_call" {
                toolName = item["name"] as? String
            }
            return nil
        case "response.function_call_arguments.delta":
            toolArgumentParts.append(root["delta"] as? String ?? "")
            return nil
        case "response.function_call_arguments.done":
            if let arguments = root["arguments"] as? String { toolArgumentParts = [arguments] }
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
                textParts.append(content)
                return CodexResponsesStreamFrame(contentDelta: content, toolCall: nil, isDone: false, failureMessage: nil)
            }
            return nil
        }
    }

    mutating func finish() -> CodexResponsesStreamFrame {
        let call: AgentToolCall?
        if let toolName {
            let arguments = (try? JSONSerialization.jsonObject(with: Data(toolArgumentParts.joined().utf8)) as? [String: Any]) ?? [:]
            call = AgentToolCall.from(json: ["name": toolName, "arguments": arguments]) ?? AgentToolCall(name: toolName, arguments: [:])
        } else {
            call = nil
        }
        return CodexResponsesStreamFrame(contentDelta: "", toolCall: call, isDone: true, failureMessage: nil)
    }
}

enum OpenAICodexTransport {
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
