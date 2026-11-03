import Carbon
import FoundryDomain

enum WindowHotkeySuggestions {
    static let all: [(placement: WindowPlacement, hotkey: FoundryHotkey)] = [
        (.leftHalf, chord(kVK_LeftArrow, "←")),
        (.rightHalf, chord(kVK_RightArrow, "→")),
        (.topHalf, chord(kVK_UpArrow, "↑")),
        (.bottomHalf, chord(kVK_DownArrow, "↓")),
        (.maximize, chord(kVK_Return, "↩")),
        (.center, chord(kVK_ANSI_C, "C"))
    ]

    static var summary: String { all.map(\.hotkey.displayName).joined(separator: "  ") }

    static func commandID(for placement: WindowPlacement) -> String { "window.\(placement.rawValue)" }

    private static func chord(_ keyCode: Int, _ key: String) -> FoundryHotkey {
        FoundryHotkey(keyCode: UInt32(keyCode), modifiers: UInt32(controlKey | optionKey), displayName: "⌃⌥\(key)")
    }
}
