import AppKit
import Foundation
import FoundryDomain
import FoundryServices

final class AppSearchProvider: CommandProvider, @unchecked Sendable {
    let id = "foundry.apps"

    private let appCache: InstalledAppCache

    init(diagnostics: DiagnosticsService, roots: [URL]? = nil, extraApps: [URL]? = nil) {
        self.appCache = InstalledAppCache(roots: roots ?? Self.appSearchRoots(), extraApps: extraApps ?? (roots == nil ? Self.coreServicesApps : []), diagnostics: diagnostics)
    }

    static let coreServicesApps: [URL] = [
        "Finder", "Applications/Keychain Access", "Applications/Archive Utility", "Applications/Directory Utility",
        "Applications/Feedback Assistant", "Applications/Ticket Viewer", "Applications/Wireless Diagnostics"
    ].map { URL(fileURLWithPath: "/System/Library/CoreServices/\($0).app") }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        let normalizedQuery = SearchScoring.PreparedQuery(query: request.query)
        guard normalizedQuery.normalized.isEmpty == false else { return [] }

        let running = runningBundleIDs()
        return await appCache.current().compactMap { app -> CommandResult? in
            guard Task.isCancelled == false else { return nil }
            let resultID = "app.\(app.identity)"
            let aliases = request.customAliases[resultID] ?? []
            guard SearchScoring.matchPrepared(
                query: normalizedQuery,
                normalizedTitle: app.normalizedName,
                normalizedSubtitle: nil,
                normalizedKeywords: app.normalizedSearchCandidates,
                normalizedAliases: aliases.map(SearchScoring.normalize),
                sensitivity: request.sensitivity
            ) != nil else { return nil }

            return Self.result(for: app, isRunning: running.contains(app.bundleIdentifier), searchAliases: aliases, searchKeywords: app.normalizedSearchCandidates)
        }
    }

    private func runningBundleIDs() -> Set<String> {
        RunningAppsSnapshot.bundleIDs()
    }

    func defaultResults() async -> [CommandResult] {
        let running = runningBundleIDs()
        return await appCache.current().map { app in
            Self.result(for: app, isRunning: running.contains(app.bundleIdentifier), searchAliases: [], searchKeywords: app.normalizedSearchCandidates)
        }
    }

    static func actions(identity: String, name: String, path: String, bundleID: String, isRunning: Bool) -> [CommandAction] {
        guard isRunning, bundleID.isEmpty == false else { return [] }
        return [
            CommandAction(id: "app.\(identity).quit", title: "Quit", kind: .quitApplication(bundleID: bundleID, name: name)),
            CommandAction(id: "app.\(identity).hide", title: "Hide", kind: .hideApplication(bundleID: bundleID, name: name)),
            CommandAction(id: "app.\(identity).force-quit", title: "Force Quit", kind: .forceQuitApplication(bundleID: bundleID, name: name))
        ]
    }

    private static func result(for app: InstalledApp, isRunning: Bool, searchAliases: [String]? = nil, searchKeywords: [String]? = nil) -> CommandResult {
        let path = app.path.path
        return CommandResult(
            id: "app.\(app.identity)",
            title: app.name,
            subtitle: nil,
            icon: CommandIcon(fallback: app.fallbackIcon, filePath: path),
            searchAliases: searchAliases ?? app.normalizedSearchCandidates,
            searchKeywords: searchKeywords ?? app.normalizedSearchCandidates,
            primaryAction: CommandAction(id: "app.\(app.identity).open", title: "Open", kind: .openApp(path: path, name: app.name)),
            secondaryActions: actions(identity: app.identity, name: app.name, path: path, bundleID: app.bundleIdentifier, isRunning: isRunning)
        )
    }

    fileprivate static func loadApps(roots: [URL], extraApps: [URL] = [], diagnostics: DiagnosticsService) -> [InstalledApp] {
        let span = diagnostics.startSpan("apps.load")
        defer { diagnostics.endSpan(span) }

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

        for url in extraApps {
            guard let app = InstalledApp(url: url), seen.insert(app.identity).inserted else { continue }
            discovered.append(app)
        }

        diagnostics.log("Loaded \(discovered.count) installed apps")
        return discovered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func appSearchRoots() -> [URL] {
        var roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications")
        ]

        roots.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"))
        return roots
    }
}

private final class InstalledAppCache: @unchecked Sendable {
    private let roots: [URL]
    private let extraApps: [URL]
    private let diagnostics: DiagnosticsService
    private let lock = NSLock()
    private var apps: [InstalledApp] = []
    private var rootSignature: [AppRootSignature] = []
    private var hasLoaded = false
    private var refreshTask: Task<[InstalledApp], Never>?
    private var nextRefresh = Date.distantPast
    private let refreshInterval: TimeInterval = 30

    init(roots: [URL], extraApps: [URL], diagnostics: DiagnosticsService) {
        self.roots = roots
        self.extraApps = extraApps
        self.diagnostics = diagnostics
    }

    func current() async -> [InstalledApp] {
        let signature = rootSignatures()
        let now = Date()

        let (cached, stale): ([InstalledApp]?, Bool) = withLock {
            guard hasLoaded, signature == rootSignature else { return (nil, false) }
            return (apps, now >= nextRefresh)
        }
        if let cached {
            if stale {
                let task = loadTask()
                Task { [weak self] in
                    self?.finishRefresh(await task.value)
                }
            }
            return cached
        }

        return await finishRefresh(loadTask().value)
    }

    private func loadTask() -> Task<[InstalledApp], Never> {
        withLock {
            if let refreshTask {
                return refreshTask
            }
            let task = Task.detached(priority: .utility) {
                AppSearchProvider.loadApps(roots: self.roots, extraApps: self.extraApps, diagnostics: self.diagnostics)
            }
            refreshTask = task
            return task
        }
    }

    @discardableResult
    private func finishRefresh(_ discovered: [InstalledApp]) -> [InstalledApp] {
        withLock {
            if discovered.isEmpty == false || apps.isEmpty {
                apps = discovered
            }
            rootSignature = rootSignatures()
            hasLoaded = true
            nextRefresh = Date().addingTimeInterval(refreshInterval)
            refreshTask = nil
            return apps
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func rootSignatures() -> [AppRootSignature] {
        roots.map { root in
            let attributes = try? FileManager.default.attributesOfItem(atPath: root.path)
            return AppRootSignature(modificationDate: attributes?[.modificationDate] as? Date)
        }
    }
}

private struct AppRootSignature: Equatable {
    let modificationDate: Date?
}

private struct InstalledApp: Sendable {
    let name: String
    let bundleIdentifier: String
    let path: URL
    let normalizedName: String
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
        self.normalizedName = SearchScoring.normalize(resolvedName)
        self.normalizedSearchCandidates = [
            resolvedName,
            bundle.bundleIdentifier ?? "",
            fileName
        ]
        .map(SearchScoring.normalize)
        .filter { $0.isEmpty == false }
    }
}
