import XCTest
@testable import Foundry
import FoundryDomain
import FoundryServices

@MainActor
final class CommandSearchCoordinatorTests: XCTestCase {
    func testAStaleSearchCannotPublishAfterANewerQueryStarts() async throws {
        let registry = CommandRegistry(
            providers: [QueryProvider()],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService()
        )
        let coordinator = CommandSearchCoordinator(registry: registry, diagnostics: DiagnosticsService())
        var immediateQueries: [String] = []
        var completedQueries: [String] = []

        coordinator.search(
            query: "first",
            onImmediate: { results in immediateQueries.append(contentsOf: results.map(\.title)) },
            onComplete: { results in completedQueries.append(contentsOf: results.map(\.title)) }
        )
        coordinator.search(
            query: "second",
            onImmediate: { results in immediateQueries.append(contentsOf: results.map(\.title)) },
            onComplete: { results in completedQueries.append(contentsOf: results.map(\.title)) }
        )

        try await Task.sleep(for: .milliseconds(150))
        coordinator.cancel()

        XCTAssertEqual(immediateQueries, ["second"])
        XCTAssertEqual(completedQueries, ["second"])
    }

    func testProviderThatMissesTheImmediateWindowCanPublishDuringCompletion() async throws {
        let registry = CommandRegistry(
            providers: [SlowResultProvider()],
            usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService()
        )
        let coordinator = CommandSearchCoordinator(registry: registry, diagnostics: DiagnosticsService())
        var immediateResults: [String] = []
        var completedResults: [String] = []

        coordinator.search(
            query: "slow",
            onImmediate: { results in immediateResults.append(contentsOf: results.map(\.title)) },
            onComplete: { results in completedResults.append(contentsOf: results.map(\.title)) }
        )

        try await Task.sleep(for: .milliseconds(260))
        coordinator.cancel()

        XCTAssertTrue(immediateResults.isEmpty)
        XCTAssertEqual(completedResults, ["Slow result"])
    }

    private struct QueryProvider: CommandProvider {
        let id = "test.query-provider"

        func search(_ request: CommandSearchRequest) async -> [CommandResult] {
            [CommandResult(
                id: "result.\(request.query)",
                title: request.query,
                subtitle: nil,
                icon: CommandIcon(fallback: "Q"),
                primaryAction: CommandAction(id: "open.\(request.query)", title: "Open", kind: .openHome),
                secondaryActions: []
            )]
        }
    }

    private struct SlowResultProvider: CommandProvider {
        let id = "test.slow-result"

        func search(_ request: CommandSearchRequest) async -> [CommandResult] {
            try? await Task.sleep(for: .milliseconds(130))
            return [CommandResult(
                id: "slow.result",
                title: "Slow result",
                subtitle: nil,
                icon: CommandIcon(fallback: "S"),
                primaryAction: CommandAction(id: "slow.result.open", title: "Open", kind: .openHome),
                secondaryActions: []
            )]
        }
    }
}
