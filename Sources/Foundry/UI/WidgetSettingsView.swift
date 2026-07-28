import AppKit
import Carbon
import SwiftUI

struct WidgetSettingsView: View {
    @ObservedObject var state: CommandPanelState
    @State private var category: SettingsCategory = .general

    var body: some View {
        HStack(spacing: 0) {
            settingsRail
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
            detailPane
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private var settingsRail: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsCategory.allCases) { item in
                Button {
                    category = item
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18)
                        Text(item.title)
                            .font(FoundryTheme.body(size: 13, weight: .medium))
                    }
                    .foregroundStyle(category == item ? FoundryTheme.primaryText : FoundryTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(category == item ? 0.07 : 0))
                    )
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(category == item ? .isSelected : [])
            }

            Spacer()
        }
        .frame(width: 148, alignment: .leading)
        .padding(.top, 8)
        .padding(.trailing, 8)
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = state.settingsPersistenceError {
                SettingsNotice(text: error, symbol: "exclamationmark.triangle")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch category {
                    case .general:
                        generalContent
                    case .appearance:
                        appearanceContent
                    case .ai:
                        aiContent
                    case .widgets:
                        widgetsContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var generalContent: some View {
        SettingsGroup {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 12) {
                        SettingsLabel(title: "Global shortcut", subtitle: "Open Foundry from anywhere")
                        Spacer()
                        ShortcutRecorder(hotkey: state.hotkey, onChange: state.setHotkey)
                            .frame(width: 120, height: 30)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                if let error = state.hotkeyError {
                    Text(error)
                        .font(FoundryTheme.body(size: 12, weight: .medium))
                        .foregroundStyle(FoundryTheme.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private var appearanceContent: some View {
        SettingsGroup {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SettingsLabel(
                        title: "Panel contrast",
                        subtitle: "Increase separation from content behind Foundry"
                    )
                    Spacer()
                    Text("\(Int(state.themeIntensity * 100))%")
                        .font(FoundryTheme.body(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                }

                Slider(
                    value: Binding(
                        get: { state.themeIntensity },
                        set: { value in state.setThemeIntensity(value) }
                    ),
                    in: 0.2...1
                )
                .tint(FoundryTheme.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
    }

    private var aiContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsGroup {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        SettingsLabel(title: "Apple Intelligence", subtitle: "Used first when available")
                        Spacer()
                        Text("Primary")
                            .font(FoundryTheme.body(size: 12, weight: .medium))
                            .foregroundStyle(FoundryTheme.mutedText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    SettingsDivider()
                    SettingsToggleRow(
                        title: "Ollama fallback",
                        subtitle: "Use a local model when Apple AI is unavailable",
                        isOn: state.isOllamaEnabled,
                        set: state.setOllamaEnabled
                    )
                }
            }

            if state.isOllamaEnabled {
                SettingsGroup {
                    SettingsTextFieldRow(
                        title: "Host",
                        placeholder: "http://127.0.0.1:11434",
                        value: state.ollamaHost,
                        error: state.ollamaHostError,
                        commit: state.setOllamaHost
                    )
                    SettingsDivider()
                    SettingsTextFieldRow(
                        title: "Model",
                        placeholder: "llama3.1",
                        value: state.ollamaModel,
                        error: state.ollamaModelError,
                        commit: state.setOllamaModel
                    )
                }
            }
        }
    }

    private var widgetsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(title: "Home widgets", value: "\(state.widgetBoard.config.enabled.count)/\(WidgetBoardConfig.maxEnabled)")
            SettingsGroup {
                if state.widgetBoard.config.enabled.isEmpty {
                    Text("No widgets yet. Add one below.")
                        .font(FoundryTheme.body(size: 13, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .padding(.vertical, 5)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(state.widgetBoard.config.enabled.enumerated()), id: \.element) { index, kind in
                            ActiveWidgetRow(
                                kind: kind,
                                isFirst: index == 0,
                                isLast: index == state.widgetBoard.config.enabled.count - 1,
                                moveUp: { state.widgetBoard.moveUp(kind) },
                                moveDown: { state.widgetBoard.moveDown(kind) },
                                remove: { state.widgetBoard.remove(kind) }
                            )
                            if index < state.widgetBoard.config.enabled.count - 1 {
                                SettingsDivider()
                            }
                        }
                    }
                }
            }

            if state.widgetBoard.config.enabled.contains(.weather) || state.widgetBoard.config.enabled.contains(.stock) {
                SettingsSectionLabel(title: "Widget options")
                SettingsGroup {
                    if state.widgetBoard.config.enabled.contains(.weather) {
                        ConfigFieldRow(
                            title: "Weather city",
                            placeholder: "City name",
                            initialValue: state.widgetBoard.config.weatherCity,
                            commit: state.widgetBoard.setWeatherCity
                        )
                        if state.widgetBoard.config.enabled.contains(.stock) {
                            SettingsDivider()
                        }
                    }
                    if state.widgetBoard.config.enabled.contains(.stock) {
                        ConfigFieldRow(
                            title: "Stock ticker",
                            placeholder: "e.g. AAPL",
                            initialValue: state.widgetBoard.config.stockSymbol,
                            commit: state.widgetBoard.setStockSymbol
                        )
                    }
                }
            }

            SettingsSectionLabel(title: "Available widgets")
            if state.widgetBoard.isFull {
                Text("Remove a widget to add another.")
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 5)
            } else if state.widgetBoard.config.available.isEmpty {
                Text("All available widgets are on Home.")
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 5)
            } else {
                SettingsGroup {
                    ForEach(state.widgetBoard.config.available) { kind in
                        AvailableWidgetRow(kind: kind, add: { state.widgetBoard.add(kind) })
                    }
                }
            }
        }
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case appearance
    case ai
    case widgets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .ai: "AI"
        case .widgets: "Widgets"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "circle.lefthalf.filled"
        case .ai: "sparkles"
        case .widgets: "rectangle.3.group"
        }
    }

}

private struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(.horizontal, 2)
            .background(Color.white.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(0.045), lineWidth: 1)
            )
    }
}

private struct SettingsSectionLabel: View {
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

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
            .padding(.horizontal, 12)
    }
}

private struct SettingsLabel: View {
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

private struct SettingsToggleRow: View {
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

private struct SettingsNotice: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(FoundryTheme.body(size: 12, weight: .medium))
            .foregroundStyle(FoundryTheme.error)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(FoundryTheme.error.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct SettingsTextFieldRow: View {
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

private struct ShortcutRecorder: NSViewRepresentable {
    let hotkey: FoundryHotkey
    let onChange: (FoundryHotkey) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.onHotkey = context.coordinator.record
        view.hotkey = hotkey
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.hotkey = hotkey
        view.onHotkey = context.coordinator.record
    }

    final class Coordinator {
        let onChange: (FoundryHotkey) -> Void

        init(onChange: @escaping (FoundryHotkey) -> Void) { self.onChange = onChange }

        func record(_ hotkey: FoundryHotkey) { onChange(hotkey) }
    }
}

private final class ShortcutRecorderView: NSView {
    var hotkey = FoundryHotkey.commandSpace { didSet { needsDisplay = true } }
    var onHotkey: ((FoundryHotkey) -> Void)?
    private var isRecording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let background = isRecording ? NSColor.white.withAlphaComponent(0.14) : NSColor.white.withAlphaComponent(0.08)
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()

        let text = isRecording ? "Press shortcut…" : hotkey.displayName
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(isRecording ? 0.7 : 0.95)
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

private struct ActiveWidgetRow: View {
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

private struct AvailableWidgetRow: View {
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

private struct SettingsIconButton: View {
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
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
        .pointerCursor()
    }
}

private struct ConfigFieldRow: View {
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
