import AppKit
import Foundation

final class AppSearchProvider: CommandProvider {
    let id = "foundry.apps"

    private let diagnostics: DiagnosticsService
    private lazy var apps: [InstalledApp] = loadApps()

    init(diagnostics: DiagnosticsService) {
        self.diagnostics = diagnostics
    }

    func results(matching query: String) -> [CommandResult] {
        apps.compactMap { app in
            guard let score = SearchScoring.score(
                query: query,
                title: app.name,
                aliases: [app.bundleIdentifier, app.path.lastPathComponent.replacingOccurrences(of: ".app", with: "")]
            ) else { return nil }

            return CommandResult(
                id: "app.\(app.identity)",
                title: app.name,
                subtitle: nil,
                icon: CommandIcon(fallback: app.fallbackIcon, filePath: app.path.path),
                score: score,
                primaryAction: CommandAction(id: "app.\(app.identity).open", title: "Open") { [diagnostics] in
                    DispatchQueue.main.async {
                        let configuration = NSWorkspace.OpenConfiguration()
                        NSWorkspace.shared.openApplication(at: app.path, configuration: configuration) { _, error in
                            if let error {
                                diagnostics.log("Failed to launch \(app.name): \(error.localizedDescription)")
                            } else {
                                diagnostics.log("Launched app: \(app.name)")
                            }
                        }
                    }
                },
                secondaryActions: []
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
            return lhs.score > rhs.score
        }
    }

    private func loadApps() -> [InstalledApp] {
        let span = diagnostics.startSpan("apps.load")
        defer { diagnostics.endSpan(span) }

        let roots = appSearchRoots()
        var seen = Set<String>()
        var discovered: [InstalledApp] = []

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                enumerator.skipDescendants()

                guard let app = InstalledApp(url: url) else { continue }
                guard seen.insert(app.identity).inserted else { continue }
                discovered.append(app)
            }
        }

        diagnostics.log("Loaded \(discovered.count) installed apps")
        return discovered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func appSearchRoots() -> [URL] {
        var roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities")
        ]

        roots.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"))
        return roots
    }
}

private struct InstalledApp {
    let name: String
    let bundleIdentifier: String
    let path: URL

    var identity: String {
        if bundleIdentifier.isEmpty == false { return bundleIdentifier }
        return path.path.replacingOccurrences(of: "/", with: ".")
    }

    var fallbackIcon: String {
        let words = name.split(separator: " ")
        let initials = words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return initials.isEmpty ? "AP" : initials
    }

    init?(url: URL) {
        guard let bundle = Bundle(url: url) else { return nil }

        let info = bundle.infoDictionary ?? [:]
        let displayName = info["CFBundleDisplayName"] as? String
        let bundleName = info["CFBundleName"] as? String
        let fileName = url.deletingPathExtension().lastPathComponent
        let resolvedName = displayName ?? bundleName ?? fileName

        self.name = resolvedName
        self.bundleIdentifier = bundle.bundleIdentifier ?? ""
        self.path = url
    }
}
