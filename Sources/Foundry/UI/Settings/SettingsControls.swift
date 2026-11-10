import SwiftUI

struct FoundrySwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: { EmptyView() }
            .buttonStyle(Track(isOn: configuration.isOn))
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch) }
    }

    private struct Track: ButtonStyle {
        let isOn: Bool
        @Environment(\.controlSize) private var controlSize
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            let height: CGFloat = controlSize == .regular ? 20 : 16
            let knob = height - 4
            let stretch: CGFloat = configuration.isPressed ? 3 : 0
            Capsule()
                .fill(isOn ? FoundryTheme.textPrimary : FoundryTheme.fillEmphasis)
                .frame(width: knob * 2 + 4, height: height)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? FoundryTheme.onPrimary : FoundryTheme.knobOff)
                        .frame(width: knob + stretch, height: knob)
                        .shadow(color: FoundryTheme.shadow, radius: 1, y: 0.5)
                        .padding(2)
                }
                .opacity(isEnabled ? 1 : FoundryTheme.Alpha.half)
                .contentShape(Capsule())
                .animation(reduceMotion ? nil : FoundryTheme.Motion.release, value: isOn)
                .animation(reduceMotion ? nil : FoundryTheme.Motion.press, value: configuration.isPressed)
        }
    }
}

struct FoundryCheckboxStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: FoundryTheme.Spacing.xs) {
                RoundedRectangle(cornerRadius: FoundryTheme.Radius.badge, style: .continuous)
                    .fill(configuration.isOn ? FoundryTheme.textPrimary : FoundryTheme.fillEmphasis)
                    .frame(width: 16, height: 16)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(FoundryTheme.Glyph.xs)
                            .foregroundStyle(FoundryTheme.onPrimary)
                            .opacity(configuration.isOn ? 1 : 0)
                    }
                configuration.label
            }
            .opacity(isEnabled ? 1 : FoundryTheme.Alpha.half)
            .contentShape(Rectangle())
        }
        .buttonStyle(FoundryQuietButtonStyle())
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.checkbox) }
    }
}

struct SettingsButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, isProminent: isProminent)
    }

    private struct Surface: View {
        let configuration: Configuration
        let isProminent: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var ink: Color {
            if isProminent { return FoundryTheme.onPrimary }
            return configuration.role == .destructive ? FoundryTheme.destructive : FoundryTheme.textPrimary
        }

        private var fill: Color {
            if isProminent { return FoundryTheme.textPrimary }
            return hovering ? FoundryTheme.fillEmphasis : FoundryTheme.fillTint
        }

        var body: some View {
            configuration.label
                .font(FoundryTheme.body)
                .foregroundStyle(ink)
                .lineLimit(1)
                .padding(.horizontal, FoundryTheme.Spacing.sm)
                .frame(height: FoundryTheme.Control.compact)
                .background(fill, in: RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
                .opacity(isEnabled ? (configuration.isPressed ? FoundryTheme.Alpha.pressed : 1) : FoundryTheme.Alpha.half)
                .scaleEffect(configuration.isPressed ? FoundryTheme.Motion.pressScale : 1)
                .animation(reduceMotion ? nil : (configuration.isPressed ? FoundryTheme.Motion.press : FoundryTheme.Motion.release),
                    value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}

struct SettingsMenuPicker<Value: Hashable>: View {
    let title: LocalizedStringKey
    let options: [(value: Value, label: String)]
    let selection: Value
    let select: (Value) -> Void
    @State private var hovering = false

    private var current: String {
        options.first { $0.value == selection }?.label ?? ""
    }

    var body: some View {
        Menu {
            Picker(title, selection: Binding(get: { selection }, set: { select($0) })) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: FoundryTheme.Spacing.xs) {
                Text(current)
                    .font(FoundryTheme.body)
                    .foregroundStyle(FoundryTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(FoundryTheme.Glyph.xs)
                    .foregroundStyle(FoundryTheme.textTertiary)
            }
            .padding(.horizontal, FoundryTheme.Spacing.sm)
            .frame(width: FoundryTheme.Control.settingsColumn, height: FoundryTheme.Control.compact)
            .background(hovering ? FoundryTheme.fillEmphasis : FoundryTheme.fillTint,
                in: RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(current))
    }
}
