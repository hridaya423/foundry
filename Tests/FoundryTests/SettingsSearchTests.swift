import XCTest
import FoundryServices
@testable import Foundry

@MainActor
final class SettingsSearchTests: XCTestCase {
    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(SettingsSearch.matches("").isEmpty)
        XCTAssertTrue(SettingsSearch.matches("   ").isEmpty)
    }

    func testKeywordsAndTitlesRouteToTheRightPaneAndAnchor() {
        XCTAssertEqual(SettingsSearch.matches("hotkey").first?.anchorID, "general.hotkey")
        XCTAssertEqual(SettingsSearch.matches("Launch at LOGIN").map(\.anchorID), ["general.system"])
        XCTAssertTrue(SettingsSearch.matches("clip").allSatisfy { $0.pane == .clipboard })
        XCTAssertFalse(SettingsSearch.matches("clip").isEmpty)
        XCTAssertEqual(SettingsSearch.matches("ollama").first?.pane, .ai)
        XCTAssertEqual(SettingsSearch.matches("compact").first?.anchorID, "general.compact")
        XCTAssertTrue(SettingsSearch.matches("zzzz-no-such-setting").isEmpty)
        XCTAssertEqual(SettingsSearch.matches("export").first?.anchorID, "advanced.backup")
    }

    func testEveryPaneIsReachableFromSearch() {
        let panes = Set(SettingsSearch.items.map(\.pane))
        XCTAssertEqual(panes, Set(SettingsCategory.allCases))
    }

    /// Settings moved to a dedicated window (5.4) — opening it always
    /// goes through the shell, whether or not the panel is up.
    func testOpenSettingsOpensTheDedicatedWindowWhenClosed() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-settings-\(UUID().uuidString).json"))
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        var opened = 0
        let shell = RecordingShellPort()
        shell.onOpenSettings = { opened += 1 }
        state.shell = shell

        state.router.openSettings()

        XCTAssertEqual(opened, 1)
        state.shutdown()
    }

    func testOpenSettingsOpensTheDedicatedWindowWhilePanelIsOpen() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-settings-\(UUID().uuidString).json"))
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        var opened = 0
        let shell = RecordingShellPort()
        shell.onOpenSettings = { opened += 1 }
        state.shell = shell
        state.resetForOpen()

        state.router.openSettings()

        XCTAssertEqual(opened, 1)
        state.shutdown()
    }

    /// 5.4 acceptance: resetting applies live — the mirrored store values
    /// snap back to defaults without terminating the app.
    func testResetConfigurationAppliesLiveWithoutTerminating() throws {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-settings-\(UUID().uuidString).json"))
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        state.shell = RecordingShellPort()

        try config.updatePopToRootAfter(300)
        state.settings.apply(config: config.current)
        XCTAssertEqual(state.settings.popToRootAfterSeconds, 300)

        state.settings.resetConfiguration()

        XCTAssertEqual(state.settings.popToRootAfterSeconds, 90)
        XCTAssertEqual(config.current.popToRootAfterSeconds, 90)
        XCTAssertNil(state.settings.settingsPersistenceError)
        state.shutdown()
    }
}
