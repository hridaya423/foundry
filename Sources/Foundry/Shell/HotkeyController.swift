import Carbon
import Foundation

struct FoundryHotkey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var displayName: String

    static let commandSpace = FoundryHotkey(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey),
        displayName: "⌘ Space"
    )

    static let optionSpace = FoundryHotkey(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey),
        displayName: "⌥ Space"
    )
}

enum HotkeyError: Error {
    case registrationFailed(OSStatus)
}

final class HotkeyController {
    var onPressed: (() -> Void)?

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var registeredHotkey: FoundryHotkey?

    func register(hotkey: FoundryHotkey) throws {
        if registeredHotkey == hotkey { return }

        let hotkeyID = EventHotKeyID(signature: OSType(0x464E4459), id: 1)
        var newHotkeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &newHotkeyRef
        )

        guard status == noErr else {
            throw HotkeyError.registrationFailed(status)
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        var newEventHandler: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
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
            &newEventHandler
        )
        guard handlerStatus == noErr else {
            if let newHotkeyRef { UnregisterEventHotKey(newHotkeyRef) }
            throw HotkeyError.registrationFailed(handlerStatus)
        }

        unregister()
        hotkeyRef = newHotkeyRef
        eventHandler = newEventHandler
        registeredHotkey = hotkey
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
        registeredHotkey = nil
    }
}
