import Foundation

final class AIProviderSessionDelegate: NSObject, URLSessionTaskDelegate {
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
