import AppKit
import SwiftUI

struct ScriptsSettingsPane: View {
    var store: ScriptDirectoryStore = .shared
    @State private var directories: [String] = []
    @State private var trusted: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Foundry runs Raycast-compatible Script Commands: executable files with a “# @raycast.title” line. Scripts run as you, so a folder must be trusted before its first run.")
                .font(FoundryTheme.body(size: 12, weight: .regular))
                .foregroundStyle(FoundryTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            SettingsGroup {
                ForEach(directories, id: \.self) { directory in
                    HStack(spacing: 10) {
                        SettingsLabel(title: (directory as NSString).lastPathComponent, subtitle: "\(ScriptCommandProvider.scan(directory).count) scripts · \(directory)")
                        Spacer()
                        Toggle("Trusted", isOn: Binding(
                            get: { trusted.contains(directory) },
                            set: { store.setTrusted($0, for: directory); reload() }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        Button {
                            createIfNeeded(directory)
                            NSWorkspace.shared.open(URL(fileURLWithPath: directory))
                        } label: { Image(systemName: "folder") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Open \(directory)")
                        Button {
                            store.directories = directories.filter { $0 != directory }
                            reload()
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(directory)")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    if directory != directories.last { SettingsDivider() }
                }
            }

            Button("Add Folder…", action: addFolder)
                .controlSize(.small)
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        directories = store.directories
        trusted = Set(directories.filter(store.isTrusted))
    }

    private func createIfNeeded(_ directory: String) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url, directories.contains(url.path) == false else { return }
        store.directories = directories + [url.path]
        reload()
    }
}
