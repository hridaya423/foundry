import AppKit
import Carbon
import Foundation
import FoundryDomain
import FoundryServices

struct FoundryHotkey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var displayName: String

    static let commandSpace = FoundryHotkey(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey),
        displayName: HotkeyFormatter.displayName(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
    )

    static let optionSpace = FoundryHotkey(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey),
        displayName: HotkeyFormatter.displayName(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    )
}

extension FoundryHotkey {
    /// A launcher chord from a key press: it needs ⌘, ⌥ or ⌃ and a nameable key.
    init?(recording event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        guard modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
        let typed = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let keyName = HotkeyFormatter.keyName(UInt32(event.keyCode)) ?? (typed?.isEmpty == false ? typed : nil) else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, displayName: HotkeyFormatter.modifierString(modifiers) + keyName)
    }
}

enum HotkeyError: Error {
    case registrationFailed(OSStatus)
}

final class HotkeyController {
    var onPressed: (() -> Void)?

    private static let launcherHotkeyID: UInt32 = 1
    private static let commandHotkeyBaseID: UInt32 = 1_000
    private static let signature = OSType(0x464E4459)

    private var hotkeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var registeredHotkey: FoundryHotkey?
    private var registeredCommandHotkeys: [String: FoundryHotkey] = [:]
    private var commandIDsByHotkeyID: [UInt32: String] = [:]
    private var onCommandPressed: ((String) -> Void)?

    func register(hotkey: FoundryHotkey) throws {
        if registeredHotkey == hotkey { return }

        try ensureEventHandler()
        let newHotkeyRef = try registerRaw(hotkey: hotkey, id: Self.launcherHotkeyID)
        if let oldHotkeyRef = hotkeyRefs[Self.launcherHotkeyID] {
            UnregisterEventHotKey(oldHotkeyRef)
        }
        hotkeyRefs[Self.launcherHotkeyID] = newHotkeyRef
        registeredHotkey = hotkey
    }

    /// Registers each command hotkey on its own, so one chord taken by macOS or another app disables only that command.
    /// Returns the IDs of the commands whose hotkeys could not be registered.
    @discardableResult
    func registerCommandHotkeys(
        _ hotkeys: [String: FoundryHotkey],
        onPressed: @escaping (String) -> Void
    ) throws -> [String] {
        unregisterCommandHotkeys()
        guard hotkeys.isEmpty == false else { return [] }

        try ensureEventHandler()
        var failed: [String] = []
        var registered: [String: FoundryHotkey] = [:]
        for (offset, entry) in hotkeys.sorted(by: { $0.key < $1.key }).enumerated() {
            let id = Self.commandHotkeyBaseID + UInt32(offset)
            guard let ref = try? registerRaw(hotkey: entry.value, id: id) else {
                failed.append(entry.key)
                continue
            }
            hotkeyRefs[id] = ref
            commandIDsByHotkeyID[id] = entry.key
            registered[entry.key] = entry.value
        }
        registeredCommandHotkeys = registered
        onCommandPressed = onPressed
        return failed
    }

    func unregisterCommandHotkeys() {
        for id in commandIDsByHotkeyID.keys {
            if let ref = hotkeyRefs.removeValue(forKey: id) {
                UnregisterEventHotKey(ref)
            }
        }
        commandIDsByHotkeyID.removeAll()
        registeredCommandHotkeys.removeAll()
        onCommandPressed = nil
    }

    func unregister() {
        for ref in hotkeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotkeyRefs.removeAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        registeredHotkey = nil
        registeredCommandHotkeys.removeAll()
        commandIDsByHotkeyID.removeAll()
        onCommandPressed = nil
    }

    private func ensureEventHandler() throws {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        var newEventHandler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
                var hotkeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                guard parameterStatus == noErr else { return parameterStatus }
                controller.handleHotkey(id: hotkeyID.id)
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &newEventHandler
        )
        guard status == noErr, let newEventHandler else {
            throw HotkeyError.registrationFailed(status)
        }
        eventHandler = newEventHandler
    }

    private func registerRaw(hotkey: FoundryHotkey, id: UInt32) throws -> EventHotKeyRef {
        let hotkeyID = EventHotKeyID(signature: Self.signature, id: id)
        var newHotkeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &newHotkeyRef
        )
        guard status == noErr, let newHotkeyRef else {
            throw HotkeyError.registrationFailed(status)
        }
        return newHotkeyRef
    }

    private func handleHotkey(id: UInt32) {
        if id == Self.launcherHotkeyID {
            onPressed?()
        } else if let commandID = commandIDsByHotkeyID[id] {
            onCommandPressed?(commandID)
        }
    }
}
