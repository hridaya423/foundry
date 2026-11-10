import AppKit
import XCTest
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

    func testRetentionChoicesKeepAnUnusualCurrentValue() {
        XCTAssertEqual(SettingsView.itemLimits(current: 500), [100, 250, 500, 1_000, 5_000])
        XCTAssertEqual(SettingsView.itemLimits(current: 300), [100, 250, 300, 500, 1_000, 5_000])
    }
}
