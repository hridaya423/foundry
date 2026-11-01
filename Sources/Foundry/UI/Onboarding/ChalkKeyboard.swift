import AppKit
import Carbon
import FoundryDomain
import SwiftUI

private typealias Brand = FoundryTheme.Brand

struct BoardKey: Identifiable, Sendable {
    enum Kind {
        case modifier(NSEvent.ModifierFlags, carbon: UInt32)
        case key(UInt16)
    }

    let id: String
    let glyph: String
    var name = ""
    let kind: Kind
    var width: CGFloat = 1
    /// Arrow keys are half height; ↓ sits under ↑ in the same slot.
    var isHalf = false
    var below: [BoardKey] = []

    static let modifierFlags: [(flag: NSEvent.ModifierFlags, carbon: UInt32)] = [
        (.control, UInt32(controlKey)), (.option, UInt32(optionKey)), (.shift, UInt32(shiftKey)), (.command, UInt32(cmdKey)),
    ]

    /// Only the left-hand modifiers light up, the way people press a chord.
    func isLit(modifiers: UInt32, keyCode: UInt32?) -> Bool {
        switch kind {
        case .modifier(_, let carbon): modifiers & carbon != 0
        case .key(let code): keyCode == UInt32(code)
        }
    }

    private static func key(_ glyph: String, _ code: Int, name: String = "", width: CGFloat = 1, isHalf: Bool = false) -> BoardKey {
        BoardKey(id: "key-\(code)", glyph: glyph, name: name, kind: .key(UInt16(code)), width: width, isHalf: isHalf)
    }

    private static func modifier(_ glyph: String, _ name: String, _ flag: NSEvent.ModifierFlags, _ carbon: Int, width: CGFloat = 1) -> BoardKey {
        BoardKey(id: name, glyph: glyph, name: name, kind: .modifier(flag, carbon: UInt32(carbon)), width: width)
    }

    /// A MacBook's ANSI letter rows; every row is 15 units wide.
    static let macBook: [[BoardKey]] = [
        [key("", kVK_Tab, name: "tab", width: 1.5), key("Q", kVK_ANSI_Q), key("W", kVK_ANSI_W), key("E", kVK_ANSI_E),
         key("R", kVK_ANSI_R), key("T", kVK_ANSI_T), key("Y", kVK_ANSI_Y), key("U", kVK_ANSI_U), key("I", kVK_ANSI_I),
         key("O", kVK_ANSI_O), key("P", kVK_ANSI_P), key("[", kVK_ANSI_LeftBracket), key("]", kVK_ANSI_RightBracket),
         key("\\", kVK_ANSI_Backslash, width: 1.5)],
        [key("", kVK_CapsLock, name: "caps lock", width: 1.75), key("A", kVK_ANSI_A), key("S", kVK_ANSI_S), key("D", kVK_ANSI_D),
         key("F", kVK_ANSI_F), key("G", kVK_ANSI_G), key("H", kVK_ANSI_H), key("J", kVK_ANSI_J), key("K", kVK_ANSI_K),
         key("L", kVK_ANSI_L), key(";", kVK_ANSI_Semicolon), key("'", kVK_ANSI_Quote), key("", kVK_Return, name: "return", width: 2.25)],
        [modifier("", "shift", .shift, shiftKey, width: 2.25), key("Z", kVK_ANSI_Z), key("X", kVK_ANSI_X), key("C", kVK_ANSI_C),
         key("V", kVK_ANSI_V), key("B", kVK_ANSI_B), key("N", kVK_ANSI_N), key("M", kVK_ANSI_M), key(",", kVK_ANSI_Comma),
         key(".", kVK_ANSI_Period), key("/", kVK_ANSI_Slash), key("", kVK_RightShift, name: "shift", width: 2.75)],
        [key("fn", kVK_Function), modifier("⌃", "control", .control, controlKey), modifier("⌥", "option", .option, optionKey),
         modifier("⌘", "command", .command, cmdKey, width: 1.25), key("", kVK_Space, width: 5.5),
         key("⌘", kVK_RightCommand, name: "command", width: 1.25), key("⌥", kVK_RightOption, name: "option"),
         key("◀︎", kVK_LeftArrow, isHalf: true),
         BoardKey(id: "key-\(kVK_UpArrow)", glyph: "▲", kind: .key(UInt16(kVK_UpArrow)), isHalf: true,
                  below: [key("▼", kVK_DownArrow, isHalf: true)]),
         key("▶︎", kVK_RightArrow, isHalf: true)],
    ]
}

/// Mirrors the physical keyboard while the onboarding window is key, and
/// records a new launcher chord on request.
@MainActor
@Observable
final class KeyboardMirror {
    private(set) var flags: NSEvent.ModifierFlags = []
    private(set) var keysDown: Set<UInt16> = []
    private(set) var flashing = false
    var isRecording = false {
        didSet { if isRecording == false { flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask) } }
    }

    @ObservationIgnored var onRecord: ((FoundryHotkey) -> Void)?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var flashTask: Task<Void, Never>?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.consumes(event) ?? false }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    /// Key-up events land in whichever window took focus, so re-read the
    /// hardware state whenever focus comes back.
    func resync() {
        flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        keysDown.removeAll()
    }

    /// The launcher hotkey is consumed by Carbon before it reaches the
    /// window, so the panel opening is the only sign the key went down.
    func flash() {
        flashTask?.cancel()
        flashing = true
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            self?.flashing = false
        }
    }

    /// The held modifiers as Carbon flags, for lighting keys while recording.
    var heldModifiers: UInt32 {
        BoardKey.modifierFlags.filter { flags.contains($0.flag) }.reduce(0) { $0 | $1.carbon }
    }

    func isPressed(_ key: BoardKey) -> Bool {
        switch key.kind {
        case .modifier(let flag, _): flags.contains(flag)
        case .key(let code): keysDown.contains(code)
        }
    }

    /// Mirrors the event; true when recording swallows it.
    private func consumes(_ event: NSEvent) -> Bool {
        switch event.type {
        case .flagsChanged:
            flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        case .keyDown where isRecording:
            if event.keyCode == UInt16(kVK_Escape) {
                isRecording = false
            } else if let hotkey = FoundryHotkey(recording: event) {
                isRecording = false
                onRecord?(hotkey)
            } else {
                NSSound.beep()
            }
            return true
        case .keyDown:
            keysDown.insert(event.keyCode)
        case .keyUp:
            keysDown.remove(event.keyCode)
        default:
            break
        }
        return false
    }
}

/// A MacBook keyboard in ink, with the launcher chord cast in the website's
/// chalk. Keys dip as they are pressed on the real keyboard.
struct ChalkKeyboard: View {
    let modifiers: UInt32
    let keyCode: UInt32?
    var hot = false
    let isPressed: (BoardKey, _ lit: Bool) -> Bool

    static let unit: CGFloat = 50.5
    static let gap: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            ForEach(BoardKey.macBook.indices, id: \.self) { row in
                HStack(spacing: Self.gap) {
                    ForEach(BoardKey.macBook[row]) { key in
                        VStack(spacing: 2) {
                            ForEach([key] + key.below) { cap($0) }
                        }
                        .frame(width: key.width * Self.unit - Self.gap, height: Self.unit - Self.gap, alignment: .bottom)
                        .zIndex(key.isLit(modifiers: modifiers, keyCode: keyCode) ? 1 : 0)
                    }
                }
                .zIndex(row == BoardKey.macBook.count - 1 ? 1 : 0)
            }
        }
        .accessibilityHidden(true)
    }

    private func cap(_ key: BoardKey) -> some View {
        let lit = key.isLit(modifiers: modifiers, keyCode: keyCode)
        return BoardKeyView(key: key, lit: lit, pressed: isPressed(key, lit), hot: hot)
            .frame(height: key.isHalf ? (Self.unit - Self.gap - 2) / 2 : nil)
    }
}

private struct BoardKeyView: View {
    let key: BoardKey
    let lit: Bool
    let pressed: Bool
    let hot: Bool

    private let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
    private var travel: CGFloat { key.isHalf ? 1.5 : 3 }

    var body: some View {
        ZStack {
            shape
                .fill(lit ? AnyShapeStyle(LinearGradient(colors: hot ? [Brand.accentDeep, Brand.accentSide] : [Brand.chalkSideTop, Brand.chalkSideBottom],
                                                         startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Brand.keyIdleBase))
                .offset(y: travel)
                .shadow(color: lit ? Brand.keyShadow : .clear, radius: pressed ? 3 : 12, y: pressed ? 2 : 9)
            face
                .offset(y: pressed ? travel : 0)
        }
        .animation(pressed ? Brand.Motion.press : Brand.Motion.release, value: pressed)
        .animation(Brand.Motion.state, value: lit)
        .animation(Brand.Motion.enter, value: hot)
    }

    private var face: some View {
        ZStack {
            shape.fill(LinearGradient(colors: [Brand.keyIdleTop, Brand.keyIdleBottom], startPoint: .top, endPoint: .bottom))
            shape.strokeBorder(Brand.keyIdleEdge, lineWidth: 1)
            Group {
                shape.fill(LinearGradient(stops: [
                    .init(color: Brand.chalkTop, location: 0),
                    .init(color: Brand.chalkMid, location: 0.55),
                    .init(color: Brand.chalkBottom, location: 1),
                ], startPoint: .top, endPoint: .bottom))
                shape.fill(LinearGradient(colors: [Brand.accent, Brand.accentDeep], startPoint: .top, endPoint: .bottom))
                    .opacity(hot ? 1 : 0)
                shape.strokeBorder(LinearGradient(colors: [Brand.chalkHighlight, .clear, Brand.chalkEdge],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .opacity(lit ? 1 : 0)
            Group {
                if key.isHalf {
                    Text(key.glyph).font(Brand.keyName)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(key.glyph).font(Brand.keyGlyph)
                        Spacer(minLength: 0)
                        Text(key.name).font(Brand.keyName)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .foregroundStyle(lit ? Brand.legend : Brand.keyIdleLegend)
        }
    }
}
