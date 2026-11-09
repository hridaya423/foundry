import XCTest
@testable import Foundry
import FoundryDomain
import FoundryServices

@MainActor
final class PanelSessionTests: XCTestCase {
    private func makeSession() -> PanelSession {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(
            diagnostics: diagnostics,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-session-\(UUID().uuidString).json"),
            legacyDefaults: nil
        )
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics),
            diagnostics: diagnostics, configService: config)
        return PanelSession(registry: registry, searchCoordinator: CommandSearchCoordinator(registry: registry, diagnostics: diagnostics),
            configService: config, diagnostics: diagnostics)
    }

    private func result(_ id: String, payload: ResultPayload = .command) -> CommandResult {
        CommandResult(id: id, title: id, subtitle: nil, icon: CommandIcon(fallback: "T"), payload: payload,
            primaryAction: CommandAction(id: id + ".primary", title: "Open", behavior: OpenHomeAction()), secondaryActions: [])
    }

    func testCalculatorFallbackRowsAreNavigableOnlyWhenTheyAreDrawn() {
        let session = makeSession()
        let calc = result("calculator.expr", payload: .calculation(expression: "6*7", value: "42"))
        session.query = "6*7"
        session.results = [calc, result("test.command")]
        session.selectedResultID = calc.id
        XCTAssertEqual(session.navigableResults.map(\.id), ["test.command"])

        session.results = [calc]
        XCTAssertEqual(session.navigableResults.map(\.id), PanelSession.calculatorFallbackResults.map(\.id))
    }
}
