import Carbon
import XCTest
@testable import Foundry

final class StatusItemMenuTests: XCTestCase {
    func testMenuItemsReflectState() {
        let ready = StatusItemMenuModel(hotkey: .optionSpace, clipboardPaused: false, hotkeyFailed: false)
        XCTAssertEqual(
            ready.items.map(\.kind),
            [.openFoundry, .clipboardHistory, .clipboardPauseToggle, .separator, .settings, .welcomeGuide, .separator, .quit]
        )
        XCTAssertEqual(ready.items.map(\.title).filter { $0.isEmpty == false }, ["Open Foundry", "Clipboard History", "Pause Clipboard", "Settings…", "Welcome Guide", "Quit Foundry"])
        let openItem = ready.items.first { $0.kind == .openFoundry }
        XCTAssertEqual(openItem?.keyEquivalent, " ")
        XCTAssertEqual(openItem?.keyEquivalentModifierMask, .option)

        let paused = StatusItemMenuModel(hotkey: .optionSpace, clipboardPaused: true, hotkeyFailed: true)
        XCTAssertEqual(paused.items.first?.kind, .hotkeyWarning)
        XCTAssertEqual(paused.items.first?.title, "⌥ Space is unavailable — Choose Another Shortcut…")
        XCTAssertTrue(paused.items.contains { $0.kind == .clipboardPauseToggle && $0.title == "Resume Clipboard" })
    }

    func testNonSpaceHotkeyRendersInTitle() {
        let hotkey = FoundryHotkey(keyCode: 0, modifiers: UInt32(cmdKey), displayName: "⌘A")
        let model = StatusItemMenuModel(hotkey: hotkey, clipboardPaused: false, hotkeyFailed: true)

        let openItem = model.items.first { $0.kind == .openFoundry }
        XCTAssertEqual(openItem?.title, "Open Foundry (⌘A)")
        XCTAssertEqual(model.items.first?.title, "⌘A is unavailable — Choose Another Shortcut…")
    }
}
