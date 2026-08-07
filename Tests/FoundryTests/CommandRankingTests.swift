import XCTest
@testable import Foundry
import FoundryDomain
import FoundryServices

final class CommandRankingTests: XCTestCase {
    func testSlowProviderDoesNotBlockFastProvider() async {
        let registry = CommandRegistry(
            providers: [
                SlowProvider(),
                TestProvider(results: [command(id: "test.fast", title: "Fast Result")])
            ],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService()
        )
        let startedAt = Date()

        let results = await registry.results(matching: "result")

        XCTAssertEqual(results.first?.id, "test.fast")
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5)
    }

    func testProviderTimeoutIsRecordedAsAProviderFailure() async {
        let health = ProviderHealthStore()
        let registry = CommandRegistry(
            providers: [SlowProvider()],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService(),
            providerHealth: health
        )

        _ = await registry.results(matching: "result")
        let snapshot = await health.snapshot(for: "test.slow")

        XCTAssertEqual(snapshot.timeoutCount, 1)
        XCTAssertEqual(snapshot.failureCount, 1)
        XCTAssertEqual(snapshot.successCount, 0)
    }

    func testProviderErrorIsRecordedWithoutPoisoningOtherResults() async {
        let health = ProviderHealthStore()
        let registry = CommandRegistry(
            providers: [
                FailingProvider(),
                TestProvider(results: [command(id: "test.healthy", title: "Healthy Result")])
            ],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService(),
            providerHealth: health
        )

        let results = await registry.results(matching: "result")
        let snapshot = await health.snapshot(for: "test.failing")

        XCTAssertTrue(results.contains { $0.id == "test.healthy" })
        XCTAssertEqual(snapshot.failureCount, 1)
        XCTAssertEqual(snapshot.successCount, 0)
        XCTAssertEqual(snapshot.lastFailure, "Unavailable")
    }

    func testCancellationInsensitiveProviderCannotRunOverlappingSearches() async throws {
        let probe = OverlapProbe()
        let registry = CommandRegistry(
            providers: [CancellationInsensitiveProvider(probe: probe)],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService()
        )

        _ = await registry.immediateResults(matching: "first")
        _ = await registry.immediateResults(matching: "second")
        try await Task.sleep(for: .milliseconds(180))
        let maximumConcurrent = await probe.maximumConcurrent()

        XCTAssertEqual(maximumConcurrent, 1)
    }

    func testFallbackEligibilityCanSuppressAProviderFallbackResult() async throws {
        let configURL = temporaryURL()
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config = ConfigService(diagnostics: DiagnosticsService(), url: configURL)
        var preference = CommandPreference()
        preference.fallbackEligible = false
        try config.updateCommandPreference(preference, for: "test.fallback")

        let registry = CommandRegistry(
            providers: [FallbackProvider()],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService(),
            configService: config
        )

        let results = await registry.results(matching: "fallback")

        XCTAssertFalse(results.contains { $0.id == "test.fallback" })
    }

    func testConfiguredAliasesParticipateInRuntimeRanking() async throws {
        let configURL = temporaryURL()
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config = ConfigService(diagnostics: DiagnosticsService(), url: configURL)
        var preference = CommandPreference()
        preference.aliases = ["ship"]
        try config.updateCommandPreference(preference, for: "foundry.settings")

        let registry = CommandRegistry(
            providers: [BuiltInCommandProvider(config: config, diagnostics: DiagnosticsService())],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService(),
            configService: config
        )

        let results = await registry.results(matching: "ship")
        XCTAssertEqual(results.first?.id, "foundry.settings")
    }

    func testRelevantLexicalMatchBeatsUnmatchedProviderResults() async {
        let registry = CommandRegistry(
            providers: [TestProvider(results: [
                command(id: "test.relevant", title: "Open Project"),
                command(id: "test.noisy", title: "Unrelated Result")
            ])],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService()
        )

        let results = await registry.results(matching: "project")
        XCTAssertEqual(results.first?.id, "test.relevant")
    }

    func testExplicitRouteBeatsLexicalCandidates() async {
        let registry = CommandRegistry(
            providers: [TestProvider(results: [
                command(id: "test.calculation", title: "4", route: .calculator),
                command(id: "test.static", title: "Calculator")
            ])],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService()
        )

        let results = await registry.results(matching: "2 + 2")
        XCTAssertEqual(results.first?.id, "test.calculation")
    }

    func testUnmatchedResultsUseStableLexicalOrdering() async {
        let registry = CommandRegistry(
            providers: [TestProvider(results: [
                command(id: "test.history", title: "History Result", route: .browserHistory),
                command(id: "test.tab", title: "Tab Result", route: .browserTab)
            ])],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService()
        )

        let results = await registry.results(matching: "unrelated")
        XCTAssertEqual(results.first?.id, "test.history")
    }

    func testExactAliasBeatsUnrelatedRoutedResults() async {
        let registry = CommandRegistry(
            providers: [TestProvider(results: [
                command(id: "test.download", title: "youtube.com video", route: .mediaDownload),
                command(id: "test.emoji", title: "Emoji & Symbols", aliases: ["characters"])
            ])],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService()
        )

        let results = await registry.results(matching: "characters")
        XCTAssertEqual(results.first?.id, "test.emoji")
    }

    func testExactTitleBeatsProviderKeyword() async {
        let registry = CommandRegistry(
            providers: [TestProvider(results: [
                command(id: "test.keyword", title: "Character Tools", searchKeywords: ["characters"]),
                command(id: "test.title", title: "Characters")
            ])],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService()
        )

        let results = await registry.results(matching: "characters")
        XCTAssertEqual(results.first?.id, "test.title")
    }

    func testUsageNeverPromotesWeakMatchesAboveStrongerLexicalTiers() async throws {
        let configURL = temporaryURL()
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config = ConfigService(diagnostics: DiagnosticsService(), url: configURL)
        try config.updateSearchSensitivity(.low)
        let usageURL = temporaryURL()
        defer { try? FileManager.default.removeItem(at: usageURL) }
        let usageRanking = UsageRankingStore(diagnostics: DiagnosticsService(), url: usageURL)

        let registry = CommandRegistry(
            providers: [TestProvider(results: [
                command(id: "test.prefix", title: "Wi-Fi Settings"),
                command(id: "test.fuzzy", title: "Wild Fire Selector")
            ])],
            usageRanking: usageRanking,
            diagnostics: DiagnosticsService(),
            configService: config
        )

        usageRanking.recordExecution(resultID: "test.fuzzy", query: "wifi")

        let results = await registry.results(matching: "wifi")
        XCTAssertEqual(results.first?.id, "test.prefix")
    }

    func testUsageCanReorderComparableTitleMatches() async {
        let usageURL = temporaryURL()
        defer { try? FileManager.default.removeItem(at: usageURL) }
        let usageRanking = UsageRankingStore(diagnostics: DiagnosticsService(), url: usageURL)
        let registry = CommandRegistry(
            providers: [TestProvider(results: [
                command(id: "test.calendar", title: "Calendar"),
                command(id: "test.calculator", title: "Calculator")
            ])],
            usageRanking: usageRanking,
            diagnostics: DiagnosticsService()
        )

        usageRanking.recordExecution(resultID: "test.calculator", query: "cal")
        let results = await registry.results(matching: "cal")
        XCTAssertEqual(results.first?.id, "test.calculator")
    }

    func testEquivalentResultsUseStableIDTieBreakers() async {
        let registry = CommandRegistry(
            providers: [TestProvider(results: [
                command(id: "test.z", title: "Thing"),
                command(id: "test.a", title: "Thing")
            ])],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService()
        )

        let results = await registry.results(matching: "thing")
        XCTAssertEqual(results.map(\.id), ["test.a", "test.z"])
    }

    func testUsageBoostFollowsTheQueryInsteadOfApplyingGlobally() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = UsageRankingStore(diagnostics: DiagnosticsService(), url: url)
        let result = command(id: "test.command", title: "Test Command")

        store.recordExecution(resultID: result.id, query: "alpha")

        let alphaBoost = store.usageBoost(for: result.id, query: "alpha")
        let betaBoost = store.usageBoost(for: result.id, query: "beta")
        XCTAssertGreaterThan(alphaBoost, betaBoost)
    }

    func testUsageLearnsFromLongerQueriesForShorterPrefixes() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = UsageRankingStore(diagnostics: DiagnosticsService(), url: url)
        let result = command(id: "test.calendar", title: "Calendar")

        store.recordExecution(resultID: result.id, query: "calendar")

        XCTAssertGreaterThan(
            store.usageBoost(for: result.id, query: "cal"),
            store.usageBoost(for: result.id, query: "other")
        )
    }

    func testResetRankingRemovesGlobalAndQueryHistory() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = UsageRankingStore(diagnostics: DiagnosticsService(), url: url)
        let result = command(id: "test.command", title: "Test Command")

        store.recordExecution(resultID: result.id, query: "alpha")
        store.resetRanking(for: result.id)

        XCTAssertEqual(store.usageBoost(for: result.id, query: "alpha"), 0)
    }

    private func command(id: String, title: String, aliases: [String] = [], searchKeywords: [String] = [], route: SearchRoute? = nil) -> CommandResult {
        CommandResult(
            id: id,
            title: title,
            subtitle: nil,
            icon: CommandIcon(fallback: "T"),
            searchAliases: aliases,
            searchKeywords: searchKeywords,
            route: route,
            primaryAction: CommandAction(id: id + ".open", title: "Open", kind: .openHome),
            secondaryActions: []
        )
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("foundry-ranking-\(UUID().uuidString).json")
    }

    private struct TestProvider: CommandProvider {
        let id = "test.provider"
        let resultsToReturn: [CommandResult]

        init(results: [CommandResult]) {
            resultsToReturn = results
        }

        func search(_ request: CommandSearchRequest) async -> [CommandResult] {
            resultsToReturn
        }
    }

    private struct SlowProvider: CommandProvider {
        let id = "test.slow"

        func search(_ request: CommandSearchRequest) async -> [CommandResult] {
            try? await Task.sleep(for: .seconds(5))
            return []
        }
    }

    private struct FailingProvider: CommandProvider {
        let id = "test.failing"

        func search(_ request: CommandSearchRequest) async throws -> [CommandResult] {
            throw Failure.unavailable
        }

        private enum Failure: LocalizedError {
            case unavailable

            var errorDescription: String? { "Unavailable" }
        }
    }

    private struct CancellationInsensitiveProvider: CommandProvider {
        let id = "test.cancellation-insensitive"
        let probe: OverlapProbe

        func search(_ request: CommandSearchRequest) async -> [CommandResult] {
            await probe.enter()
            try? await Task.sleep(for: .milliseconds(150))
            await probe.leave()
            return []
        }
    }

    private struct FallbackProvider: CommandProvider {
        let id = "test.fallback-provider"

        func search(_ request: CommandSearchRequest) async -> [CommandResult] { [] }

        func fallbackResults(matching query: String, sensitivity: SearchSensitivity) async throws -> [CommandResult] {
            [CommandResult(
                id: "test.fallback",
                title: "Fallback result",
                subtitle: nil,
                icon: CommandIcon(fallback: "F"),
                primaryAction: CommandAction(id: "test.fallback.open", title: "Open", kind: .openHome),
                secondaryActions: []
            )]
        }
    }

    private actor OverlapProbe {
        private var active = 0
        private var maximum = 0

        func enter() {
            active += 1
            maximum = max(maximum, active)
        }

        func leave() {
            active -= 1
        }

        func maximumConcurrent() -> Int {
            maximum
        }
    }
}
