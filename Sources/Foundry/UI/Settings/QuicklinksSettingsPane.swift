import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct QuicklinksSettingsPane: View {
    var settings: SettingsStore
    var store: QuicklinkStore = .shared
    @State private var links: [Quicklink] = []
    @State private var error: String?
    @State private var confirmingRestore = false
    @State private var removed: (link: Quicklink, index: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("""
                Type a keyword and your query, for example “g swift concurrency”. \
                Use {argument}, {clipboard}, {selection}, {date} or {time} in the link. {selection} needs Accessibility access.
                """)
                .font(FoundryTheme.bodySecondary)
                .foregroundStyle(FoundryTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            SettingsGroup {
                SettingsToggleRow(title: "Site icons",
                    subtitle: "Show each site’s icon in Quicklinks and Media Downloads. Foundry gets the icon from the site.",
                    isOn: settings.quicklinkSiteIcons, set: settings.updateQuicklinkSiteIcons)
            }

            SettingsGroup {
                if links.isEmpty {
                    Text("No quicklinks yet.")
                        .font(FoundryTheme.bodySecondary)
                        .foregroundStyle(FoundryTheme.textTertiary)
                        .padding(12)
                }
                ForEach($links) { $link in
                    HStack(spacing: 8) {
                        field("Name", text: $link.name)
                            .frame(width: 130)
                        field("Keyword", text: $link.keyword)
                            .frame(width: 64)
                        field("https://example.com/search?q={argument}", text: $link.link)
                        if let app = Self.appName(for: link.openWithBundleID) {
                            Text("in \(app)")
                                .font(FoundryTheme.caption)
                                .foregroundStyle(FoundryTheme.textTertiary)
                                .lineLimit(1)
                        }
                        Toggle("", isOn: $link.isEnabled)
                            .labelsHidden()
                            .toggleStyle(FoundrySwitchStyle())
                            .controlSize(.small)
                            .accessibilityLabel("Enable \(link.name)")
                        Menu {
                            Toggle("Show Site Icon", isOn: Binding(
                                get: { link.useFavicon != false },
                                set: { link.useFavicon = $0 ? nil : false }
                            ))
                            .disabled(settings.quicklinkSiteIcons == false)
                            Button("Open With…") { pickApp(for: link.id) }
                            if link.openWithBundleID != nil {
                                Button("Open With the Default App") { link.openWithBundleID = nil }
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                guard let index = links.firstIndex(where: { $0.id == link.id }) else { return }
                                removed = (links.remove(at: index), index)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(FoundryTheme.Glyph.xs)
                                .foregroundStyle(FoundryTheme.textSecondary)
                                .frame(width: FoundryTheme.Control.mini, height: FoundryTheme.Control.mini)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityLabel("Options for \(link.name)")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .opacity(link.isEnabled ? 1 : FoundryTheme.Alpha.half)
                    if link.id != links.last?.id { SettingsDivider() }
                }
            }

            if let removed {
                InlineNotice(level: .info, text: "Removed \u{201C}\(removed.link.name.isEmpty ? removed.link.link : removed.link.name)\u{201D}",
                    actionTitle: "Undo") {
                    links.insert(removed.link, at: min(removed.index, links.count))
                    self.removed = nil
                }
            }

            HStack {
                Button("Add Quicklink") { links.append(Quicklink(name: "", link: "")) }
                Button("Import from Raycast…", action: importRaycast)
                Spacer()
                Button("Restore Defaults…") { confirmingRestore = true }
            }
            .confirmationDialog("Replace your \(links.count) quicklinks with the defaults?", isPresented: $confirmingRestore) {
                Button("Replace", role: .destructive) { links = QuicklinkTemplate.defaults }
            } message: {
                Text("Quicklinks you added are removed. This can't be undone.")
            }

            if let error {
                SettingsNotice(text: LocalizedStringResource(stringLiteral: error), symbol: "exclamationmark.triangle")
            }
        }
        .onAppear { links = store.load() }
        .onChange(of: links) { _, updated in save(updated) }
    }

    private func field(_ placeholder: LocalizedStringKey, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(FoundryTheme.bodySecondary)
            .foregroundStyle(FoundryTheme.textPrimary)
            .padding(.horizontal, 8)
            .frame(height: FoundryTheme.Control.compact)
            .background(FoundryTheme.fillHover, in: RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
    }

    private func save(_ updated: [Quicklink]) {
        do {
            try store.save(updated.filter { $0.name.isEmpty == false || $0.link.isEmpty == false })
            error = nil
        } catch {
            self.error = String(localized: "Quicklinks could not be saved: \(error.localizedDescription)")
        }
    }

    private func pickApp(for linkID: Quicklink.ID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        Task { @MainActor in
            guard await runFilePanelAsSheet(panel), let url = panel.url,
                  let bundleID = Bundle(url: url)?.bundleIdentifier,
                  let index = links.firstIndex(where: { $0.id == linkID }) else { return }
            links[index].openWithBundleID = bundleID
        }
    }

    static func appName(for bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else { return bundleID }
        return (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent
    }

    private func importRaycast() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        Task { @MainActor in
            await importRaycastPanel(panel)
        }
    }

    private func importRaycastPanel(_ panel: NSOpenPanel) async {
        guard await runFilePanelAsSheet(panel), let url = panel.url else { return }
        do {
            let imported = try QuicklinkTemplate.importRaycast(Data(contentsOf: url))
            let existing = Set(links.map(\.link))
            links.append(contentsOf: imported.filter { existing.contains($0.link) == false })
        } catch {
            self.error = String(localized: "That file isn’t a Raycast Quicklinks export.")
        }
    }
}
