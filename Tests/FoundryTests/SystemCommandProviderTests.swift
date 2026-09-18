import XCTest
import FoundryDomain
import FoundryServices
@testable import Foundry

final class SystemCommandProviderTests: XCTestCase {
    func testSettingsShortcutsOpenNativeSystemSettingsPanes() async throws {
        let provider = SystemCommandProvider()
        let shortcuts = [
            (query: "wifi", id: "system.settings.wifi", url: "x-apple.systempreferences:com.apple.wifi-settings.extension"),
            (query: "bluetooth", id: "system.settings.bluetooth", url: "x-apple.systempreferences:com.apple.BluetoothSettings"),
            (query: "network", id: "system.settings.network", url: "x-apple.systempreferences:com.apple.Network-Settings.extension"),
            (query: "storage", id: "system.settings.storage", url: "x-apple.systempreferences:com.apple.settings.Storage"),
            (query: "trackpad", id: "system.settings.trackpad", url: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension"),
            (query: "software update", id: "system.settings.software-update", url: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")
        ]

        for shortcut in shortcuts {
            let results = await provider.results(matching: shortcut.query)
            let result = try XCTUnwrap(results.first { $0.id == shortcut.id })
            XCTAssertEqual(result.primaryAction.kind, .openURL(shortcut.url))
        }
    }

    func testSettingsAliasesFindTheExpectedPane() async throws {
        let provider = SystemCommandProvider()

        let wifiResults = await provider.results(matching: "wireless")
        XCTAssertEqual(wifiResults.first?.id, "system.settings.wifi")

        let storageResults = await provider.results(matching: "disk space")
        XCTAssertEqual(storageResults.first?.id, "system.settings.storage")

        let bluetoothResults = await provider.results(matching: "bluetooth devices")
        XCTAssertEqual(bluetoothResults.first?.id, "system.settings.bluetooth")
    }

    func testEmptyQueryShowsNoSettingsPanes() async {
        let results = await SystemCommandProvider().results(matching: "")
        XCTAssertFalse(results.contains { CommandSettingsCatalog.isSystemSettingsPane($0.id) })
    }

    func testCommandsCatalogShowsOneSystemSettingsRow() {
        let icon = CommandIcon(fallback: "SE", systemName: nil)
        let descriptors = ["system.settings", "system.settings.wifi", "system.settings.bluetooth", "system.lock-screen"].map {
            CommandDescriptor(id: $0, sourceID: "foundry.system", title: $0, subtitle: nil, category: "System", icon: icon)
        }
        let catalog = CommandSettingsCatalog.build(descriptors: descriptors, preferences: [:], query: "")
        XCTAssertEqual(Set(catalog.rows.map(\.id)), ["system.settings", "system.lock-screen"])
    }

    func testDisablingSystemSettingsHidesEveryPane() async throws {
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-system-settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config = ConfigService(diagnostics: DiagnosticsService(), url: configURL)
        let registry = CommandRegistry(providers: [SystemCommandProvider()], usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()), diagnostics: DiagnosticsService(), configService: config)
        let before = await registry.fullResults(matching: "wifi")
        XCTAssertTrue(before.contains { $0.id == "system.settings.wifi" })

        var preference = CommandPreference()
        preference.isEnabled = false
        try config.updateCommandPreference(preference, for: "system.settings")
        let after = await registry.fullResults(matching: "wifi")
        XCTAssertFalse(after.contains { CommandSettingsCatalog.isSystemSettingsPane($0.id) })
    }
}
