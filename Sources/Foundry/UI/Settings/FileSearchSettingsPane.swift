import AppKit
import SwiftUI

struct FileSearchSettingsPane: View {
    var settings: SettingsStore
    @State private var confirmingRestore = false

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
                        SettingsIconButton(symbol: "minus",
                            label: config.folders.count == 1 ? "Keep at least one folder" : "Stop searching \(folder)") {
                            settings.updateFileSearch { $0.folders.removeAll { $0 == folder } }
                        }
                        .disabled(config.folders.count == 1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    if folder != config.folders.last { SettingsDivider() }
                }
            }
            HStack(spacing: 8) {
                Button("Add Folder…", action: addFolder)
                Button("Restore Defaults…") { confirmingRestore = true }
                    .disabled(config == .default)
            }
            .confirmationDialog("Replace your search folders with the defaults?", isPresented: $confirmingRestore) {
                Button("Replace", role: .destructive) { settings.updateFileSearch { $0 = .default } }
            } message: {
                Text("Folders and skipped names you added are removed. This can't be undone.")
            }

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
