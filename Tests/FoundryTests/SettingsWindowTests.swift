import AppKit
import SwiftUI
import XCTest
import FoundryDomain
import FoundryServices
@testable import Foundry

@MainActor
final class SettingsWindowTests: XCTestCase {
    func testWindowRestoresFrameAndPane() {
        let name = "FoundrySettingsTest-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(name)") }
        let saved = NSRect(x: 120, y: 140, width: 700, height: 500)
        let first = NSWindow(contentRect: saved, styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        first.setFrame(saved, display: false)
        first.saveFrame(usingName: name)

        let blank = NSRect(x: 0, y: 0, width: 680, height: 480)
        let restored = NSWindow(contentRect: blank, styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        XCTAssertTrue(restored.setFrameUsingName(name))

        let second = NSWindow(contentRect: blank, styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        SettingsWindowController.place(second, autosaveName: name)

        XCTAssertEqual(second.frame.size, saved.size)
        XCTAssertEqual(second.frame, restored.frame, "a saved frame is not overridden by center()")
        XCTAssertEqual(second.frameAutosaveName, name)
    }

    func testTheWindowKeepsItsDefaultAndMinimumSizeOnceItsContentLaysOut() {
        let window = SettingsWindowController.makeWindow(rootView: Color.clear)
        XCTAssertEqual(window.frame.size, NSSize(width: 820, height: 600))

        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        XCTAssertEqual(window.minSize, NSSize(width: 720, height: 560), "the hosting controller must not replace the minimum with the content's own")
        XCTAssertEqual(window.frame.size, NSSize(width: 820, height: 600))
    }

    func testReopeningOnTheCommandsPaneLoadsItsCatalog() throws {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID()).json"))
        let state = CommandPanelState.isolated(
            registry: CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config),
            actionRunner: ActionRunner.isolated(diagnostics: diagnostics),
            diagnostics: diagnostics,
            config: config
        )
        defer { state.shutdown() }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: isolatedDefaultsSuite("settings-reopen")))
        defaults.set(SettingsCategory.commands.rawValue, forKey: "settings.lastPane")

        let window = SettingsWindowController.makeWindow(rootView: SettingsView(state: state).defaultAppStorage(defaults))
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        XCTAssertTrue(state.settings.isCommandCatalogReady, "the remembered pane loads without a click on its rail item")
    }

    func testRetentionChoicesKeepAnUnusualCurrentValue() {
        XCTAssertEqual(SettingsView.itemLimits(current: 500), [100, 250, 500, 1_000, 5_000])
        XCTAssertEqual(SettingsView.itemLimits(current: 300), [100, 250, 300, 500, 1_000, 5_000])
    }
}
