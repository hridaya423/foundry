import Foundation

/// Single source of truth for rendering hotkey chords as user-facing strings.
/// Output uses the standard ⌃⌥⇧⌘ modifier order with no spaces, e.g.
/// `⌥Space`, `⇧⌘V`, `⌃⌥⇧↩`.
public enum HotkeyFormatter {
    public static let cmdKeyFlag: UInt32 = 256
    public static let shiftKeyFlag: UInt32 = 512
    public static let optionKeyFlag: UInt32 = 2048
    public static let controlKeyFlag: UInt32 = 4096

    /// ANSI key-code → display name. Covers everything the launcher lets
    /// users bind (letters, digits, punctuation, function keys, navigation).
    static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        76: "↩", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
        101: "F9", 103: "F11", 109: "F10", 111: "F12",
        114: "Help", 115: "Home", 116: "PageUp", 117: "⌦",
        118: "F4", 119: "End", 120: "F2", 121: "PageDown", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    /// Modifier glyphs in ⌃⌥⇧⌘ order.
    public static func modifierString(_ modifiers: UInt32) -> String {
        var result = ""
        if modifiers & controlKeyFlag != 0 { result += "⌃" }
        if modifiers & optionKeyFlag != 0 { result += "⌥" }
        if modifiers & shiftKeyFlag != 0 { result += "⇧" }
        if modifiers & cmdKeyFlag != 0 { result += "⌘" }
        return result
    }

    /// Display name for a bare key code, or nil for an unmapped key.
    public static func keyName(_ keyCode: UInt32) -> String? {
        keyNames[keyCode]
    }

    /// Full chord display, e.g. `⇧⌘V`. Keys not in the ANSI table render
    /// as `?` so a bad binding is visible instead of silently empty.
    public static func displayName(keyCode: UInt32, modifiers: UInt32) -> String {
        modifierString(modifiers) + (keyName(keyCode) ?? "?")
    }

    static let spokenNames: [Character: String] = [
        "⌃": "Control", "⌥": "Option", "⇧": "Shift", "⌘": "Command",
        "↵": "Return", "↩": "Return", "⌫": "Delete", "⌦": "Forward Delete", "⇥": "Tab", "⎋": "Escape",
        "↑": "Up Arrow", "↓": "Down Arrow", "←": "Left Arrow", "→": "Right Arrow",
    ]

    /// The chord as VoiceOver should read it, e.g. `⇧⌘C` → "Shift Command C".
    public static func spoken(_ display: String) -> String {
        if display.lowercased() == "esc" { return "Escape" }
        var words: [String] = []
        var rest = ""
        for character in display {
            if let name = spokenNames[character] {
                if rest.isEmpty == false { words.append(rest); rest = "" }
                words.append(name)
            } else {
                rest.append(character)
            }
        }
        if rest.isEmpty == false { words.append(rest) }
        return words.joined(separator: " ")
    }
}