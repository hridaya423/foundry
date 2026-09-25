import AppKit
import XCTest
@testable import Foundry

@MainActor
final class MainMenuTests: XCTestCase {
    func testStandardEditingAndWindowChordsHaveMenuItems() {
        let items = MainMenu.make().items.flatMap { $0.submenu?.items ?? [] }
        func action(for key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> Selector? {
            items.first { $0.keyEquivalent == key && $0.keyEquivalentModifierMask == modifiers }?.action
        }
        XCTAssertEqual(action(for: "c"), #selector(NSText.copy(_:)))
        XCTAssertEqual(action(for: "x"), #selector(NSText.cut(_:)))
        XCTAssertEqual(action(for: "v"), #selector(NSText.paste(_:)))
        XCTAssertEqual(action(for: "a"), #selector(NSText.selectAll(_:)))
        XCTAssertEqual(action(for: "z"), Selector(("undo:")))
        XCTAssertEqual(action(for: "z", [.command, .shift]), Selector(("redo:")))
        XCTAssertEqual(action(for: "w"), #selector(NSWindow.performClose(_:)))
    }
}
