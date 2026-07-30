import XCTest
@testable import Foundry

final class SystemCommandProviderTests: XCTestCase {
    func testSettingsShortcutsOpenNativeSystemSettingsPanes() async throws {
        let provider = SystemCommandProvider(diagnostics: DiagnosticsService())
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
        let provider = SystemCommandProvider(diagnostics: DiagnosticsService())

        let wifiResults = await provider.results(matching: "wireless")
        XCTAssertEqual(wifiResults.first?.id, "system.settings.wifi")

        let storageResults = await provider.results(matching: "disk space")
        XCTAssertEqual(storageResults.first?.id, "system.settings.storage")

        let bluetoothResults = await provider.results(matching: "bluetooth devices")
        XCTAssertEqual(bluetoothResults.first?.id, "system.settings.bluetooth")
    }
}
