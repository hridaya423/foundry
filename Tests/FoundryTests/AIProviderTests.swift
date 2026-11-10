import os
import XCTest
@testable import Foundry
import FoundryServices

final class AIProviderTests: XCTestCase {
    func testAIRequestsAreExplicitAndAppleFirst() {
        XCTAssertNil(AIProvider.request(from: "open safari"))

        let apple = AIProvider.request(from: "ask open my browser")
        XCTAssertEqual(apple?.prompt, "open my browser")
        XCTAssertEqual(apple?.backend, .appleFoundationModels)

        let ollama = AIProvider.request(from: "ollama summarize this")
        XCTAssertEqual(ollama?.prompt, "summarize this")
        XCTAssertEqual(ollama?.backend, .ollama)
    }

    func testMaterialPolicyUsesNativeGlassOnlyOnMacOS26WithoutReducedTransparency() {
        XCTAssertEqual(FoundryMaterialPolicy.rendering(osMajorVersion: 26, reduceTransparency: false), .nativeGlass)
        XCTAssertEqual(FoundryMaterialPolicy.rendering(osMajorVersion: 15, reduceTransparency: false), .legacyVisualEffect)
        XCTAssertEqual(FoundryMaterialPolicy.rendering(osMajorVersion: 26, reduceTransparency: true), .opaque)
    }

    func testPanelDismissalPolicyKeepsFoundryVisibleForOwnedWindows() {
        XCTAssertTrue(PanelDismissalPolicy.shouldDismiss(hasAttachedSheet: false, hasChildWindows: false, hasModalWindow: false))
        XCTAssertFalse(PanelDismissalPolicy.shouldDismiss(hasAttachedSheet: true, hasChildWindows: false, hasModalWindow: false))
        XCTAssertFalse(PanelDismissalPolicy.shouldDismiss(hasAttachedSheet: false, hasChildWindows: true, hasModalWindow: false))
        XCTAssertFalse(PanelDismissalPolicy.shouldDismiss(hasAttachedSheet: false, hasChildWindows: false, hasModalWindow: true))
    }

    func testAIRequestIdentifiersAreStableAndBackendSpecific() {
        let appleID = AIRequestIdentifier.make(prompt: " latest models ", backend: .appleFoundationModels)
        XCTAssertEqual(appleID, AIRequestIdentifier.make(prompt: "latest models", backend: .appleFoundationModels))
        XCTAssertNotEqual(appleID, AIRequestIdentifier.make(prompt: "latest models", backend: .ollama))
    }

    func testProviderPresetsCoverCloudVendorsAndLocalServers() {
        XCTAssertNotNil(AIProviderPreset.find("openai"))
        XCTAssertNotNil(AIProviderPreset.find("anthropic"))
        XCTAssertNotNil(AIProviderPreset.find("gemini"))
        XCTAssertNotNil(AIProviderPreset.find("openrouter"))
        XCTAssertNotNil(AIProviderPreset.find("lmstudio"))
        XCTAssertNotNil(AIProviderPreset.find("vllm"))
        XCTAssertEqual(AIProviderPreset.find("custom-openai-compatible")?.authentication, .optionalAPIKey)
    }

    func testCodexModelCatalogIncludesCurrentSubscriptionModels() throws {
        XCTAssertEqual(
            CodexModelPolicy.models.map(\.id),
            ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.2"]
        )
        XCTAssertEqual(CodexModelPolicy.defaultModel, "gpt-5.6-luna")
        let preset = try XCTUnwrap(AIProviderPreset.find("chatgpt-subscription"))
        XCTAssertEqual(preset.defaultModel, "gpt-5.6-luna")
        XCTAssertEqual(preset.makeProfile().requestOptions.reasoningEffort, "low")
        XCTAssertTrue(preset.capabilities.modelDiscovery)
    }

    func testCompatibleEndpointBuilderPreservesPresetVersionPaths() throws {
        let deepInfra = try XCTUnwrap(AIProviderPreset.find("deepinfra")?.makeProfile())
        let perplexity = try XCTUnwrap(AIProviderPreset.find("perplexity")?.makeProfile())

        XCTAssertEqual(AITransportSupport.endpoint(deepInfra, path: "chat/completions")?.path, "/v1/openai/chat/completions")
        XCTAssertEqual(AITransportSupport.endpoint(perplexity, path: "chat/completions")?.path, "/v1/chat/completions")
    }

    func testEndpointPolicyRejectsCredentialsAndFlagsRemotePlainHTTP() {
        XCTAssertEqual(AIEndpointPolicy.normalized(" https://example.com/v1/ "), "https://example.com/v1")
        XCTAssertNil(AIEndpointPolicy.normalized("https://user:secret@example.com/v1"))
        XCTAssertNil(AIEndpointPolicy.normalized("file:///tmp/model"))
        XCTAssertFalse(AIEndpointPolicy.requiresPlainHTTPWarning("http://127.0.0.1:1234/v1"))
        XCTAssertTrue(AIEndpointPolicy.requiresPlainHTTPWarning("http://example.com/v1"))
    }

    func testProfileResolverPreservesLegacyBackendSemantics() {
        var config = AIConfig()
        var ollama = AIProviderProfile.ollamaDefault
        ollama.enabled = true
        ollama.model = "qwen2.5"
        config.profiles = [AIProviderProfile.appleDefault, ollama]

        XCTAssertEqual(config.profile(for: .ollama).model, "qwen2.5")
        XCTAssertEqual(AIProfileResolver.defaultProfile(in: config).kind, .appleFoundationModels)
    }

    func testGenericFallbackPolicyRetriesAvailabilityAndRateLimitsOnly() {
        XCTAssertTrue(AIFallbackPolicy.shouldFallback(failureKind: .unavailable, hasFallback: true))
        XCTAssertTrue(AIFallbackPolicy.shouldFallback(failureKind: .rateLimited, hasFallback: true))
        XCTAssertFalse(AIFallbackPolicy.shouldFallback(failureKind: .configuration, hasFallback: true))
        XCTAssertFalse(AIFallbackPolicy.shouldFallback(failureKind: .unavailable, hasFallback: false))
    }

    func testCodexPKCEAndAuthorizationURLContainRequiredSecurityParameters() throws {
        let pkce = CodexPKCE.generate()
        XCTAssertGreaterThanOrEqual(pkce.verifier.count, 43)
        XCTAssertFalse(pkce.challenge.contains("="))
        let url = try XCTUnwrap(CodexOAuthHTTP.authorizeURL(redirectURI: "http://localhost:1455/auth/callback", pkce: pkce, state: "state-value"))
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first(where: { $0.name == "client_id" })?.value, CodexOAuthHTTP.clientID)
        XCTAssertEqual(query.first(where: { $0.name == "code_challenge_method" })?.value, "S256")
        XCTAssertEqual(query.first(where: { $0.name == "state" })?.value, "state-value")
        XCTAssertEqual(query.first(where: { $0.name == "originator" })?.value, "foundry")
    }

    func testCodexJWTExtractsAccountIDFromSupportedClaims() {
        let header = CodexOAuthSecurity.base64URL(Data(#"{"alg":"none"}"#.utf8))
        let payload = CodexOAuthSecurity.base64URL(Data(#"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct_nested"}}"#.utf8))
        XCTAssertEqual(OpenAIJWT.accountID(from: "\(header).\(payload).signature"), "acct_nested")
    }

    func testCodexStateComparisonIsConstantTimeCompatible() {
        XCTAssertTrue(CodexOAuthSecurity.constantTimeEqual("same-state", "same-state"))
        XCTAssertFalse(CodexOAuthSecurity.constantTimeEqual("same-state", "different-state"))
        XCTAssertFalse(CodexOAuthSecurity.constantTimeEqual("short", "shorter"))
    }

    func testCodexResponsesDecoderNormalizesTextAndFunctionCalls() {
        var decoder = CodexResponsesStreamDecoder()
        XCTAssertEqual(decoder.decode(line: #"data: {"type":"response.output_text.delta","delta":"Hello"}"#)?.contentDelta, "Hello")
        _ = decoder.decode(line: #"data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"provider-call","name":"system_context"}}"#)
        _ = decoder.decode(line: #"data: {"type":"response.function_call_arguments.done","arguments":"{}"}"#)
        let frame = decoder.decode(line: #"data: {"type":"response.completed"}"#)
        XCTAssertEqual(frame?.toolCall, AgentToolCall(id: "provider-call", name: "system_context", arguments: [:]))
        XCTAssertTrue(frame?.isDone == true)
    }

    func testCodexResponsesDecoderHandlesLongStreamWorkload() {
        let line = #"data: {"type":"response.output_text.delta","delta":"token"}"#
        var decodedFrames = 0

        measure {
            var decoder = CodexResponsesStreamDecoder()
            for _ in 0..<10_000 {
                if decoder.decode(line: line) != nil { decodedFrames += 1 }
            }
            _ = decoder.finish()
        }

        XCTAssertEqual(decodedFrames, 100_000)
    }

    func testOAuthCredentialRoundTripsAccountAndExpiry() throws {
        let credential = AICredential.oauth(AIOAuthCredential(accessToken: "access", refreshToken: "refresh", idToken: "id", accountID: "acct", expiresAt: Date(timeIntervalSince1970: 1234)))
        let data = try JSONEncoder().encode(credential)
        let restored = try JSONDecoder().decode(AICredential.self, from: data)
        XCTAssertEqual(restored, credential)
    }

    func testToolCallParserNormalizesStringArguments() {
        let call = AgentToolCall.from(json: [
            "name": "open_url",
            "arguments": ["url": "https://example.com"]
        ])

        XCTAssertEqual(call, AgentToolCall(name: "open_url", arguments: ["url": "https://example.com"]))
    }

    func testToolCallParserRejectsMissingName() {
        XCTAssertNil(AgentToolCall.from(json: ["arguments": [:]]))
    }

    func testToolTranscriptPreservesProviderCallIdentity() {
        var messages: [[String: Any]] = []
        let call = AgentToolCall(id: "call-provider-123", name: "web_search", arguments: ["query": "Swift"])

        AgentTranscript.appendToolExchange([(call, "Found it")], assistantText: "Searching", to: &messages)

        let assistantCall = (messages[0]["tool_calls"] as? [[String: Any]])?.first
        XCTAssertEqual(assistantCall?["id"] as? String, "call-provider-123")
        XCTAssertEqual(messages[1]["tool_call_id"] as? String, "call-provider-123")
    }

    func testToolTranscriptAnswersEveryParallelCall() {
        var messages: [[String: Any]] = []
        let first = AgentToolCall(id: "call-1", name: "web_search", arguments: ["query": "Swift"])
        let second = AgentToolCall(id: "call-2", name: "system_context", arguments: [:])

        AgentTranscript.appendToolExchange([(first, "A"), (second, "B")], assistantText: "", to: &messages)

        XCTAssertEqual((messages[0]["tool_calls"] as? [[String: Any]])?.compactMap { $0["id"] as? String }, ["call-1", "call-2"])
        XCTAssertEqual(messages.dropFirst().compactMap { $0["tool_call_id"] as? String }, ["call-1", "call-2"])
        XCTAssertEqual(messages.dropFirst().compactMap { $0["content"] as? String }, ["A", "B"])
    }

    func testOpenAICompatibleStreamSkipsNonJSONLinesAndKeepsParallelToolCallsApart() async throws {
        let response = try await OpenAICompatibleTransport.decodeStream(lines: Self.lines([
            ": keep-alive",
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"a","function":{"name":"web_search","arguments":"{\"query\":"}}]}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":1,"id":"b","function":{"name":"open_url","arguments":"{\"url\":"}}]}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"Swift\"}"}}]}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":1,"function":{"arguments":"\"https://example.com\"}"}}]}}]}"#,
            "data: [DONE]"
        ]))

        guard case let .toolCalls(calls, _) = response else { return XCTFail("Expected tool calls, got \(response)") }
        XCTAssertEqual(calls, [
            AgentToolCall(id: "a", name: "web_search", arguments: ["query": "Swift"]),
            AgentToolCall(id: "b", name: "open_url", arguments: ["url": "https://example.com"])
        ])
    }

    func testOpenAICompatibleStreamSurfacesAMidStreamError() async throws {
        let response = try await OpenAICompatibleTransport.decodeStream(lines: Self.lines([
            #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#,
            #"data: {"error":{"message":"Rate limit reached","type":"rate_limit_exceeded"}}"#
        ]))

        guard case let .failure(message, kind) = response else { return XCTFail("Expected a failure, got \(response)") }
        XCTAssertEqual(kind, .rateLimited)
        XCTAssertTrue(message.contains("Rate limit reached"), message)
    }

    func testAnthropicStreamKeepsParallelToolUseBlocksApartAndSurfacesErrors() async throws {
        let calls = try await AnthropicTransport.decodeStream(lines: Self.lines([
            "event: ping",
            "data: not json",
            "event: content_block_start",
            #"data: {"index":0,"content_block":{"type":"tool_use","id":"a","name":"web_search"}}"#,
            "event: content_block_start",
            #"data: {"index":1,"content_block":{"type":"tool_use","id":"b","name":"system_context"}}"#,
            "event: content_block_delta",
            #"data: {"index":0,"delta":{"partial_json":"{\"query\":\"Swift\"}"}}"#,
            "event: content_block_delta",
            #"data: {"index":1,"delta":{"partial_json":"{}"}}"#
        ]))
        guard case let .toolCalls(decoded, _) = calls else { return XCTFail("Expected tool calls, got \(calls)") }
        XCTAssertEqual(decoded, [
            AgentToolCall(id: "a", name: "web_search", arguments: ["query": "Swift"]),
            AgentToolCall(id: "b", name: "system_context", arguments: [:])
        ])

        let failure = try await AnthropicTransport.decodeStream(lines: Self.lines([
            "event: content_block_delta",
            #"data: {"index":0,"delta":{"text":"Partial"}}"#,
            "event: error",
            #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        ]))
        guard case let .failure(_, kind) = failure else { return XCTFail("Expected a failure, got \(failure)") }
        XCTAssertEqual(kind, .unavailable)
    }

    func testGeminiStreamKeepsEveryFunctionCallAndSurfacesErrors() async throws {
        let calls = try await GeminiTransport.decodeStream(lines: Self.lines([
            "",
            #"data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"web_search","args":{"query":"Swift"}}},"#
                + #"{"functionCall":{"name":"system_context","args":{}}}]}}]}"#
        ]))
        guard case let .toolCalls(decoded, _) = calls else { return XCTFail("Expected tool calls, got \(calls)") }
        XCTAssertEqual(decoded.map(\.name), ["web_search", "system_context"])

        let failure = try await GeminiTransport.decodeStream(lines: Self.lines([
            #"data: {"error":{"code":429,"message":"Quota","status":"RESOURCE_EXHAUSTED"}}"#
        ]))
        guard case let .failure(_, kind) = failure else { return XCTFail("Expected a failure, got \(failure)") }
        XCTAssertEqual(kind, .rateLimited)
    }

    private static func lines(_ values: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            values.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }

    func testOpenAICompatibleTranscriptEncodesToolArgumentsAsJSON() throws {
        var messages: [[String: Any]] = []
        AgentTranscript.appendToolExchange(
            [(AgentToolCall(name: "web_search", arguments: ["query": "Swift"]), "Found it")],
            assistantText: "Searching",
            to: &messages
        )

        let encoded = OpenAICompatibleTransport.messages(from: messages)
        let call = try XCTUnwrap((encoded[0]["tool_calls"] as? [[String: Any]])?.first)
        let function = try XCTUnwrap(call["function"] as? [String: Any])
        let arguments = try XCTUnwrap(function["arguments"] as? String)

        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: String],
            ["query": "Swift"]
        )
    }

    @MainActor
    func testQuickAIMergesMutationsMadeBeforeInitialLoadCompletes() async throws {
        var existing = AIChatThread(title: "Existing")
        existing.messages.append(.init(role: .user, content: "earlier"))
        let store = DelayedAIChatStore(threads: [existing])
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config = ConfigService(diagnostics: DiagnosticsService(), url: configURL)
        let state = QuickAIState(aiProvider: AIProvider(config: config, diagnostics: DiagnosticsService()), chatStore: store)

        state.startNewThread(selectedAIProfileID: nil)
        state.quickAIThreads[0].messages.append(.init(role: .user, content: "hi"))
        state.useProfile(UUID())
        store.finishLoading()
        await waitUntil { store.savedThreads().count >= 2 }

        let saved = store.savedThreads()
        XCTAssertEqual(Set(saved.map(\.id)), Set([existing.id, state.quickAIThreads.first { $0.title == "New Chat" }!.id]))
    }

    @MainActor
    func testQuickAIShutdownFlushesPendingSave() {
        let store = DelayedAIChatStore(threads: [])
        store.finishLoading()
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config = ConfigService(diagnostics: DiagnosticsService(), url: configURL)
        let state = QuickAIState(aiProvider: AIProvider(config: config, diagnostics: DiagnosticsService()), chatStore: store)

        state.startNewThread(selectedAIProfileID: nil)
        state.quickAIThreads[0].messages.append(.init(role: .user, content: "hi"))
        state.shutdown()

        let saved = store.savedThreads()
        XCTAssertEqual(saved.map(\.title), ["New Chat"])
    }

    @MainActor
    func testOpeningQuickAIDoesNotCreateEmptyThreads() {
        let store = DelayedAIChatStore(threads: [])
        store.finishLoading()
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config = ConfigService(diagnostics: DiagnosticsService(), url: configURL)
        let state = QuickAIState(aiProvider: AIProvider(config: config, diagnostics: DiagnosticsService()), chatStore: store)

        state.startNewThread(selectedAIProfileID: nil)
        state.startNewThread(selectedAIProfileID: nil)
        state.startNewThread(selectedAIProfileID: nil)
        state.shutdown()

        XCTAssertEqual(state.quickAIThreads.count, 1, "reopening reuses the one blank chat")
        XCTAssertEqual(store.savedThreads(), [], "a chat is saved once it has a message")
    }

    @MainActor
    func testModelMenuDoesNotChangeDefaultProfile() {
        let store = DelayedAIChatStore(threads: [])
        store.finishLoading()
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config = ConfigService(diagnostics: DiagnosticsService(), url: configURL)
        let state = QuickAIState(aiProvider: AIProvider(config: config, diagnostics: DiagnosticsService()), chatStore: store)
        let settings = AISettingsState(config: config, diagnostics: DiagnosticsService())
        state.startNewThread(selectedAIProfileID: settings.defaultAIProfileID)
        let defaultBefore = settings.defaultAIProfileID
        let other = UUID()

        QuickAIModelMenu(quickAI: state, aiSettings: settings, openAISettings: {}).choose(other)

        XCTAssertEqual(state.activeProfileID, other)
        XCTAssertEqual(settings.defaultAIProfileID, defaultBefore)
        XCTAssertEqual(config.current.ai.defaultProfileID, defaultBefore)
        state.shutdown()
    }

    @MainActor
    func testEmptyReturnDoesNothingAndDeletingTheOpenChatMovesToTheNext() async {
        let store = DelayedAIChatStore(threads: [])
        store.finishLoading()
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config = ConfigService(diagnostics: DiagnosticsService(), url: configURL)
        let state = QuickAIState(aiProvider: AIProvider(config: config, diagnostics: DiagnosticsService()), chatStore: store)
        let older = AIChatThread(title: "Older", messages: [.init(role: .user, content: "a")])
        let newer = AIChatThread(title: "Newer", messages: [.init(role: .user, content: "b")])
        state.quickAIThreads = [newer, older]
        state.selectThread(newer)
        let status = state.quickAIStatus

        state.quickAIQuery = "   "
        await state.submit()
        XCTAssertEqual(state.quickAIStatus, status)
        XCTAssertFalse(state.isQuickAILoading)

        state.deleteThread(id: newer.id)
        XCTAssertEqual(state.quickAIThreads.map(\.title), ["Older"])
        XCTAssertEqual(state.activeQuickAIThreadID, older.id)
        state.shutdown()
    }

    @MainActor
    func testPickingAModelAppliesToTheCurrentChat() {
        let store = DelayedAIChatStore(threads: [])
        store.finishLoading()
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config = ConfigService(diagnostics: DiagnosticsService(), url: configURL)
        let state = QuickAIState(aiProvider: AIProvider(config: config, diagnostics: DiagnosticsService()), chatStore: store)
        state.startNewThread(selectedAIProfileID: nil)
        state.quickAIThreads[0].messages.append(.init(role: .user, content: "hi"))
        let defaultBefore = config.current.ai.defaultProfileID
        let profile = UUID()
        state.useProfile(profile)
        XCTAssertEqual(state.activeProfileID, profile)
        state.shutdown()
        XCTAssertEqual(store.savedThreads().first?.providerProfileID, profile)
        XCTAssertEqual(config.current.ai.defaultProfileID, defaultBefore, "the model menu changes this chat, not the default")
    }

    @MainActor
    func testProviderFailureIsShownAsAnErrorNotAnAnswer() async {
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config = ConfigService(diagnostics: DiagnosticsService(), url: configURL)
        let unreachable = AIProviderProfile(name: "Closed port", kind: .openAICompatible, authentication: .none,
            endpoint: "http://127.0.0.1:9", model: "none")
        var ai = config.current.ai
        ai.profiles = [unreachable]
        ai.defaultProfileID = unreachable.id
        ai.fallbackProfileIDs = []
        try? config.updateAIConfig(ai)
        let state = QuickAIState(aiProvider: AIProvider(config: config, diagnostics: DiagnosticsService()),
            chatStore: AIChatStore(url: configURL.appendingPathExtension("chats")))
        state.startNewThread(selectedAIProfileID: unreachable.id)
        state.quickAIQuery = "hello"
        await state.submit()
        await waitUntil { state.isQuickAILoading == false }
        XCTAssertEqual(state.quickAIResponse, "")
        XCTAssertNotNil(state.quickAIError)
        XCTAssertEqual(state.quickAILastFailedPrompt, "hello")
        XCTAssertEqual(state.activeThread?.messages.map(\.role), [.user])
        state.shutdown()
    }

    @MainActor
    func testStoppingKeepsThePartialAnswerAndOnlyOffersRetryWhenNothingArrived() {
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config = ConfigService(diagnostics: DiagnosticsService(), url: configURL)
        let state = QuickAIState(aiProvider: AIProvider(config: config, diagnostics: DiagnosticsService()), chatStore: AIChatStore(url: configURL.appendingPathExtension("chats")))
        state.startNewThread(selectedAIProfileID: nil)
        let threadID = try! XCTUnwrap(state.activeQuickAIThreadID)
        state.isQuickAILoading = true

        state.finishCancelled(prompt: "question", partial: "half an answer", threadID: threadID)
        XCTAssertFalse(state.isQuickAILoading)
        XCTAssertEqual(state.activeThread?.messages.last?.content, "half an answer")
        XCTAssertNil(state.quickAILastFailedPrompt)

        state.finishCancelled(prompt: "second", partial: "", threadID: threadID)
        XCTAssertEqual(state.activeThread?.messages.count, 1)
        XCTAssertEqual(state.quickAILastFailedPrompt, "second")
    }

    @MainActor
    func testQuickAISelectingThreadClearsLoadingState() {
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config = ConfigService(diagnostics: DiagnosticsService(), url: configURL)
        let state = QuickAIState(aiProvider: AIProvider(config: config, diagnostics: DiagnosticsService()),
            chatStore: AIChatStore(url: configURL.appendingPathExtension("chats")))
        let thread = AIChatThread(title: "Other chat")
        state.isQuickAILoading = true

        state.selectThread(thread)

        XCTAssertFalse(state.isQuickAILoading)
        XCTAssertEqual(state.activeQuickAIThreadID, thread.id)
    }

    @MainActor
    func testQuickAIShutdownKeepsTheLatestStateWhenAnOlderSaveIsInFlight() async throws {
        let store = BlockingAIChatStore()
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config = ConfigService(diagnostics: DiagnosticsService(), url: configURL)
        let state = QuickAIState(aiProvider: AIProvider(config: config, diagnostics: DiagnosticsService()), chatStore: store)

        state.startNewThread(selectedAIProfileID: nil)
        while store.saveStarted() == false {
            try await Task.sleep(for: .milliseconds(10))
        }
        state.startNewThread(selectedAIProfileID: nil)
        state.quickAIThreads[0].messages.append(.init(role: .user, content: "latest"))
        let latest = state.quickAIThreads

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { store.releaseSave() }
        state.shutdown()
        while store.savedSnapshots().count < 2 { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertEqual(store.savedSnapshots().last, latest)
    }

    @MainActor
    func testQuickAIShutdownDoesNotReplaceAnUnreadableArchive() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: url)
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config = ConfigService(diagnostics: DiagnosticsService(), url: configURL)
        let state = QuickAIState(
            aiProvider: AIProvider(config: config, diagnostics: DiagnosticsService()),
            chatStore: AIChatStore(url: url)
        )

        state.shutdown()

        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testOllamaStreamDecoderReadsContentAndDoneFrames() {
        var decoder = OllamaStreamDecoder()

        let delta = decoder.decode(line: #"{"message":{"content":"Hello"},"done":false}"#)
        XCTAssertEqual(delta, OllamaStreamFrame(contentDelta: "Hello", toolCall: nil, isDone: false))

        let done = decoder.decode(line: #"{"message":{"content":""},"done":true}"#)
        XCTAssertEqual(done?.isDone, true)
    }

    func testOllamaStreamDecoderReadsToolCallFrame() {
        var decoder = OllamaStreamDecoder()
        let frame = decoder.decode(line: #"{"message":{"tool_calls":[{"function":{"name":"open_url","arguments":{"url":"https://example.com"}}}]},"done":true}"#)

        XCTAssertEqual(frame?.toolCall, AgentToolCall(name: "open_url", arguments: ["url": "https://example.com"]))
        XCTAssertEqual(frame?.isDone, true)
    }

    func testAgentProtocolDecoderUnwrapsFinalString() {
        XCTAssertEqual(
            AgentProtocolDecoder.finalContent(from: #"{"type":"final","content":"17:12"}"#),
            "17:12"
        )
    }

    func testAgentProtocolDecoderUnwrapsStructuredAnswer() {
        XCTAssertEqual(
            AgentProtocolDecoder.finalContent(from: #"{"type":"final","content":{"answer":2}}"#),
            "2"
        )
    }

    func testAgentProtocolDecoderFindsFinalAfterToolTranscript() {
        let response = "Tool system_context returned:\nCurrent local date and time: July 14\n{\"type\":\"final\",\"content\":\"July 14\"}"
        XCTAssertEqual(AgentProtocolDecoder.finalContent(from: response), "July 14")
    }

    func testAgentProtocolDecoderReadsPrettyPrintedFinalAfterProse() {
        let response = """
        From the search results, the answer is clear.
        Final Answer:
        ```json
        {
          "type": "final",
          "content": {
            "latest_openai_model": "GPT-5.6 Sol"
          }
        }
        ```
        """
        XCTAssertEqual(AgentProtocolDecoder.finalContent(from: response), "GPT-5.6 Sol")
    }

    func testAgentProtocolDecoderFormatsStandaloneObjectWithoutJSON() {
        XCTAssertEqual(
            AgentProtocolDecoder.displayContent(from: #"{"month":"October","year":"2024"}"#),
            "October 2024"
        )
    }

    func testAgentProtocolDecoderFormatsSingleValueObjectWithoutJSON() {
        XCTAssertEqual(AgentProtocolDecoder.displayContent(from: #"{"value":"x=1"}"#), "x=1")
    }

    func testAgentProtocolDecoderFormatsArrayAsBullets() {
        XCTAssertEqual(
            AgentProtocolDecoder.displayContent(from: #"{"latest_ai_models":["GPT-5.6 Sol","Gemini 3"]}"#),
            "• GPT-5.6 Sol\n• Gemini 3"
        )
    }

    @MainActor
    func testQuickAIUsesCompactPanelSize() {
        XCTAssertEqual(PanelController.contentSize(for: .search), PanelController.contentSize(for: .quickAI))
        XCTAssertEqual(PanelController.contentSize(for: .quickAI).height, 495)
    }

    @MainActor
    func testEveryPanelModeUsesTheSameFixedSize() {
        let modes: [CommandPanelState.Mode] = [
            .search,
            .quickAI,
            .emojiPicker,
            .fileShelf,
            .clipboardHistory,
            .snippets,
            .fileConversion,
            .translator,
            .developerTools
        ]

        for mode in modes {
            XCTAssertEqual(PanelController.contentSize(for: mode), NSSize(width: 750, height: 495))
        }
    }

    func testWebSearchHTMLParserExtractsCleanResults() {
        let html = """
        <a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fopenai.com%2Fresearch&amp;rut=x"><b>OpenAI</b> Research &amp; Releases</a>
        <a class="result__snippet" href="x">Latest model release details &amp; benchmarks.</a>
        """
        XCTAssertEqual(
            WebSearchHTMLParser.parse(Data(html.utf8)),
            [WebSearchResult(title: "OpenAI Research & Releases", url: "https://openai.com/research", summary: "Latest model release details & benchmarks.")]
        )
    }

    func testDuckDuckGoParserRejectsAdRedirects() {
        let html = """
        <a class="result__a" href="https://duckduckgo.com/y.js?ad_domain=example.com">Sponsored result</a>
        <a class="result__snippet" href="x">Advertisement</a>
        """

        XCTAssertTrue(WebSearchHTMLParser.parse(Data(html.utf8)).isEmpty)
    }

    func testBraveSearchParserExtractsEmbeddedWebResults() {
        let html = #"""
        <script>web:{type:"search",results:[{title:"Previewing GPT-5.6 Sol: a next-generation model | OpenAI",url:"https://openai.com/index/previewing-gpt-5-6-sol/",full_title:void 0,description:"OpenAI previews <strong>GPT-5.6 Sol</strong>, a new flagship model."}]}</script>
        """#

        XCTAssertEqual(
            BraveSearchHTMLParser.parse(Data(html.utf8)),
            [WebSearchResult(
                title: "Previewing GPT-5.6 Sol: a next-generation model | OpenAI",
                url: "https://openai.com/index/previewing-gpt-5-6-sol/",
                summary: "OpenAI previews GPT-5.6 Sol, a new flagship model."
            )]
        )
    }

    func testAutonomousAICapabilitiesAreReadOnly() {
        XCTAssertEqual(AICapabilityPolicy.autonomousToolNames, ["system_context", "web_search"])
        XCTAssertFalse(AICapabilityPolicy.autonomousToolNames.contains("read_clipboard"))
        XCTAssertFalse(AICapabilityPolicy.autonomousToolNames.contains("copy_text"))
        XCTAssertFalse(AICapabilityPolicy.autonomousToolNames.contains("open_url"))
        XCTAssertFalse(AICapabilityPolicy.autonomousToolNames.contains("open_app"))
    }

    func testFallbackOnlyUsesOllamaForAppleAvailabilityFailures() {
        XCTAssertTrue(AIFallbackPolicy.shouldFallback(failureKind: .unavailable, backend: .appleFoundationModels, ollamaEnabled: true, isCancelled: false))
        XCTAssertFalse(AIFallbackPolicy.shouldFallback(failureKind: .refusal, backend: .appleFoundationModels, ollamaEnabled: true, isCancelled: false))
        XCTAssertFalse(AIFallbackPolicy.shouldFallback(failureKind: .guardrail, backend: .appleFoundationModels, ollamaEnabled: true, isCancelled: false))
        XCTAssertFalse(AIFallbackPolicy.shouldFallback(failureKind: .unavailable, backend: .ollama, ollamaEnabled: true, isCancelled: false))
        XCTAssertFalse(AIFallbackPolicy.shouldFallback(failureKind: .unavailable, backend: .appleFoundationModels, ollamaEnabled: false, isCancelled: false))
    }

    func testWebSearchURLPolicyRejectsUnsafeHostsAndSchemes() {
        XCTAssertTrue(WebSearchURLPolicy.isAllowed("https://example.com/article"))
        XCTAssertFalse(WebSearchURLPolicy.isAllowed("httpx://example.com/article"))
        XCTAssertFalse(WebSearchURLPolicy.isAllowed("http://localhost:8080/"))
        XCTAssertFalse(WebSearchURLPolicy.isAllowed("http://127.0.0.1/"))
        XCTAssertFalse(WebSearchURLPolicy.isAllowed("http://192.168.1.10/"))
        XCTAssertFalse(WebSearchURLPolicy.isAllowed("http://169.254.169.254/latest/"))
    }

    func testWebSearchURLPolicyAllowsFcAndFdHostnamesButRejectsPrivateIPv6() {
        for url in ["https://www.fcc.gov/x", "https://fda.gov/", "https://fd.nl/", "https://fcbarcelona.com/"] {
            XCTAssertTrue(WebSearchURLPolicy.isAllowed(url), url)
        }
        for url in ["http://[fd00::1]/", "http://[fc00::1]/", "http://[fe80::1]/", "http://[::1]/"] {
            XCTAssertFalse(WebSearchURLPolicy.isAllowed(url), url)
        }
    }

    func testAnthropicConnectionTestFailsWithoutAStoredKey() async {
        let profile = AIProviderProfile(name: "Anthropic", kind: .anthropic, authentication: .apiKey, model: "claude")
        let result = await AnthropicTransport.test(profile: profile, credentials: EmptyCredentialStore())
        XCTAssertTrue(result.isFailure)
    }

    func testGeminiConnectionTestFailsWithoutAStoredKey() async {
        let profile = AIProviderProfile(name: "Gemini", kind: .gemini, authentication: .apiKey, model: "gemini")
        let result = await GeminiTransport.test(profile: profile, credentials: EmptyCredentialStore())
        XCTAssertTrue(result.isFailure)
    }

    func testAPIKeyIsOnlyReleasedOverHTTPSOrLoopback() throws {
        let store = StaticKeyCredentialStore()
        for endpoint in ["https://api.example.com/v1", "http://127.0.0.1:1234/v1", "http://localhost:8080", "http://[::1]:8080"] {
            let profile = AIProviderProfile(name: "Server", kind: .openAICompatible, authentication: .apiKey, endpoint: endpoint, model: "m")
            XCTAssertEqual(try AITransportSupport.apiKey(profile, store: store), "secret", endpoint)
        }
        for endpoint in ["http://api.example.com/v1", "http://192.168.1.4:1234/v1", "http://127.0.0.1.example.com/v1"] {
            let profile = AIProviderProfile(name: "Server", kind: .openAICompatible, authentication: .optionalAPIKey, endpoint: endpoint, model: "m")
            XCTAssertThrowsError(try AITransportSupport.apiKey(profile, store: store), endpoint)
        }
    }

    func testAnthropicConnectionTestRefusesAPlainHTTPRemoteEndpoint() async {
        let profile = AIProviderProfile(name: "Anthropic", kind: .anthropic, authentication: .apiKey, endpoint: "http://api.example.com/v1",
            model: "claude")
        let result = await AnthropicTransport.test(profile: profile, credentials: StaticKeyCredentialStore())
        XCTAssertTrue(result.isFailure)
        XCTAssertTrue(result.message.contains("HTTPS"), result.message)
    }

    func testProviderRedirectThatChangesSchemeIsNotFollowed() async throws {
        defer { RedirectingURLProtocol.reset() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectingURLProtocol.self]
        let session = URLSession(configuration: configuration, delegate: AIProviderSessionDelegate(), delegateQueue: nil)
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://api.example.com/v1/models")))
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 302)
        XCTAssertEqual(RedirectingURLProtocol.requestedURLs(), ["https://api.example.com/v1/models"])
    }

    func testIntentHeuristicsRequireLiveSearchForFreshFacts() {
        XCTAssertTrue(AIIntentHeuristics.needsWebSearch("What is the latest macOS release?"))
        XCTAssertTrue(AIIntentHeuristics.needsWebSearch("current weather in San Francisco"))
        XCTAssertFalse(AIIntentHeuristics.needsWebSearch("Explain dependency injection"))
    }

    func testIntentHeuristicsRequireSystemContextForLocalFacts() {
        XCTAssertTrue(AIIntentHeuristics.needsSystemContext("What time is it?"))
        XCTAssertTrue(AIIntentHeuristics.needsSystemContext("Which app is frontmost on my Mac?"))
        XCTAssertFalse(AIIntentHeuristics.needsSystemContext("Explain Swift actors"))
    }

    func testSearchQueriesRejectURLsAndKeepDistinctTextQueries() {
        XCTAssertEqual(
            WebSearchQuerySet.validated([
                "latest ai models",
                "https://www.apple.com/artificial-intelligence/",
                "site:openai.com latest GPT model official release 2026",
                "latest OpenAI model",
                "LATEST AI MODELS",
            ], maxCount: 4),
            ["latest ai models", "site:openai.com latest GPT model official release 2026", "latest OpenAI model"]
        )
    }

    func testPageTextExtractorRemovesNonContentTags() {
        let html = "<html><script>ignore()</script><style>.x{}</style><main>Introducing GPT-5.6 Sol &amp; details</main></html>"
        XCTAssertEqual(WebPageTextExtractor.extract(data: Data(html.utf8), limit: 100), "Introducing GPT-5.6 Sol & details")
    }

    func testConciseGroundedAnswerDropsUnrequestedDetailsAndUnknownSources() {
        let results = [WebSearchResult(title: "Release", url: "https://example.com/release", summary: "Muse Spark 1.1 released today.")]
        let formatted = GroundedAnswerFormatter.format(
            answer: "Muse Spark 1.1 by Meta.\nAnthropic: Claude 3.5\nDeepMind: Gemini 1.5 Ultra",
            details: ["DeepSeek R1"],
            sourceURLs: ["https://untrusted.example", "https://example.com/release"],
            results: results,
            detailed: false
        )
        XCTAssertEqual(formatted, "Muse Spark 1.1 by Meta.\n\nSources:\n• https://example.com/release")
    }

    func testDetailedGroundedAnswerKeepsRequestedSupportedDetails() {
        let results = [WebSearchResult(title: "Release", url: "https://example.com/release", summary: "Release details")]
        let formatted = GroundedAnswerFormatter.format(
            answer: "Muse Spark 1.1 is the newest release found.",
            details: ["It was released by Meta."],
            sourceURLs: ["https://example.com/release"],
            results: results,
            detailed: true
        )
        XCTAssertTrue(formatted.contains("• It was released by Meta."))
    }

    func testGroundedListKeepsOnlySpecificItemsNamedByTheirSources() {
        let results = [
            WebSearchResult(title: "Meta releases Muse Spark 1.1", url: "https://example.com/meta", summary: "Meta announced Muse Spark 1.1 today."),
            WebSearchResult(title: "OpenAI launches GPT-5.6", url: "https://example.com/openai", summary: "OpenAI released GPT-5.6 for developers."),
            WebSearchResult(title: "Anthropic ships Claude Opus 4.2", url: "https://example.com/anthropic", summary: "Anthropic introduced Claude Opus 4.2."),
        ]
        let formatted = GroundedListFormatter.format(
            items: [
                GroundedListItem(name: "Muse Spark 1.1", sourceURL: "https://example.com/meta"),
                GroundedListItem(name: "GPT-5.6", sourceURL: "https://example.com/openai"),
                GroundedListItem(name: "Claude Opus 4.2", sourceURL: "https://example.com/anthropic"),
                GroundedListItem(name: "Gemini Ultra", sourceURL: "https://untrusted.example"),
            ],
            results: results,
            requestedCount: 3
        )

        XCTAssertTrue(formatted.contains("1. **Muse Spark 1.1**"))
        XCTAssertTrue(formatted.contains("2. **GPT-5.6**"))
        XCTAssertTrue(formatted.contains("3. **Claude Opus 4.2**"))
        XCTAssertFalse(formatted.contains("Gemini Ultra"))
    }

    func testGroundedListRejectsItemsNotNamedBySources() {
        let results = [
            WebSearchResult(title: "AI model tracker", url: "https://example.com/tracker", summary: "OpenAI and Anthropic continue to release models."),
        ]
        let formatted = GroundedListFormatter.format(
            items: [
                GroundedListItem(name: "Claude Opus 4.2", sourceURL: "https://example.com/tracker"),
            ],
            results: results,
            requestedCount: 3
        )

        XCTAssertEqual(formatted, "I couldn't identify specific items explicitly named by the live search results.")
    }

    func testGroundedListReportsWhenFewerItemsCanBeVerified() {
        let results = [WebSearchResult(title: "Meta releases Muse Spark 1.1", url: "https://example.com/meta", summary: "Meta announced Muse Spark 1.1 today.")]
        let formatted = GroundedListFormatter.format(
            items: [GroundedListItem(name: "Muse Spark 1.1", sourceURL: "https://example.com/meta")],
            results: results,
            requestedCount: 3
        )

        XCTAssertTrue(formatted.hasPrefix("I could only verify 1 of the requested 3 items:"))
    }

    func testGroundedListDropsDuplicateItems() {
        let results = [
            WebSearchResult(title: "Release list", url: "https://example.com/one", summary: "GPT-5.6 Sol and GPT-5.2 Thinking are available."),
        ]
        let formatted = GroundedListFormatter.format(
            items: [
                GroundedListItem(name: "GPT-5.6 Sol", sourceURL: "https://example.com/one"),
                GroundedListItem(name: "GPT-5.6 Sol", sourceURL: "https://example.com/one"),
            ],
            results: results,
            requestedCount: 3
        )

        XCTAssertTrue(formatted.contains("I could only verify 1 of the requested 3 items:"))
        XCTAssertFalse(formatted.contains("2. **GPT-5.6 Sol**"))
    }

    func testGroundedWebFallbackReturnsVerifiedSourcesInsteadOfGenericFailure() {
        let results = [
            WebSearchResult(title: "Introducing Model One", url: "https://example.com/one", summary: "Release details"),
            WebSearchResult(title: "Introducing Model Two", url: "https://example.com/two", summary: "Release details"),
            WebSearchResult(title: "Introducing Model Three", url: "https://example.com/three", summary: "Release details"),
        ]
        let formatted = GroundedWebFallbackFormatter.format(
            results: results,
            wantsList: true,
            requestedItemCount: 3
        )

        XCTAssertTrue(formatted.contains("1. **Introducing Model One**"))
        XCTAssertTrue(formatted.contains("3. **Introducing Model Three**"))
        XCTAssertTrue(formatted.contains("Release details"))
        XCTAssertFalse(formatted.contains("Apple Intelligence could not complete"))
    }

    func testWebEvidenceFormattingIsBounded() {
        let results = (1...5).map { index in
            WebSearchResult(title: "Result \(index)", url: "https://example.com/\(index)", summary: String(repeating: "x", count: 500))
        }
        let formatted = WebSearch.formatted(results)
        XCTAssertTrue(formatted.contains("Result 3"))
        XCTAssertFalse(formatted.contains("Result 4"))
        XCTAssertLessThan(formatted.count, 1400)
    }

    func testToolEventRoundTripsAndDecodesLegacyMessages() {
        let running = AIChatMessage.tool(.init(name: "search", result: nil))
        XCTAssertEqual(running.toolEvent, .init(name: "search", result: nil))
        XCTAssertTrue(running.toolEvent?.isRunning == true)
        let legacy = AIChatMessage(role: .tool, content: "complete:search\nline 1\nline 2")
        XCTAssertEqual(legacy.toolEvent, .init(name: "search", result: "line 1\nline 2"))
        XCTAssertEqual(legacy.toolEvent?.encoded, legacy.content)
        XCTAssertNil(AIChatMessage(role: .assistant, content: "running:x").toolEvent)
    }

    func testParallelToolResultsReturnInOneTurn() throws {
        var messages: [[String: Any]] = [["role": "user", "content": "weather in two cities"]]
        AgentTranscript.appendToolExchange([
            (AgentToolCall(id: "a", name: "web_search", arguments: ["query": "paris"]), "sunny"),
            (AgentToolCall(id: "b", name: "web_search", arguments: ["query": "rome"]), "rain")
        ], assistantText: "", to: &messages)

        let anthropic = AnthropicTransport.anthropicMessages(messages)
        XCTAssertEqual(anthropic.map { $0["role"] as? String }, ["user", "assistant", "user"])
        let results = try XCTUnwrap(anthropic.last?["content"] as? [[String: Any]])
        XCTAssertEqual(results.map { $0["tool_use_id"] as? String }, ["a", "b"])

        let gemini = GeminiTransport.geminiContents(messages)
        XCTAssertEqual(gemini.map { $0["role"] as? String }, ["user", "model", "user"])
        let parts = try XCTUnwrap(gemini.last?["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
    }
}

private final class DelayedAIChatStore: Sendable, AIChatStoring {
    private struct Box {
        var continuation: CheckedContinuation<Void, Never>?
        var canLoad = false
        var saved: [AIChatThread] = []
    }

    private let threads: [AIChatThread]
    private let box = OSAllocatedUnfairLock(uncheckedState: Box())

    init(threads: [AIChatThread]) {
        self.threads = threads
    }

    func load() -> [AIChatThread] { threads }

    func loadAsync() async -> [AIChatThread] {
        let shouldWait = box.withLockUnchecked { $0.canLoad == false }
        if shouldWait {
            await withCheckedContinuation { continuation in
                box.withLockUnchecked { $0.continuation = continuation }
            }
        }
        return threads
    }

    func save(_ threads: [AIChatThread]) {
        box.withLockUnchecked { $0.saved = threads }
    }

    func finishLoading() {
        let continuation = box.withLockUnchecked { box in
            box.canLoad = true
            defer { box.continuation = nil }
            return box.continuation
        }
        continuation?.resume()
    }

    func savedThreads() -> [AIChatThread] {
        box.withLockUnchecked { $0.saved }
    }
}

private final class BlockingAIChatStore: Sendable, AIChatStoring {
    private struct Box {
        var shouldBlockNextSave = true
        var hasStartedSave = false
        var snapshots: [[AIChatThread]] = []
    }

    private let box = OSAllocatedUnfairLock(uncheckedState: Box())
    private let saveGate = DispatchSemaphore(value: 0)

    func load() -> [AIChatThread] { [] }
    func loadAsync() async -> [AIChatThread] { [] }

    func save(_ threads: [AIChatThread]) {
        let shouldBlock = box.withLockUnchecked { box in
            box.hasStartedSave = true
            guard box.shouldBlockNextSave else { return false }
            box.shouldBlockNextSave = false
            return true
        }
        if shouldBlock { saveGate.wait() }
        box.withLockUnchecked { $0.snapshots.append(threads) }
    }

    func saveStarted() -> Bool {
        box.withLockUnchecked { $0.hasStartedSave }
    }

    func releaseSave() {
        saveGate.signal()
    }

    func savedSnapshots() -> [[AIChatThread]] {
        box.withLockUnchecked { $0.snapshots }
    }
}

private struct StaticKeyCredentialStore: AICredentialStore {
    func credential(for profileID: UUID) throws -> AICredential? { .apiKey("secret") }
    func save(_ credential: AICredential, for profileID: UUID) throws {}
    func delete(for profileID: UUID) throws {}
}

private final class RedirectingURLProtocol: URLProtocol {
    private static let urls = OSAllocatedUnfairLock<[String]>(initialState: [])

    static func requestedURLs() -> [String] { urls.withLock { $0 } }
    static func reset() { urls.withLock { $0 = [] } }

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.urls.withLock { $0.append(url.absoluteString) }
        if url.scheme == "https", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "http"
            let destination = components.url!
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": destination.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: destination), redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct EmptyCredentialStore: AICredentialStore {
    func credential(for profileID: UUID) throws -> AICredential? { nil }
    func save(_ credential: AICredential, for profileID: UUID) throws {}
    func delete(for profileID: UUID) throws {}
}
