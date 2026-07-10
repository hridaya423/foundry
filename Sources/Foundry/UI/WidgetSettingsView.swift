import AppKit
import Carbon
import SwiftUI

struct WidgetSettingsView: View {
    @ObservedObject var state: CommandPanelState
    @State private var widgetsExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                generalSection
                keyboardSection
                appearanceSection
                widgetsSection
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.never)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: "General")

            ToggleRow(
                title: "Agent Shelf",
                subtitle: "Show recent agent sessions on the home screen",
                isOn: state.isAgentShelfVisible,
                set: state.setAgentShelfVisible
            )
        }
    }

    private var keyboardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: "Keyboard")

            HStack(spacing: 12) {
                WidgetGlyph(symbol: "command")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Global shortcut")
                        .font(FoundryTheme.body(size: 14, weight: .medium))
                        .foregroundStyle(FoundryTheme.primaryText)
                    Text("Open Foundry from anywhere")
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                }

                Spacer()

                ShortcutRecorder(hotkey: state.hotkey, onChange: state.setHotkey)
                    .frame(width: 150, height: 34)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 58)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: "Appearance")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Backdrop intensity")
                        .font(FoundryTheme.body(size: 14, weight: .medium))
                        .foregroundStyle(FoundryTheme.primaryText)
                    Spacer()
                    Text("\(Int(state.themeIntensity * 100))%")
                        .font(FoundryTheme.body(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.mutedText)
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
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var widgetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.14)) { widgetsExpanded.toggle() }
            } label: {
                HStack {
                    SettingsSectionHeader(title: "Widgets")
                    Spacer()
                    Image(systemName: widgetsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.mutedText)
                }
            }
            .buttonStyle(.plain)

            if widgetsExpanded {
                activeSection
                configSection
                availableSection
            } else {
                Text("Choose what appears on the Home board")
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: "On the Board")

            if state.widgetBoard.config.enabled.isEmpty {
                Text("No widgets yet. Add some below.")
                    .font(FoundryTheme.body(size: 13, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
            } else {
                Text("Showing up to \(WidgetBoardConfig.maxEnabled) widgets on Home.")
                    .font(FoundryTheme.body(size: 12, weight: .medium))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .padding(.horizontal, 4)

                ForEach(Array(state.widgetBoard.config.enabled.enumerated()), id: \.element) { index, kind in
                    ActiveWidgetRow(
                        kind: kind,
                        isFirst: index == 0,
                        isLast: index == state.widgetBoard.config.enabled.count - 1,
                        moveUp: { state.widgetBoard.moveUp(kind) },
                        moveDown: { state.widgetBoard.moveDown(kind) },
                        remove: { state.widgetBoard.remove(kind) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var configSection: some View {
        if state.widgetBoard.config.enabled.contains(.weather) || state.widgetBoard.config.enabled.contains(.stock) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionHeader(title: "Widget Options")

                if state.widgetBoard.config.enabled.contains(.weather) {
                    ConfigFieldRow(
                        symbol: "cloud.sun",
                        title: "Weather City",
                        placeholder: "City name",
                        initialValue: state.widgetBoard.config.weatherCity,
                        commit: { state.widgetBoard.setWeatherCity($0) }
                    )
                }

                if state.widgetBoard.config.enabled.contains(.stock) {
                    ConfigFieldRow(
                        symbol: "chart.line.uptrend.xyaxis",
                        title: "Stock Ticker",
                        placeholder: "e.g. AAPL",
                        initialValue: state.widgetBoard.config.stockSymbol,
                        commit: { state.widgetBoard.setStockSymbol($0) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var availableSection: some View {
        if state.widgetBoard.config.available.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionHeader(title: "Available")

                if state.widgetBoard.isFull {
                    Text("Remove a widget to add another.")
                        .font(FoundryTheme.body(size: 13, weight: .medium))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                } else {
                    ForEach(state.widgetBoard.config.available) { kind in
                        AvailableWidgetRow(kind: kind, add: { state.widgetBoard.add(kind) })
                    }
                }
            }
        }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let hotkey: FoundryHotkey
    let onChange: (FoundryHotkey) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

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

        init(onChange: @escaping (FoundryHotkey) -> Void) {
            self.onChange = onChange
        }

        func record(_ hotkey: FoundryHotkey) {
            onChange(hotkey)
        }
    }
}

private final class ShortcutRecorderView: NSView {
    var hotkey = FoundryHotkey.commandSpace {
        didSet { needsDisplay = true }
    }
    var onHotkey: ((FoundryHotkey) -> Void)?

    private var isRecording = false {
        didSet { needsDisplay = true }
    }

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

private struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(FoundryTheme.body(size: 11, weight: .semibold))
            .foregroundStyle(FoundryTheme.faintText)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 4)
    }
}

private struct ToggleRow: View {
    let title: String
    let subtitle: String
    let isOn: Bool
    let set: (Bool) -> Void

    var body: some View {
        Button {
            set(isOn == false)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(FoundryTheme.body(size: 14, weight: .medium))
                        .foregroundStyle(FoundryTheme.primaryText)
                    Text(subtitle)
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                }

                Spacer()

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isOn ? Color.green.opacity(0.9) : FoundryTheme.secondaryText)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}

private struct WidgetGlyph: View {
    let symbol: String

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .frame(width: 34, height: 34)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(FoundryTheme.secondaryText)
            )
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
        HStack(spacing: 12) {
            WidgetGlyph(symbol: kind.symbol)

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(FoundryTheme.body(size: 14, weight: .medium))
                    .foregroundStyle(FoundryTheme.primaryText)
                Text(kind.summary)
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                IconButton(symbol: "chevron.up", action: moveUp)
                    .disabled(isFirst)
                    .opacity(isFirst ? 0.3 : 1)
                IconButton(symbol: "chevron.down", action: moveDown)
                    .disabled(isLast)
                    .opacity(isLast ? 0.3 : 1)
                IconButton(symbol: "minus", action: remove, tint: Color.red.opacity(0.85))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.06 : 0.04))
        )
        .onHover { isHovering = $0 }
    }
}

private struct AvailableWidgetRow: View {
    let kind: WidgetKind
    let add: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: add) {
            HStack(spacing: 12) {
                WidgetGlyph(symbol: kind.symbol)

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(FoundryTheme.body(size: 14, weight: .medium))
                        .foregroundStyle(FoundryTheme.primaryText)
                    Text(kind.summary)
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.06 : 0.04))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

private struct IconButton: View {
    let symbol: String
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
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

private struct ConfigFieldRow: View {
    let symbol: String
    let title: String
    let placeholder: String
    let initialValue: String
    let commit: (String) -> Void

    @State private var text = ""

    var body: some View {
        HStack(spacing: 12) {
            WidgetGlyph(symbol: symbol)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FoundryTheme.body(size: 12, weight: .medium))
                    .foregroundStyle(FoundryTheme.faintText)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(FoundryTheme.body(size: 14, weight: .medium))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .onSubmit { commit(text) }
            }

            Spacer()

            Button(action: { commit(text) }) {
                Text("Save")
                    .font(FoundryTheme.body(size: 12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .onAppear { text = initialValue }
    }
}
