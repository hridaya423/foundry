import AppKit
import Carbon
import SwiftUI
import FoundryDomain

struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(.horizontal, 2)
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.primary.opacity(0.045), lineWidth: 1)
            )
    }
}

struct SettingsSectionLabel: View {
    let title: String
    let value: String?

    init(title: String, value: String? = nil) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack {
            Text(title)
                .font(FoundryTheme.body(size: 13, weight: .semibold))
                .foregroundStyle(FoundryTheme.primaryText.opacity(0.78))
            Spacer()
            if let value {
                Text(value)
                    .font(FoundryTheme.body(size: 12, weight: .medium))
                    .foregroundStyle(FoundryTheme.mutedText)
            }
        }
        .padding(.horizontal, 2)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
            .padding(.horizontal, 12)
    }
}

struct SettingsLabel: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(FoundryTheme.body(size: 14, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)
            Text(subtitle)
                .font(FoundryTheme.body(size: 12, weight: .regular))
                .foregroundStyle(FoundryTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let isOn: Bool
    let set: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            SettingsLabel(title: title, subtitle: subtitle)
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { value in set(value) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
                .accessibilityValue(isOn ? "On" : "Off")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

struct SettingsNotice: View {
    let text: String
    let symbol: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        InlineNotice(level: .error, text: text, symbol: symbol, actionTitle: actionTitle, action: action)
    }
}

struct SettingsTextFieldRow: View {
    let title: String
    let placeholder: String
    let value: String
    let error: String?
    let commit: (String) -> Void

    @State private var text: String

    init(title: String, placeholder: String, value: String, error: String?, commit: @escaping (String) -> Void) {
        self.title = title
        self.placeholder = placeholder
        self.value = value
        self.error = error
        self.commit = commit
        _text = State(initialValue: value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(title)
                    .font(FoundryTheme.body(size: 13, weight: .medium))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .frame(width: 72, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .font(FoundryTheme.body(size: 14, weight: .medium))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .onSubmit { commit(text) }
                }
                Spacer()
            }
            if let error {
                Text(error)
                    .font(FoundryTheme.body(size: 11, weight: .medium))
                    .foregroundStyle(FoundryTheme.error)
                    .padding(.leading, 44)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .onAppear { text = value }
        .onChange(of: value) { _, newValue in text = newValue }
    }
}

struct SettingsSecureFieldRow: View {
    let title: String
    let placeholder: String
    @Binding var value: String
    let commit: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(FoundryTheme.body(size: 13, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)
                .frame(width: 72, alignment: .leading)
            SecureField(placeholder, text: $value)
                .textFieldStyle(.plain)
                .font(FoundryTheme.body(size: 14, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)
                .onSubmit { commit(value) }
            Button("Save") {
                commit(value)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let hotkey: FoundryHotkey
    var placeholder: String? = nil
    let onChange: (FoundryHotkey) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.onHotkey = context.coordinator.record
        view.hotkey = hotkey
        view.placeholder = placeholder
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.hotkey = hotkey
        view.placeholder = placeholder
        view.onHotkey = context.coordinator.record
    }

    final class Coordinator {
        let onChange: (FoundryHotkey) -> Void

        init(onChange: @escaping (FoundryHotkey) -> Void) { self.onChange = onChange }

        func record(_ hotkey: FoundryHotkey) { onChange(hotkey) }
    }
}

final class ShortcutRecorderView: NSView {
    var hotkey = FoundryHotkey.commandSpace { didSet { needsDisplay = true } }
    var placeholder: String? { didSet { needsDisplay = true } }
    var onHotkey: ((FoundryHotkey) -> Void)?
    private var isRecording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let background = isRecording ? NSColor.labelColor.withAlphaComponent(0.14) : NSColor.labelColor.withAlphaComponent(0.08)
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()

        let text = isRecording ? "Press shortcut…" : (placeholder ?? hotkey.displayName)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(isRecording ? 0.7 : 0.95)
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = carbonModifiers(from: flags)
        guard modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else {
            NSSound.beep()
            return
        }
        guard let keyName = keyName(for: event) else {
            NSSound.beep()
            return
        }

        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        parts.append(keyName)

        isRecording = false
        onHotkey?(FoundryHotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers, displayName: parts.joined()))
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    private func keyName(for event: NSEvent) -> String? {
        let names: [UInt16: String] = [
            UInt16(kVK_Return): "↩",
            UInt16(kVK_Tab): "⇥",
            UInt16(kVK_Space): "Space",
            UInt16(kVK_Delete): "⌫",
            UInt16(kVK_Escape): "Esc",
            UInt16(kVK_LeftArrow): "←",
            UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑",
            UInt16(kVK_DownArrow): "↓"
        ]
        if let name = names[event.keyCode] { return name }
        guard let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines), characters.isEmpty == false else {
            return nil
        }
        return characters.uppercased()
    }
}

struct ActiveWidgetRow: View {
    let kind: WidgetKind
    let isFirst: Bool
    let isLast: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FoundryTheme.secondaryText)
                .frame(width: 20)
            SettingsLabel(title: kind.title, subtitle: kind.summary)
            Spacer()
            SettingsIconButton(symbol: "chevron.up", label: "Move \(kind.title) up", action: moveUp)
                .disabled(isFirst)
                .opacity(isHovering ? (isFirst ? 0.3 : 1) : 0.12)
            SettingsIconButton(symbol: "chevron.down", label: "Move \(kind.title) down", action: moveDown)
                .disabled(isLast)
                .opacity(isHovering ? (isLast ? 0.3 : 1) : 0.12)
            SettingsIconButton(symbol: "minus", label: "Remove \(kind.title)", action: remove, tint: FoundryTheme.error)
                .opacity(isHovering ? 1 : 0.12)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

struct AvailableWidgetRow: View {
    let kind: WidgetKind
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            HStack(spacing: 10) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .frame(width: 20)
                SettingsLabel(title: kind.title, subtitle: kind.summary)
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}

struct SettingsIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var tint: Color = FoundryTheme.secondaryText

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
        .pointerCursor()
    }
}

struct ConfigFieldRow: View {
    let title: String
    let placeholder: String
    let initialValue: String
    let commit: (String) -> Void
    @State private var text = ""

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(FoundryTheme.body(size: 13, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)
                .frame(width: 112, alignment: .leading)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(FoundryTheme.body(size: 14, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)
                .onSubmit { commit(text) }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .onAppear { text = initialValue }
    }
}

struct CommandSettingsRow: View {
    let row: CommandSettingsRowModel
    let isExpanded: Bool
    let setEnabled: (Bool) -> Void
    let setFavorite: (Bool) -> Void
    let commitAliases: (String) -> Void
    let setHotkey: (FoundryHotkey?) -> Void
    let setFallbackEligible: (Bool) -> Void
    let reset: () -> Void
    let toggleExpanded: () -> Void

    @State private var aliasesText: String

    init(
        row: CommandSettingsRowModel,
        isExpanded: Bool,
        setEnabled: @escaping (Bool) -> Void,
        setFavorite: @escaping (Bool) -> Void,
        commitAliases: @escaping (String) -> Void,
        setHotkey: @escaping (FoundryHotkey?) -> Void,
        setFallbackEligible: @escaping (Bool) -> Void,
        reset: @escaping () -> Void,
        toggleExpanded: @escaping () -> Void
    ) {
        self.row = row
        self.isExpanded = isExpanded
        self.setEnabled = setEnabled
        self.setFavorite = setFavorite
        self.commitAliases = commitAliases
        self.setHotkey = setHotkey
        self.setFallbackEligible = setFallbackEligible
        self.reset = reset
        self.toggleExpanded = toggleExpanded
        _aliasesText = State(initialValue: row.preference.aliases.joined(separator: ", "))
    }

    private var suggestedHotkey: CommandHotkey? {
        guard row.id.hasPrefix("window.") else { return nil }
        return WindowPlacement(rawValue: String(row.id.dropFirst(7)))?.suggestedHotkey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                CommandSettingsIcon(icon: row.icon)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(FoundryTheme.body(size: 14, weight: .semibold))
                        .foregroundStyle(row.preference.isEnabled ? FoundryTheme.primaryText : FoundryTheme.mutedText)
                        .lineLimit(1)
                    Text(row.subtitle)
                        .font(FoundryTheme.body(size: 11, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    setFavorite(row.preference.favoriteRank == nil)
                } label: {
                    Image(systemName: row.preference.favoriteRank == nil ? "star" : "star.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(row.preference.favoriteRank == nil ? FoundryTheme.mutedText : FoundryTheme.accent)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.preference.favoriteRank == nil ? "Favorite \(row.title)" : "Remove \(row.title) from favorites")

                Toggle("", isOn: Binding(get: { row.preference.isEnabled }, set: { value in setEnabled(value) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.82)
                    .accessibilityLabel("Enable \(row.title)")

                Button {
                    if isExpanded {
                        commitAliases(aliasesText)
                    }
                    toggleExpanded()
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Hide settings for \(row.title)" : "Show settings for \(row.title)")
            }

            if isExpanded {
                HStack(spacing: 8) {
                    Text("Aliases")
                        .font(FoundryTheme.body(size: 11, weight: .medium))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .frame(width: 48, alignment: .leading)
                    TextField("comma separated", text: $aliasesText)
                        .textFieldStyle(.plain)
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .onSubmit { commitAliases(aliasesText) }
                    Spacer()
                    if row.preference.aliases.isEmpty == false || row.preference.favoriteRank != nil || row.preference.isEnabled == false || row.preference.globalHotkey != nil || row.preference.fallbackEligible == false {
                        Button("Reset") { reset() }
                            .buttonStyle(.plain)
                            .font(FoundryTheme.body(size: 11, weight: .medium))
                            .foregroundStyle(FoundryTheme.mutedText)
                    }
                }

                HStack(spacing: 8) {
                    Text("Hotkey")
                        .font(FoundryTheme.body(size: 11, weight: .medium))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .frame(width: 48, alignment: .leading)
                    ShortcutRecorder(
                        hotkey: row.preference.globalHotkey.map {
                            FoundryHotkey(keyCode: $0.keyCode, modifiers: $0.modifiers, displayName: $0.displayName)
                        } ?? FoundryHotkey(keyCode: 0, modifiers: 0, displayName: "Set shortcut"),
                        placeholder: row.preference.globalHotkey == nil ? "Set shortcut" : nil,
                        onChange: { setHotkey($0) }
                    )
                    .frame(width: 132, height: 28)
                    if row.preference.globalHotkey != nil {
                        Button("Clear") { setHotkey(nil) }
                            .buttonStyle(.plain)
                            .font(FoundryTheme.body(size: 11, weight: .medium))
                            .foregroundStyle(FoundryTheme.mutedText)
                    } else if let suggested = suggestedHotkey {
                        Button("Use \(suggested.displayName)") {
                            setHotkey(FoundryHotkey(keyCode: suggested.keyCode, modifiers: suggested.modifiers, displayName: suggested.displayName))
                        }
                        .buttonStyle(.plain)
                        .font(FoundryTheme.body(size: 11, weight: .medium))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .help("Rectangle-style suggested shortcut")
                    }
                    Spacer()
                }

                Toggle("Use as fallback result", isOn: Binding(
                    get: { row.preference.fallbackEligible },
                    set: { setFallbackEligible($0) }
                ))
                .toggleStyle(.switch)
                .font(FoundryTheme.body(size: 11, weight: .medium))
                .foregroundStyle(FoundryTheme.mutedText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .onChange(of: row.preference.aliases) { _, newValue in
            aliasesText = newValue.joined(separator: ", ")
        }
        .onChange(of: isExpanded) { wasExpanded, nowExpanded in
            if wasExpanded && !nowExpanded {
                commitAliases(aliasesText)
            }
        }
    }
}

struct CommandSettingsIcon: View {
    let icon: CommandIcon
    @State private var appImage: NSImage?

    var body: some View {
        Group {
            if let appImage {
                Image(nsImage: appImage)
                    .resizable()
                    .scaledToFit()
            } else if let systemName = icon.systemName {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
            } else {
                Text(icon.fallback)
                    .font(FoundryTheme.body(size: 10, weight: .bold))
                    .foregroundStyle(FoundryTheme.secondaryText)
            }
        }
        .frame(width: 28, height: 28)
        .task(id: icon.filePath) {
            guard let filePath = icon.filePath else { return }
            appImage = await CommandIconRepository.shared.image(for: filePath)
        }
    }
}
