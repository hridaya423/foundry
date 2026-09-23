import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct QuicklinksSettingsPane: View {
    var store: QuicklinkStore = .shared
    @State private var links: [Quicklink] = []
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Type a keyword and your query, for example “g swift concurrency”. Use {argument}, {clipboard}, {date} or {time} in the link.")
                .font(FoundryTheme.body(size: 12, weight: .regular))
                .foregroundStyle(FoundryTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            SettingsGroup {
                if links.isEmpty {
                    Text("No quicklinks yet.")
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .padding(12)
                }
                ForEach($links) { $link in
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            TextField("Name", text: $link.name)
                                .frame(width: 150)
                            TextField("Keyword", text: $link.keyword)
                                .frame(width: 70)
                            TextField("https://example.com/search?q={argument}", text: $link.link)
                            Button {
                                links.removeAll { $0.id == link.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete \(link.name)")
                        }
                        .textFieldStyle(.roundedBorder)

                        HStack(spacing: 10) {
                            Toggle("Site icon", isOn: Binding(
                                get: { link.useFavicon != false },
                                set: { link.useFavicon = $0 ? nil : false }
                            ))
                            .toggleStyle(.checkbox)
                            Spacer()
                            Text("Open with")
                                .foregroundStyle(FoundryTheme.mutedText)
                            Button(Self.appName(for: link.openWithBundleID) ?? "Default", action: { pickApp(for: link.id) })
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Choose app for \(link.name)")
                            if link.openWithBundleID != nil {
                                Button { link.openWithBundleID = nil } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Use default app for \(link.name)")
                            }
                        }
                        .font(FoundryTheme.body(size: 11, weight: .regular))
                    }
                    .controlSize(.small)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    if link.id != links.last?.id { SettingsDivider() }
                }
            }

            HStack {
                Button("Add Quicklink") { links.append(Quicklink(name: "", link: "")) }
                Button("Import from Raycast…", action: importRaycast)
                Spacer()
                Button("Restore Defaults") { links = QuicklinkTemplate.defaults }
            }
            .controlSize(.small)

            if let error {
                SettingsNotice(text: error, symbol: "exclamationmark.triangle")
            }
        }
        .onAppear { links = store.load() }
        .onChange(of: links) { _, updated in save(updated) }
    }

    private func save(_ updated: [Quicklink]) {
        do {
            try store.save(updated.filter { $0.name.isEmpty == false || $0.link.isEmpty == false })
            error = nil
        } catch {
            self.error = "Quicklinks could not be saved: \(error.localizedDescription)"
        }
    }

    private func pickApp(for linkID: Quicklink.ID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier,
              let index = links.firstIndex(where: { $0.id == linkID }) else { return }
        links[index].openWithBundleID = bundleID
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
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try QuicklinkTemplate.importRaycast(Data(contentsOf: url))
            let existing = Set(links.map(\.link))
            links.append(contentsOf: imported.filter { existing.contains($0.link) == false })
        } catch {
            self.error = "That file isn’t a Raycast Quicklinks export."
        }
    }
}
