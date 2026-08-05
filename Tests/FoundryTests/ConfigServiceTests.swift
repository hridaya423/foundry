import Foundation
import XCTest
@testable import Foundry
import FoundryDomain
import FoundryServices

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
        try service.updateSearchSensitivity(.high)

        let loaded = ConfigService(diagnostics: DiagnosticsService(), url: url)
        XCTAssertEqual(loaded.current.hotkey, hotkey)
        XCTAssertEqual(loaded.current.themeIntensity, 0.45)
        XCTAssertFalse(loaded.current.showAgentShelf)
        XCTAssertEqual(loaded.current.widgets, widgets)
        XCTAssertEqual(loaded.current.ai, ai)
        XCTAssertEqual(loaded.current.searchSensitivity, .high)
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

    func testFutureConfigVersionIsRejectedWithoutOverwritingTheFile() throws {
        let url = temporaryDirectory.appendingPathComponent("config.json")
        let data = Data(#"{"schemaVersion":999,"themeIntensity":0.11}"#.utf8)
        try data.write(to: url)

        XCTAssertThrowsError(try FoundryConfigMigration.migrate(data)) { error in
            XCTAssertEqual(error as? FoundryConfigMigrationError, .unsupportedVersion(999))
        }

        let service = ConfigService(diagnostics: DiagnosticsService(), url: url)
        XCTAssertEqual(service.current.themeIntensity, 0.72)
        XCTAssertNotNil(service.loadErrorMessage)

        XCTAssertThrowsError(try service.updateThemeIntensity(0.31)) { error in
            guard case .readOnly = error as? ConfigServiceError else {
                return XCTFail("Expected the config service to remain read-only")
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), data)

        try service.resetToDefaults()
        XCTAssertNil(service.loadErrorMessage)
        XCTAssertEqual(service.current.themeIntensity, 0.72)
        XCTAssertEqual(try JSONDecoder().decode(FoundryConfig.self, from: Data(contentsOf: url)), service.current)
    }

    func testConfigSnapshotsRemainConsistentDuringConcurrentWrites() async throws {
        let url = temporaryDirectory.appendingPathComponent("config.json")
        let service = ConfigService(diagnostics: DiagnosticsService(), url: url)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    try? service.updateThemeIntensity(Double(index) / 20)
                    _ = service.current
                }
            }
        }

        let saved = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(FoundryConfig.self, from: saved)
        XCTAssertEqual(decoded, service.current)
        XCTAssertGreaterThanOrEqual(decoded.themeIntensity, 0)
        XCTAssertLessThan(decoded.themeIntensity, 1)
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

    func testLegacyAIConfigMigratesOllamaFieldsIntoAProfile() throws {
        let data = Data(#"{"ai":{"isOllamaEnabled":true,"ollamaHost":"http://192.168.1.20:11434","ollamaModel":"qwen2.5"}}"#.utf8)
        let config = try JSONDecoder().decode(FoundryConfig.self, from: data)
        let ollama = try XCTUnwrap(config.ai.profiles.first(where: { $0.kind == .ollama }))

        XCTAssertTrue(ollama.enabled)
        XCTAssertEqual(ollama.endpoint, "http://192.168.1.20:11434")
        XCTAssertEqual(ollama.model, "qwen2.5")
        XCTAssertTrue(config.ai.fallbackProfileIDs.isEmpty)
    }

    func testPersistedOllamaFallbackIsRemovedFromDefaults() throws {
        var ai = AIConfig()
        ai.fallbackProfileIDs = [AIProviderProfile.ollamaID]
        let data = try JSONEncoder().encode(FoundryConfig(ai: ai))
        let config = try JSONDecoder().decode(FoundryConfig.self, from: data)

        XCTAssertTrue(config.ai.fallbackProfileIDs.isEmpty)
    }

    func testUnsupportedChatGPTModelMigratesToCurrentDefault() throws {
        let profile = AIProviderProfile(
            name: "ChatGPT subscription",
            kind: .openAISubscription,
            authentication: .oauth,
            model: "codex"
        )
        var ai = AIConfig()
        ai.profiles = [AIProviderProfile.appleDefault, profile]
        let data = try JSONEncoder().encode(FoundryConfig(ai: ai))
        let config = try JSONDecoder().decode(FoundryConfig.self, from: data)

        XCTAssertEqual(config.ai.profiles.first(where: { $0.kind == .openAISubscription })?.model, CodexModelPolicy.defaultModel)
        XCTAssertEqual(config.ai.profiles.first(where: { $0.kind == .openAISubscription })?.requestOptions.reasoningEffort, "low")
    }

    func testAIProfileCanBeAddedSelectedAndRemovedWithoutLeavingFallbackIDs() throws {
        let url = temporaryDirectory.appendingPathComponent("config.json")
        let service = ConfigService(diagnostics: DiagnosticsService(), url: url)
        let profile = try XCTUnwrap(AIProviderPreset.find("openrouter")?.makeProfile())

        try service.updateAIProfile(profile)
        try service.setDefaultAIProfile(id: profile.id)
        try service.setAIFallbackProfiles([profile.id])
        try service.removeAIProfile(id: profile.id)

        XCTAssertFalse(service.current.ai.profiles.contains { $0.id == profile.id })
        XCTAssertFalse(service.current.ai.fallbackProfileIDs.contains(profile.id))
        XCTAssertNotEqual(service.current.ai.defaultProfileID, profile.id)
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
        XCTAssertEqual(AISettingsState.validatedOllamaHost(" https://localhost:11434 "), "https://localhost:11434")
        XCTAssertEqual(AISettingsState.validatedOllamaHost("http://127.0.0.1:11434"), "http://127.0.0.1:11434")
        XCTAssertNil(AISettingsState.validatedOllamaHost("localhost:11434"))
        XCTAssertNil(AISettingsState.validatedOllamaHost("file:///tmp/ollama"))
        XCTAssertNil(AISettingsState.validatedOllamaHost("http:///missing-host"))
    }

    @MainActor
    func testAISettingsStateInitializesFromConfigSelection() {
        let service = ConfigService(diagnostics: DiagnosticsService(), url: temporaryDirectory.appendingPathComponent("config.json"))
        let state = AISettingsState(config: service, diagnostics: DiagnosticsService())

        XCTAssertEqual(state.aiProfiles, service.current.ai.profiles)
        XCTAssertEqual(state.defaultAIProfileID, service.current.ai.defaultProfileID)
        XCTAssertEqual(state.selectedAIProfileID, service.current.ai.defaultProfileID ?? service.current.ai.profiles.first?.id)
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
