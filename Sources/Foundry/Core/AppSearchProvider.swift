import AppKit
import Foundation

final class AppSearchProvider: CommandProvider, @unchecked Sendable {
    let id = "foundry.apps"

    private let diagnostics: DiagnosticsService
    private let apps: [InstalledApp]

    init(diagnostics: DiagnosticsService) {
        self.diagnostics = diagnostics
        self.apps = Self.loadApps(diagnostics: diagnostics)
    }

    func results(matching query: String) async -> [CommandResult] {
        let normalizedQuery = SearchScoring.normalize(query)
        guard normalizedQuery.isEmpty == false else { return [] }

        return apps.compactMap { app -> CommandResult? in
            guard Task.isCancelled == false else { return nil }
            guard let score = SearchScoring.score(normalizedQuery: normalizedQuery, candidates: app.normalizedSearchCandidates) else { return nil }

            return Self.result(for: app, score: score)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
            return lhs.score > rhs.score
        }
    }

    func defaultResults() async -> [CommandResult] {
        apps.map { app in Self.result(for: app, score: 10) }
    }

    private static func result(for app: InstalledApp, score: Double) -> CommandResult {
        let path = app.path.path
        return CommandResult(
            id: "app.\(app.identity)",
            title: app.name,
            subtitle: nil,
            icon: CommandIcon(fallback: app.fallbackIcon, filePath: path),
            score: score,
            primaryAction: CommandAction(id: "app.\(app.identity).open", title: "Open", kind: .openApp(path: path, name: app.name)),
            secondaryActions: [
                CommandAction(id: "app.\(app.identity).reveal", title: "Reveal in Finder", kind: .revealInFinder(path: path)),
                CommandAction(id: "app.\(app.identity).copy-path", title: "Copy Path", kind: .copyToClipboard(path))
            ]
        )
    }

    private static func loadApps(diagnostics: DiagnosticsService) -> [InstalledApp] {
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

    private static func appSearchRoots() -> [URL] {
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
    let normalizedSearchCandidates: [String]

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
        self.normalizedSearchCandidates = [
            resolvedName,
            bundle.bundleIdentifier ?? "",
            fileName
        ]
        .map(SearchScoring.normalize)
        .filter { $0.isEmpty == false }
    }
}
