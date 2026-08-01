import XCTest
@testable import Foundry

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

    func testActionDescriptorMarksDestructiveActions() {
        let action = CommandAction(id: "foundry.quit.perform", title: "Quit", kind: .quit)

        XCTAssertTrue(action.descriptor.isDestructive)
        XCTAssertEqual(action.descriptor.confirmation, .destructive)
        XCTAssertEqual(action.kind.executionPolicy, .systemMutation)
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

    private struct TestCommandProvider: CommandProvider {
        let id = "test.provider"

        func results(matching query: String) async -> [CommandResult] {
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

    private final class CountingCommandProvider: CommandProvider, @unchecked Sendable {
        let id = "counting.provider"
        let counter = CallCounter()

        func results(matching query: String) async -> [CommandResult] { [] }

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
