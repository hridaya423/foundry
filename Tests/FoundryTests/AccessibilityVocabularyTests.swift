import AppKit
import SwiftUI
import XCTest
import FoundryDomain
@testable import Foundry

@MainActor
final class AccessibilityVocabularyTests: XCTestCase {
    func testSpokenHotkeyNames() {
        XCTAssertEqual(HotkeyFormatter.spoken("⌘↵"), "Command Return")
        XCTAssertEqual(HotkeyFormatter.spoken("⇧⌘C"), "Shift Command C")
        XCTAssertEqual(HotkeyFormatter.spoken("⌃⌥Space"), "Control Option Space")
        XCTAssertEqual(HotkeyFormatter.spoken("esc"), "Escape")
        XCTAssertEqual(HotkeyFormatter.spoken("⌘⌫"), "Command Delete")
    }

    func testQuietTextKeepsItsTunedAlphaAtDefaultContrast() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast, "Increase Contrast is on")
        XCTAssertEqual(NSColor(FoundryTheme.textTertiary).alphaComponent, 0.56, accuracy: 0.01)
        XCTAssertEqual(NSColor(FoundryTheme.textQuaternary).alphaComponent, 0.44, accuracy: 0.01)
    }
}
