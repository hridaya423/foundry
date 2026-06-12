import Carbon
import Foundation

struct FoundryHotkey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var displayName: String

    static let optionSpace = FoundryHotkey(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey),
        displayName: "Option-Space"
    )
}

enum HotkeyError: Error {
    case registrationFailed(OSStatus)
}

final class HotkeyController {
    var onPressed: (() -> Void)?

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func register(hotkey: FoundryHotkey) throws {
        unregister()

        let hotkeyID = EventHotKeyID(signature: OSType(0x464E4459), id: 1) // FNDY
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard status == noErr else {
            throw HotkeyError.registrationFailed(status)
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
                controller.onPressed?()
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
    }

    func unregister() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
