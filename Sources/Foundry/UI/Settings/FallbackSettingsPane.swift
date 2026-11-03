import SwiftUI

struct FallbackSettingsPane: View {
    var settings: SettingsStore

    var body: some View {
        let order = settings.fallbacks.order
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(title: "When nothing matches")
            SettingsGroup {
                ForEach(Array(order.enumerated()), id: \.element) { index, kind in
                    HStack(spacing: 8) {
                        Toggle(kind.title, isOn: Binding(
                            get: { settings.fallbacks.disabled.contains(kind) == false },
                            set: { on in settings.updateFallbacks { if on { $0.disabled.remove(kind) } else { $0.disabled.insert(kind) } } }
                        ))
                        .toggleStyle(.checkbox)
                        Spacer()
                        Button { settings.updateFallbacks { $0.move(kind, by: -1) } } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            .accessibilityLabel("Move \(kind.title) up")
                        Button { settings.updateFallbacks { $0.move(kind, by: 1) } } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless)
                            .disabled(index == order.count - 1)
                            .accessibilityLabel("Move \(kind.title) down")
                    }
                    .font(FoundryTheme.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    if index < order.count - 1 { SettingsDivider() }
                }
            }
        }
    }
}
