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

    func testOpenSettingsEntersSettingsModeAndShowsPanelWhenClosed() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-settings-\(UUID().uuidString).json"))
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState(registry: registry, actionRunner: ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        var opened = 0
        state.onOpenSettings = { opened += 1 }

        state.openSettings()

        XCTAssertEqual(opened, 1)
        XCTAssert(state.mode == .settings)
        state.shutdown()
    }

    func testOpenSettingsInsideOpenPanelJustSwitchesMode() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-settings-\(UUID().uuidString).json"))
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState(registry: registry, actionRunner: ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        var opened = 0
        state.onOpenSettings = { opened += 1 }
        state.resetForOpen()

        state.openSettings()

        XCTAssertEqual(opened, 0)
        XCTAssert(state.mode == .settings)
        state.shutdown()
    }
}
