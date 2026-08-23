import XCTest
@testable import Foundry

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
        let profile = AIProviderProfile.appleDefault
        XCTAssertTrue(AIFallbackPolicy.shouldFallback(failureKind: .unavailable, profile: profile, hasFallback: true))
        XCTAssertTrue(AIFallbackPolicy.shouldFallback(failureKind: .rateLimited, profile: profile, hasFallback: true))
        XCTAssertFalse(AIFallbackPolicy.shouldFallback(failureKind: .configuration, profile: profile, hasFallback: true))
        XCTAssertFalse(AIFallbackPolicy.shouldFallback(failureKind: .unavailable, profile: profile, hasFallback: false))
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
        _ = decoder.decode(line: #"data: {"type":"response.output_item.added","item":{"type":"function_call","name":"system_context"}}"#)
        _ = decoder.decode(line: #"data: {"type":"response.function_call_arguments.done","arguments":"{}"}"#)
        let frame = decoder.decode(line: #"data: {"type":"response.completed"}"#)
        XCTAssertEqual(frame?.toolCall, AgentToolCall(name: "system_context", arguments: [:]))
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
            .camera,
            .translator,
            .developerTools,
            .settings
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

}
