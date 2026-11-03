import XCTest
import FoundryServices
@testable import Foundry

final class LocalStateStoreTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDown() {
        roots.forEach { try? FileManager.default.removeItem(at: $0) }
        super.tearDown()
    }

    private func configURL() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("localstate-\(UUID())")
        roots.append(root)
        return root.appendingPathComponent("config.json")
    }

    private func legacySuite() -> UserDefaults {
        let name = "foundry.legacy.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return defaults
    }

    func testMigrationImportsEveryLegacyKeyAndRemovesThem() {
        let defaults = legacySuite()
        defaults.set("firefox", forKey: "foundry.mainBrowser")
        defaults.set("JPY", forKey: "preferredCurrencyQuote")
        defaults.set(true, forKey: "foundry.launchAtLoginConsent")
        defaults.set(["#FF0000"], forKey: "colorPicker.recents")
        defaults.set("/tmp/dl", forKey: "mediaDownloadFolder")
        defaults.set("/tmp/snippets", forKey: "snippets.lastExportDirectory")
        defaults.set(true, forKey: "conversion.firstSuccessCelebrated")
        defaults.set(true, forKey: "foundry.firefox.connector.promptShown")
        defaults.set("1.2.0", forKey: OnboardingState.completedVersionKey)
        defaults.set(3, forKey: OnboardingState.stepKey)
        defaults.set(["👍"], forKey: "emoji.recents")
        defaults.set(14, forKey: "emoji.columns")
        defaults.set("🏽", forKey: "emoji.skinTone")
        defaults.set(["/tmp/scripts"], forKey: "foundry.scripts.directories")
        defaults.set(["/tmp/scripts"], forKey: "foundry.scripts.trusted")
        defaults.set([["1+1", "2"]], forKey: "foundry.calculator.history")

        var state = FoundryLocalState()
        XCTAssertTrue(UserDefaultsMigration.apply(to: &state, defaults: defaults))

        XCTAssertEqual(state.mainBrowser, "firefox")
        XCTAssertEqual(state.preferredCurrencyQuote, "JPY")
        XCTAssertTrue(state.launchAtLoginConsent)
        XCTAssertEqual(state.colorPickerRecents, ["#FF0000"])
        XCTAssertEqual(state.mediaDownloadFolder, "/tmp/dl")
        XCTAssertEqual(state.snippetsLastExportDirectory, "/tmp/snippets")
        XCTAssertTrue(state.conversionFirstSuccessCelebrated)
        XCTAssertTrue(state.firefoxConnectorPromptShown)
        XCTAssertEqual(state.onboardingCompletedVersion, "1.2.0")
        XCTAssertEqual(state.onboardingStep, 3)
        XCTAssertEqual(state.emojiRecents, ["👍"])
        XCTAssertEqual(state.emojiColumns, 14)
        XCTAssertEqual(state.emojiSkinTone, "🏽")
        XCTAssertEqual(state.scriptDirectories, ["/tmp/scripts"])
        XCTAssertEqual(state.trustedScriptDirectories, ["/tmp/scripts"])
        XCTAssertEqual(state.calculatorHistory, [["1+1", "2"]])

        XCTAssertNil(defaults.string(forKey: "foundry.mainBrowser"))
        XCTAssertNil(defaults.object(forKey: OnboardingState.stepKey))
        XCTAssertNil(defaults.stringArray(forKey: "foundry.scripts.directories"))
        // Keys already migrated don't re-run or clobber current values.
        XCTAssertFalse(UserDefaultsMigration.apply(to: &state, defaults: defaults))
    }

    func testConfigServiceImportsLegacyDefaultsAtInit() throws {
        let url = configURL()
        let defaults = legacySuite()
        defaults.set("arc", forKey: "foundry.mainBrowser")
        defaults.set("/tmp/dl", forKey: "mediaDownloadFolder")

        let service = ConfigService(diagnostics: DiagnosticsService(), url: url, persistDebounce: 0.01, legacyDefaults: defaults)
        XCTAssertEqual(service.current.localState.mainBrowser, "arc")
        XCTAssertEqual(service.current.localState.mediaDownloadFolder, "/tmp/dl")
        XCTAssertNil(defaults.string(forKey: "foundry.mainBrowser"))

        service.flush()
        let decoded = try JSONDecoder().decode(FoundryConfig.self, from: Data(contentsOf: url))
        XCTAssertEqual(decoded.localState.mainBrowser, "arc")
    }

    func testBoundStoreRoundTripsThroughConfigService() throws {
        let url = configURL()
        let service = ConfigService(diagnostics: DiagnosticsService(), url: url, persistDebounce: 0.01, legacyDefaults: nil)
        let store = LocalStateStore(service: service)

        store.set(\.mainBrowser, "firefox")
        XCTAssertEqual(store.get(\.mainBrowser), "firefox")
        XCTAssertEqual(service.current.localState.mainBrowser, "firefox")

        service.flush()
        let decoded = try JSONDecoder().decode(FoundryConfig.self, from: Data(contentsOf: url))
        XCTAssertEqual(decoded.localState.mainBrowser, "firefox")
    }

    func testStandaloneStoreKeepsStateInMemory() {
        let store = LocalStateStore()
        store.set(\.colorPickerRecents, ["#00FF00"])
        store.update { $0.emojiColumns = 14 }
        XCTAssertEqual(store.get(\.colorPickerRecents), ["#00FF00"])
        XCTAssertEqual(store.get(\.emojiColumns), 14)
    }

    func testLocalStateDecodesEmptyFromLegacyConfigJSON() throws {
        // A config written before localState existed still decodes.
        var config = FoundryConfig()
        config.localState.mainBrowser = "safari"
        let data = try JSONEncoder().encode(config)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "localState")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(FoundryConfig.self, from: legacy)
        XCTAssertEqual(decoded.localState, FoundryLocalState())
    }
}
