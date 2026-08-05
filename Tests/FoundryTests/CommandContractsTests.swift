import XCTest
@testable import Foundry
import FoundryDomain
import FoundryServices

final class CommandContractsTests: XCTestCase {
    func testCommandDescriptorRoundTripsStableIdentityAndCapabilities() throws {
        let result = CommandResult(
            id: "foundry.dashboard",
            title: "Dashboard",
            subtitle: "Open the Foundry dashboard",
            icon: CommandIcon(fallback: "DB", systemName: "rectangle.3.group"),
            primaryAction: CommandAction(id: "foundry.dashboard.open", title: "Open", kind: .openDashboard),
            secondaryActions: []
        )

        let descriptor = result.descriptor(providerID: "foundry.builtin")
        let data = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(CommandDescriptor.self, from: data)

        XCTAssertEqual(decoded, descriptor)
        XCTAssertEqual(decoded.id, "foundry.dashboard")
        XCTAssertEqual(decoded.sourceID, "foundry.builtin")
        XCTAssertTrue(decoded.capabilities.contains(.search))
        XCTAssertEqual(decoded.executionPolicy, .readOnly)
    }

    func testCommandOutcomeRoundTripsTypedResult() throws {
        let outcome = CommandOutcome.fileResults([URL(fileURLWithPath: "/tmp/example.txt")])

        let data = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(CommandOutcome.self, from: data)

        XCTAssertEqual(decoded, outcome)
    }

    func testRetryableFailureKeepsThePanelOpen() {
        XCTAssertFalse(CommandOutcome.failure(message: "Unavailable", retryable: true).shouldDismissPanel)
        XCTAssertTrue(CommandOutcome.failure(message: "Invalid input", retryable: false).shouldDismissPanel)
        XCTAssertFalse(CommandOutcome.followUp(actionIDs: ["next"]).shouldDismissPanel)
    }

    @MainActor
    func testPreferredPrimaryActionAndCommandHotkeyAreAppliedAtRuntime() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("foundry-preferred-action-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let config = ConfigService(diagnostics: DiagnosticsService(), url: url)
        var preference = CommandPreference()
        preference.preferredPrimaryActionID = "test.command.secondary"
        try config.updateCommandPreference(preference, for: "test.command")

        let result = CommandResult(
            id: "test.command",
            title: "Test Command",
            subtitle: nil,
            icon: CommandIcon(fallback: "T"),
            primaryAction: CommandAction(id: "test.command.primary", title: "Primary", kind: .log("primary")),
            secondaryActions: [CommandAction(id: "test.command.secondary", title: "Secondary", kind: .log("secondary"))]
        )
        let registry = CommandRegistry(
            providers: [],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService(),
            configService: config
        )
        let state = CommandPanelState(
            registry: registry,
            actionRunner: ActionRunner(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService(),
            config: config
        )
        state.results = [result]
        state.selectedResultID = result.id

        XCTAssertEqual(state.selectedActions.first?.id, "test.command.secondary")

        state.setCommandHotkey(
            FoundryHotkey(keyCode: 0, modifiers: 256, displayName: "⌘A"),
            for: result.id
        )
        XCTAssertEqual(config.current.commandPreferences[result.id]?.globalHotkey?.displayName, "⌘A")
        state.shutdown()
    }

    func testExecutionRequestPreservesInvocationContext() {
        let request = CommandExecutionRequest(
            commandID: "foundry.test",
            action: CommandAction(id: "foundry.test.open", title: "Open", kind: .openDashboard),
            source: .external,
            arguments: ["path": "/tmp/example"],
            context: ["frontmostApplication": "Terminal"]
        )

        XCTAssertEqual(request.invocation.source, .external)
        XCTAssertEqual(request.invocation.arguments["path"], "/tmp/example")
        XCTAssertEqual(request.invocation.context["frontmostApplication"], "Terminal")
    }

    func testLegacyCommandHotkeySurvivesConfigRoundTrip() throws {
        let data = Data(#"{"commandPreferences":{"foundry.test":{"isEnabled":true,"globalHotkey":{"keyCode":49,"modifiers":256,"displayName":"⌘Space"}}}}"#.utf8)

        let config = try JSONDecoder().decode(FoundryConfig.self, from: data)
        let preference = try XCTUnwrap(config.commandPreferences["foundry.test"])

        XCTAssertEqual(preference.globalHotkey, CommandHotkey(keyCode: 49, modifiers: 256, displayName: "⌘Space"))

        let roundTripped = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(FoundryConfig.self, from: roundTripped)
        XCTAssertEqual(decoded.commandPreferences["foundry.test"]?.globalHotkey, preference.globalHotkey)
    }

    func testActionDescriptorMarksDestructiveActions() {
        let action = CommandAction(id: "foundry.quit.perform", title: "Quit", kind: .quit)

        XCTAssertTrue(action.descriptor.isDestructive)
        XCTAssertEqual(action.descriptor.confirmation, .destructive)
        XCTAssertEqual(action.kind.executionPolicy, .destructive)
    }

    func testProviderHealthTracksLatencyPercentilesAndFailures() async {
        let store = ProviderHealthStore()

        await store.recordRequest(providerID: "test", elapsedMilliseconds: 10, resultCount: 1)
        await store.recordRequest(providerID: "test", elapsedMilliseconds: 30, resultCount: 0)
        await store.recordFailure(providerID: "test", message: "Unavailable")
        await store.setPermissionState(.granted, for: "test")

        let snapshot = await store.snapshot(for: "test")

        XCTAssertEqual(snapshot.requestCount, 3)
        XCTAssertEqual(snapshot.successCount, 2)
        XCTAssertEqual(snapshot.failureCount, 1)
        XCTAssertEqual(snapshot.emptyResponseCount, 1)
        XCTAssertEqual(snapshot.latencyP50Milliseconds, 20)
        XCTAssertEqual(snapshot.latencyP95Milliseconds, 29)
        XCTAssertEqual(snapshot.lastFailure, "Unavailable")
        XCTAssertEqual(snapshot.permissionState, .granted)
    }

    func testProviderDescriptorIncludesHealthSnapshot() async {
        let provider = TestCommandProvider()
        let health = ProviderHealthStore()
        let registry = CommandRegistry(
            providers: [provider],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService(),
            providerHealth: health
        )

        _ = await registry.results(matching: "test")
        let descriptor = await registry.providerDescriptors().first

        XCTAssertEqual(descriptor?.id, "test.provider")
        XCTAssertEqual(descriptor?.health?.requestCount, 1)
        XCTAssertEqual(descriptor?.health?.successCount, 1)
    }

    func testRegistryFiltersDisabledCommandPreferences() async throws {
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("foundry-command-preferences-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config = ConfigService(diagnostics: DiagnosticsService(), url: configURL)
        var preference = CommandPreference()
        preference.isEnabled = false
        try config.updateCommandPreference(preference, for: "test.command")

        let registry = CommandRegistry(
            providers: [TestCommandProvider()],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService(),
            configService: config
        )

        let results = await registry.results(matching: "")
        XCTAssertTrue(results.isEmpty)
    }

    func testProviderActivationPolicyPreventsInactiveProviderWork() async {
        let provider = ConditionalProvider()
        let registry = CommandRegistry(
            providers: [provider],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService()
        )

        let results = await registry.results(matching: "inactive")

        XCTAssertFalse(results.contains { $0.id == "conditional.command" })
        let callCount = await provider.counter.value
        XCTAssertEqual(callCount, 0)
    }

    func testDeferredProviderCanSupplyCheapSupplementalResultsWithoutActivation() async {
        let registry = CommandRegistry(
            providers: [SupplementalProvider()],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService()
        )

        let results = await registry.immediateResults(matching: "cached")

        XCTAssertEqual(results.map(\.id), ["supplemental.cached"])
    }

    func testProviderDescriptorCarriesSearchPolicy() async {
        let registry = CommandRegistry(
            providers: [DeferredProvider()],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService()
        )

        let descriptor = await registry.providerDescriptors().first

        XCTAssertEqual(descriptor?.searchPolicy.tier, .deferred)
    }

    func testCommandCatalogSurfacesProviderFailures() async {
        let registry = CommandRegistry(
            providers: [CatalogFailingProvider()],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService()
        )

        let catalog = await registry.commandCatalog()

        XCTAssertEqual(catalog.providerFailures, ["catalog.failing: Unavailable"])
    }

    func testCommandCatalogCachesAndForceRefreshes() async {
        let provider = CountingCommandProvider()
        let registry = CommandRegistry(
            providers: [provider],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService()
        )

        let first = await registry.commandCatalog()
        let second = await registry.commandCatalog()
        let refreshed = await registry.commandCatalog(forceRefresh: true)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.generation, 1)
        XCTAssertEqual(refreshed.generation, 2)
        let callCount = await provider.counter.value
        XCTAssertEqual(callCount, 2)
    }

    func testCommandSettingsCatalogSortsFavoritesAndFiltersBySearchText() {
        let favorite = CommandResult(
            id: "foundry.favorite",
            title: "Favorite Command",
            subtitle: "Open the favorite",
            icon: CommandIcon(fallback: "F"),
            primaryAction: CommandAction(id: "favorite.open", title: "Open", kind: .openDashboard),
            secondaryActions: []
        ).descriptor(providerID: "foundry.builtin")
        let other = CommandResult(
            id: "foundry.other",
            title: "Other Command",
            subtitle: "Open another command",
            icon: CommandIcon(fallback: "O"),
            primaryAction: CommandAction(id: "other.open", title: "Open", kind: .openDashboard),
            secondaryActions: []
        ).descriptor(providerID: "foundry.system")
        var preference = CommandPreference()
        preference.favoriteRank = 0

        let catalog = CommandSettingsCatalog.build(
            descriptors: [other, favorite],
            preferences: [favorite.id: preference],
            query: "favorite"
        )

        XCTAssertEqual(catalog.rows.map(\.id), [other.id, favorite.id])
        XCTAssertEqual(catalog.visibleRows.map(\.id), [favorite.id])
    }

    private struct TestCommandProvider: CommandProvider {
        let id = "test.provider"

        func search(_ request: CommandSearchRequest) async -> [CommandResult] {
            [CommandResult(
                id: "test.command",
                title: "Test Command",
                subtitle: nil,
                icon: CommandIcon(fallback: "T"),
                    primaryAction: CommandAction(id: "test.command.open", title: "Open", kind: .openDashboard),
                secondaryActions: []
            )]
        }
    }

    private struct ConditionalProvider: CommandProvider {
        let id = "conditional.provider"
        let counter = CallCounter()

        func isActive(for query: String) -> Bool {
            query == "active"
        }

        func search(_ request: CommandSearchRequest) async -> [CommandResult] {
            await counter.increment()
            return [CommandResult(
                id: "conditional.command",
                title: "Conditional Command",
                subtitle: nil,
                icon: CommandIcon(fallback: "C"),
                primaryAction: CommandAction(id: "conditional.command.open", title: "Open", kind: .openDashboard),
                secondaryActions: []
            )]
        }
    }

    private struct DeferredProvider: CommandProvider {
        let id = "deferred.provider"
        var searchPolicy: CommandProviderSearchPolicy { CommandProviderSearchPolicy(tier: .deferred) }

        func search(_ request: CommandSearchRequest) async -> [CommandResult] { [] }
    }

    private struct SupplementalProvider: CommandProvider {
        let id = "supplemental.provider"
        var searchPolicy: CommandProviderSearchPolicy {
            CommandProviderSearchPolicy(tier: .deferred, includesSupplementalResults: true)
        }

        func isActive(for _: String) -> Bool { false }

        func search(_ request: CommandSearchRequest) async -> [CommandResult] { [] }

        func supplementalResults(matching _: String, sensitivity _: SearchSensitivity) -> [CommandResult] {
            [CommandResult(
                id: "supplemental.cached",
                title: "Cached Result",
                subtitle: nil,
                icon: CommandIcon(fallback: "C"),
                primaryAction: CommandAction(id: "supplemental.cached.open", title: "Open", kind: .openDashboard),
                secondaryActions: []
            )]
        }
    }

    private struct CatalogFailingProvider: CommandProvider {
        let id = "catalog.failing"

        func search(_ request: CommandSearchRequest) async -> [CommandResult] { [] }

        func defaultResults() async throws -> [CommandResult] {
            throw Failure.unavailable
        }

        private enum Failure: LocalizedError {
            case unavailable

            var errorDescription: String? { "Unavailable" }
        }
    }

    private final class CountingCommandProvider: CommandProvider, @unchecked Sendable {
        let id = "counting.provider"
        let counter = CallCounter()

        func search(_ request: CommandSearchRequest) async -> [CommandResult] { [] }

        func defaultResults() async -> [CommandResult] {
            await counter.increment()
            return [CommandResult(
                id: "counting.command",
                title: "Counting Command",
                subtitle: "Test",
                icon: CommandIcon(fallback: "C"),
                    primaryAction: CommandAction(id: "counting.command.open", title: "Open", kind: .openDashboard),
                secondaryActions: []
            )]
        }
    }

    private actor CallCounter {
        private(set) var value = 0

        func increment() {
            value += 1
        }
    }
}
