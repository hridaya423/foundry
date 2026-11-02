import AppKit
import Carbon
import XCTest
@testable import Foundry

@MainActor
final class ShortcutRecorderTests: XCTestCase {
    private func key(_ code: Int, _ characters: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(code))!
    }

    func testReturnStartsRecordingEscapeCancelsAndAChordRecords() {
        let view = ShortcutRecorderView()
        var recorded: FoundryHotkey?
        view.onHotkey = { recorded = $0 }
        view.keyDown(with: key(kVK_Return, "\r"))
        XCTAssertTrue(view.isRecording)
        view.keyDown(with: key(kVK_Escape, "\u{1B}"))
        XCTAssertFalse(view.isRecording)
        XCTAssertNil(recorded)
        view.keyDown(with: key(kVK_Space, " "))
        view.keyDown(with: key(kVK_ANSI_K, "k", [.command, .option]))
        XCTAssertFalse(view.isRecording)
        XCTAssertEqual(recorded?.keyCode, UInt32(kVK_ANSI_K))
    }

    func testDeleteClearsOnlyWhenClearingIsOffered() {
        let view = ShortcutRecorderView()
        var cleared = 0
        view.keyDown(with: key(kVK_Delete, "\u{7F}"))
        view.onClear = { cleared += 1 }
        view.keyDown(with: key(kVK_Delete, "\u{7F}"))
        XCTAssertEqual(cleared, 1)
        XCTAssertFalse(view.isRecording)
    }
}
