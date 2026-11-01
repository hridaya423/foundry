import AppKit
import SwiftUI

struct PermissionsSettingsPane: View {
    @State private var permissions = PermissionHealthState()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Foundry works without any of these. Each one unlocks specific features, and macOS asks only when you use them.")
                .font(FoundryTheme.bodySecondary)
                .foregroundStyle(FoundryTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            SettingsGroup {
                ForEach(PermissionKind.allCases) { kind in
                    let status = permissions.status(for: kind)
                    HStack(spacing: 10) {
                        Image(systemName: kind.symbol)
                            .font(FoundryTheme.Glyph.sm)
                            .foregroundStyle(FoundryTheme.textSecondary)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        SettingsLabel(title: LocalizedStringResource(stringLiteral: kind.title),
                            subtitle: LocalizedStringResource(stringLiteral: kind.purpose))
                        Spacer()
                        Text(status.label)
                            .font(FoundryTheme.bodySecondary)
                            .foregroundStyle(status == .granted ? FoundryTheme.success : FoundryTheme.textTertiary)
                        if status == .notGranted {
                            Button("Grant…") { permissions.request(kind) }
                                .controlSize(.small)
                        } else {
                            Button("Open Settings") { NSWorkspace.shared.open(kind.settingsURL) }
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                    if kind != PermissionKind.allCases.last { SettingsDivider() }
                }
            }
        }
        .onAppear(perform: permissions.startPolling)
        .onDisappear(perform: permissions.stopPolling)
    }
}
