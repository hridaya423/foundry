import SwiftUI

struct FallbackSettingsPane: View {
    var settings: SettingsStore

    var body: some View {
        let order = settings.fallbacks.order
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(title: "When nothing matches")
            SettingsGroup {
                ForEach(Array(order.enumerated()), id: \.element) { index, kind in
                    HStack(spacing: 2) {
                        Toggle(kind.title, isOn: Binding(
                            get: { settings.fallbacks.disabled.contains(kind) == false },
                            set: { on in settings.updateFallbacks { if on { $0.disabled.remove(kind) } else { $0.disabled.insert(kind) } } }
                        ))
                        .toggleStyle(FoundryCheckboxStyle())
                        Spacer()
                        SettingsIconButton(symbol: "chevron.up", label: "Move \(kind.title) up") {
                            settings.updateFallbacks { $0.move(kind, by: -1) }
                        }
                        .disabled(index == 0)
                        SettingsIconButton(symbol: "chevron.down", label: "Move \(kind.title) down") {
                            settings.updateFallbacks { $0.move(kind, by: 1) }
                        }
                        .disabled(index == order.count - 1)
                    }
                    .font(FoundryTheme.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    if index < order.count - 1 { SettingsDivider() }
                }
            }
        }
    }
}
