import AppKit
import SwiftUI

struct FileSearchSettingsPane: View {
    var settings: SettingsStore

    var body: some View {
        let config = settings.fileSearch
        VStack(alignment: .leading, spacing: 12) {
            Text("Type f and a file name in Foundry to search these folders with Spotlight. Add kind:folder, kind:image, kind:pdf or kind:code to " +
                "narrow results. f on its own lists files you changed this week.")
                .font(FoundryTheme.bodySecondary)
                .foregroundStyle(FoundryTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            SettingsSectionLabel(title: "Search folders", value: "\(config.folders.count)")
            SettingsGroup {
                ForEach(config.folders, id: \.self) { folder in
                    HStack(spacing: 10) {
                        SettingsLabel(
                            title: LocalizedStringResource(stringLiteral: FileManager.default.displayName(atPath: (folder as NSString).expandingTildeInPath)),
                            subtitle: LocalizedStringResource(stringLiteral: folder))
                        Spacer()
                        Button {
                            settings.updateFileSearch { $0.folders.removeAll { $0 == folder } }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .disabled(config.folders.count == 1)
                        .help(config.folders.count == 1 ? "Keep at least one folder" : "Stop searching this folder")
                        .accessibilityLabel("Remove \(folder)")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    if folder != config.folders.last { SettingsDivider() }
                }
            }
            HStack(spacing: 8) {
                Button("Add Folder…", action: addFolder)
                Button("Restore Defaults") { settings.updateFileSearch { $0 = .default } }
                    .disabled(config == .default)
            }
            .controlSize(.small)

            SettingsSectionLabel(title: "Skipped folders")
            SettingsGroup {
                ConfigFieldRow(
                    title: "Folder names",
                    placeholder: LocalizedStringResource(stringLiteral: FileSearchConfig.defaultExcluded.joined(separator: ", ")),
                    initialValue: config.excludedFolders.joined(separator: ", "),
                    commit: { value in
                        settings.updateFileSearch {
                            $0.excludedFolders = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.isEmpty == false }
                        }
                    }
                )
                .id(config.excludedFolders)
            }
            Text("Hidden files and anything inside these folders never appear. If a folder is excluded from Spotlight in System Settings, " +
                "Foundry can't search it either.")
                .font(FoundryTheme.bodySecondary)
                .foregroundStyle(FoundryTheme.textQuaternary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        Task { @MainActor in
            guard await runFilePanelAsSheet(panel) else { return }
            let added = panel.urls.map { ($0.path as NSString).abbreviatingWithTildeInPath }
            settings.updateFileSearch { config in config.folders += added.filter { config.folders.contains($0) == false } }
        }
    }
}
