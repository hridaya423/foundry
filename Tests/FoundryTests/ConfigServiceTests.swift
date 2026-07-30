import Foundation
import XCTest
@testable import Foundry

final class ConfigServiceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoundryConfigTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testConfigRoundTripsAllSettings() throws {
        let url = temporaryDirectory.appendingPathComponent("config.json")
        let service = ConfigService(diagnostics: DiagnosticsService(), url: url)
        var ai = AIConfig()
        ai.isOllamaEnabled = true
        ai.ollamaHost = "http://localhost:11434"
        ai.ollamaModel = "qwen2.5"
        let widgets = WidgetBoardConfig(enabled: [.clock, .weather], weatherCity: "Paris", stockSymbol: "AAPL")
        let hotkey = FoundryHotkey(keyCode: 0, modifiers: 256, displayName: "⌘A")

        try service.updateHotkey(hotkey)
        try service.updateThemeIntensity(0.45)
        try service.updateAgentShelfVisibility(false)
        try service.updateWidgets(widgets)
        try service.updateAIConfig(ai)

        let loaded = ConfigService(diagnostics: DiagnosticsService(), url: url)
        XCTAssertEqual(loaded.current.hotkey, hotkey)
        XCTAssertEqual(loaded.current.themeIntensity, 0.45)
        XCTAssertFalse(loaded.current.showAgentShelf)
        XCTAssertEqual(loaded.current.widgets, widgets)
        XCTAssertEqual(loaded.current.ai, ai)
        XCTAssertEqual(loaded.current.schemaVersion, FoundryConfig.currentSchemaVersion)
    }

    func testLegacyConfigMigratesToCurrentSchemaWithoutDroppingExistingFields() throws {
        let data = Data(#"{"hotkey":{"keyCode":0,"modifiers":256,"displayName":"⌘A"},"themeIntensity":0.4,"showAgentShelf":false}"#.utf8)

        let config = try FoundryConfigMigration.migrate(data)

        XCTAssertEqual(FoundryConfigMigration.sourceVersion(in: data), 1)
        XCTAssertEqual(config.schemaVersion, FoundryConfig.currentSchemaVersion)
        XCTAssertEqual(config.themeIntensity, 0.4)
        XCTAssertFalse(config.showAgentShelf)
        XCTAssertTrue(config.commandPreferences.isEmpty)
        XCTAssertTrue(config.providerEnabled.isEmpty)
    }

    func testCommandPreferencesRoundTripAndRejectBlankIDs() throws {
        let url = temporaryDirectory.appendingPathComponent("config.json")
        let service = ConfigService(diagnostics: DiagnosticsService(), url: url)
        var preference = CommandPreference()
        preference.isEnabled = false
        preference.favoriteRank = 2
        preference.aliases = ["browser"]

        try service.updateCommandPreference(preference, for: " foundry.dashboard ")
        try service.updateProviderEnabled(false, for: "foundry.builtin")
        try service.updateCommandPreference(preference, for: "   ")

        let loaded = ConfigService(diagnostics: DiagnosticsService(), url: url)
        XCTAssertEqual(loaded.current.commandPreferences["foundry.dashboard"], preference)
        XCTAssertEqual(loaded.current.providerEnabled["foundry.builtin"], false)
        XCTAssertEqual(loaded.current.commandPreferences.count, 1)
    }

    func testPartialAIConfigUsesDefaults() throws {
        let data = Data(#"{"ai":{"isOllamaEnabled":true,"ollamaModel":"phi4"}}"#.utf8)
        let config = try JSONDecoder().decode(FoundryConfig.self, from: data)

        XCTAssertTrue(config.ai.isOllamaEnabled)
        XCTAssertEqual(config.ai.ollamaHost, "http://127.0.0.1:11434")
        XCTAssertEqual(config.ai.ollamaModel, "phi4")
        XCTAssertEqual(config.ai.openAIModel, "gpt-4.1-mini")
    }

    func testFailedWriteLeavesCurrentConfigUnchanged() throws {
        let url = temporaryDirectory.appendingPathComponent("blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let service = ConfigService(diagnostics: DiagnosticsService(), url: url)
        let previous = service.current

        XCTAssertThrowsError(try service.updateThemeIntensity(0.31))
        XCTAssertEqual(service.current, previous)
    }

    @MainActor
    func testOllamaHostValidationAcceptsOnlyAbsoluteHTTPURLs() {
        XCTAssertEqual(CommandPanelState.validatedOllamaHost(" https://localhost:11434 "), "https://localhost:11434")
        XCTAssertEqual(CommandPanelState.validatedOllamaHost("http://127.0.0.1:11434"), "http://127.0.0.1:11434")
        XCTAssertNil(CommandPanelState.validatedOllamaHost("localhost:11434"))
        XCTAssertNil(CommandPanelState.validatedOllamaHost("file:///tmp/ollama"))
        XCTAssertNil(CommandPanelState.validatedOllamaHost("http:///missing-host"))
    }

    @MainActor
    func testCommandAliasesNormalizeWhitespaceDuplicatesAndCount() {
        XCTAssertEqual(
            CommandPanelState.normalizedCommandAliases(" browser, Browser, tabs , , history "),
            ["browser", "tabs", "history"]
        )
    }

    func testBuiltInProviderExposesDashboardCommand() async {
        let provider = BuiltInCommandProvider(
            config: ConfigService(diagnostics: DiagnosticsService(), url: temporaryDirectory.appendingPathComponent("config.json")),
            diagnostics: DiagnosticsService()
        )
        let results = await provider.results(matching: "dashboard")

        XCTAssertTrue(results.contains { result in
            result.id == "foundry.dashboard" && result.primaryAction.kind == .openDashboard
        })
    }

    @MainActor
    func testWidgetBoardTreatsAgentsAsAConfigurableWidget() {
        let service = ConfigService(
            diagnostics: DiagnosticsService(),
            url: temporaryDirectory.appendingPathComponent("config.json")
        )
        let board = WidgetBoardState(configService: service)

        XCTAssertTrue(board.config.enabled.contains(.agents))
        XCTAssertEqual(board.config.enabled.count, WidgetBoardConfig.maxEnabled)
        XCTAssertTrue(board.config.available.isEmpty)
    }

    @MainActor
    func testWidgetBoardDoesNotBackfillRemovedWidgetsAfterRebuild() {
        let service = ConfigService(
            diagnostics: DiagnosticsService(),
            url: temporaryDirectory.appendingPathComponent("config.json")
        )
        let board = WidgetBoardState(configService: service)
        board.remove(.calendar)

        let rebuilt = WidgetBoardState(configService: service)

        XCTAssertEqual(rebuilt.config.enabled, [.agents, .system, .battery])
        XCTAssertTrue(rebuilt.config.available.contains(.calendar))
    }

    @MainActor
    func testWidgetBoardMigratesExpandedDefaultToFourWidgets() throws {
        let url = temporaryDirectory.appendingPathComponent("config.json")
        let service = ConfigService(diagnostics: DiagnosticsService(), url: url)
        try service.updateWidgets(.legacyExpandedDefault)

        let board = WidgetBoardState(configService: service)

        XCTAssertEqual(board.config.enabled, WidgetBoardConfig.default.enabled)
        XCTAssertEqual(board.config.enabled.count, 4)
    }

    @MainActor
    func testWidgetBoardRejectsASecondAddAtTheFourWidgetLimit() {
        let service = ConfigService(
            diagnostics: DiagnosticsService(),
            url: temporaryDirectory.appendingPathComponent("config.json")
        )
        let board = WidgetBoardState(configService: service)

        board.add(.weather)

        XCTAssertEqual(board.config.enabled, WidgetBoardConfig.default.enabled)
    }
}
