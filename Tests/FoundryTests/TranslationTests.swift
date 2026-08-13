import XCTest
import FoundryDomain
@testable import Foundry

final class TranslationTests: XCTestCase {
    @MainActor
    func testEmptyInputCancelsRequestAndNeverSpins() async throws {
        let state = TranslatorState(availability: .translationFramework, translator: { _ in
            XCTFail("empty input must not invoke a translator")
            return .failure(.cancelled)
        })

        state.sourceText = "hello"
        state.sourceText = "   "
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertFalse(state.isTranslating)
        XCTAssertEqual(state.translationError, nil)
        XCTAssertNil(state.activeRequest)
    }

    @MainActor
    func testSameLanguageCompletesWithoutCallingBackend() async throws {
        let state = TranslatorState(availability: .translationFramework, translator: { _ in
            XCTFail("same-language translation must be resolved locally")
            return .failure(.cancelled)
        })

        state.sourceLanguage = "English"
        state.targetLanguage = "English"
        state.sourceText = "hello"
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(state.result, "hello")
        XCTAssertFalse(state.isTranslating)
    }

    @MainActor
    func testStaleResponseCannotReplaceNewerRequest() async throws {
        let first = XCTestExpectation(description: "first request")
        let state = TranslatorState(availability: .translationFramework, debounce: .zero, translator: { request in
            if request.text == "first" {
                first.fulfill()
                try? await Task.sleep(for: .milliseconds(100))
                return .success("old")
            }
            return .success("new")
        })

        state.sourceText = "first"
        await fulfillment(of: [first], timeout: 1)
        state.sourceText = "second"
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(state.result, "new")
    }

    @MainActor
    func testMacOS14ReportsTypedUnavailableImmediately() {
        let state = TranslatorState(availability: .unavailable)
        state.sourceText = "hello"

        XCTAssertFalse(state.isTranslating)
        XCTAssertEqual(state.translationError, TranslationFailure.unavailable.message)
    }

    func testProviderReturnsOpenTranslatorActionWhenNoExecutableBackendExists() async throws {
        let provider = TranslationProvider()
        let results = await provider.search(CommandSearchRequest(query: "translate hello to es"))
        let result = try XCTUnwrap(results.first)

        XCTAssertEqual(result.primaryAction.kind, .openTranslator(text: "hello", language: "es"))
        XCTAssertFalse(result.title.contains("failed"))
        XCTAssertFalse(result.title.contains("unavailable"))
    }

    func testProviderLabelsAppleTranslationSeparatelyFromAppleIntelligence() async {
        let provider = TranslationProvider(translator: { _ in .success("hola") })
        let result = await provider.search(CommandSearchRequest(query: "translate hello to es"))[0]

        XCTAssertEqual(result.subtitle, "Apple Translation • Translate to Spanish")
        XCTAssertTrue(result.secondaryActions.contains { $0.title == "Try Apple Intelligence" })
    }

    func testLanguageCatalogParsesNamesCodesCaseAndWhitespace() throws {
        XCTAssertEqual(TranslationLanguage.parse("  ES ")?.identifier, "es")
        XCTAssertEqual(TranslationLanguage.parse("FRENCH")?.identifier, "fr")
        XCTAssertEqual(TranslationLanguage.parse("zh-Hans")?.identifier, "zh-Hans")
        XCTAssertEqual(TranslationLanguage.parse("Spanish")?.displayName, "Spanish")
        XCTAssertNil(TranslationLanguage.parse("not-a-language"))
    }

    func testRequestIsImmutableAndContainsStableLanguageValues() throws {
        let request = try XCTUnwrap(TranslationRequest(text: " Hola ", source: " en ", target: " ES "))
        XCTAssertEqual(request.text, "Hola")
        XCTAssertEqual(request.source.identifier, "en")
        XCTAssertEqual(request.target.identifier, "es")
        XCTAssertFalse(request.id.uuidString.isEmpty)
    }

    func testRequestParserUsesTheLastToSeparatorAndRejectsUnknownTargets() throws {
        let request = try XCTUnwrap(TranslationProvider.request(from: "translate hello to the world to es"))
        XCTAssertEqual(request.text, "hello to the world")
        XCTAssertEqual(request.target.identifier, "es")
        XCTAssertNil(TranslationProvider.request(from: "translate hello to klingon"))
    }

    func testTypedFailuresHaveDistinctCases() {
        let failures: [TranslationFailure] = [.unavailable, .unsupportedPair(source: "en", target: "xx"), .asset, .offline, .cancelled, .backend("boom")]
        XCTAssertEqual(Set(failures), Set(failures))
    }

    func testProviderFailureDoesNotBecomeCopyableTranslationText() async {
        let provider = TranslationProvider(translator: { _ in .failure(.offline) })
        let results = await provider.search(CommandSearchRequest(query: "translate hello to es"))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].primaryAction.kind, CommandActionKind.openTranslator(text: "hello", language: "es"))
        XCTAssertFalse(results[0].secondaryActions.contains { $0.kind == CommandActionKind.copyToClipboard("Translation failed") })
    }

    @MainActor
    func testFrameworkSessionHandoffKeepsRequestPendingForSwiftUIAdapter() throws {
        let state = TranslatorState(availability: .translationFramework, translator: { _ in .sessionRequired })
        state.sourceText = "hello"

        let request = try XCTUnwrap(state.activeRequest)
        state.finish(.sessionRequired, for: request)

        XCTAssertEqual(state.result, "")
        XCTAssertNil(state.translationError)
        XCTAssertTrue(state.isTranslating)
        XCTAssertFalse(state.needsAppleTranslationFallback)
    }
}
