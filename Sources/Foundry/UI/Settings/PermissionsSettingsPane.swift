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
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: FoundryTheme.Spacing.xs) {
                                Text(kind.title)
                                    .font(FoundryTheme.body)
                                    .foregroundStyle(FoundryTheme.textPrimary)
                                Text(status.label)
                                    .font(FoundryTheme.bodySecondary)
                                    .foregroundStyle(status == .granted ? FoundryTheme.success : FoundryTheme.textTertiary)
                            }
                            Text(kind.purpose)
                                .font(FoundryTheme.bodySecondary)
                                .foregroundStyle(FoundryTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if status == .notGranted {
                            Button("Grant…") { permissions.request(kind) }
                        } else {
                            Button("Open Settings") { NSWorkspace.shared.open(kind.settingsURL) }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                    if kind != PermissionKind.allCases.last { SettingsDivider() }
                }
            }
        }
        .onAppear(perform: permissions.startPolling)
        .onDisappear(perform: permissions.stopPolling)
    }
}
