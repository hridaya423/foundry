import AppKit
import Foundation
import FoundryDomain
import FoundryServices
import os

final class AppSearchProvider: CommandProvider, Sendable {
    let id = "foundry.apps"

    private let appCache: InstalledAppCache

    init(diagnostics: DiagnosticsService, roots: [URL]? = nil, extraApps: [URL]? = nil, index: (any AppIndexing)? = nil) {
        let useLiveIndex = roots == nil && index == nil
        self.appCache = InstalledAppCache(roots: roots ?? Self.appSearchRoots(), extraApps: extraApps ?? (roots == nil ? Self.coreServicesApps : []),
            index: index ?? (useLiveIndex ? LiveAppIndex() : nil), diagnostics: diagnostics)
    }

    static let coreServicesApps: [URL] = [
        "Finder", "Applications/Keychain Access", "Applications/Archive Utility", "Applications/Directory Utility",
        "Applications/Feedback Assistant", "Applications/Ticket Viewer", "Applications/Wireless Diagnostics"
    ].map { URL(fileURLWithPath: "/System/Library/CoreServices/\($0).app") }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        let normalizedQuery = SearchScoring.PreparedQuery(query: request.query)
        guard normalizedQuery.normalized.isEmpty == false else { return [] }

        let running = runningBundleIDs()
        let apps = await appCache.current()
        return await Self.scan(apps: apps, query: normalizedQuery, request: request, running: running)
    }

    /// Scores the catalog against the prepared query. Large catalogs are split
    /// into fixed chunks scored on cooperative-pool threads in parallel and
    /// reassembled in catalog order, so results stay deterministic.
    private static func scan(
        apps: [InstalledApp],
        query normalizedQuery: SearchScoring.PreparedQuery,
        request: CommandSearchRequest,
        running: Set<String>
    ) async -> [CommandResult] {
        func match(_ app: InstalledApp) -> CommandResult? {
            let resultID = "app.\(app.identity)"
            let aliases = request.customAliases[resultID] ?? []
            var searchableMask = app.searchableMask
            for alias in aliases {
                searchableMask |= SearchScoring.characterMask(SearchScoring.normalize(alias))
            }
            guard SearchScoring.probableMatch(query: normalizedQuery, searchableMask: searchableMask, sensitivity: request.sensitivity),
                  SearchScoring.matchPrepared(
                      query: normalizedQuery,
                      normalizedTitle: app.normalizedName,
                      normalizedSubtitle: nil,
                      normalizedKeywords: app.normalizedSearchCandidates,
                      normalizedAliases: aliases.map(SearchScoring.normalize),
                      sensitivity: request.sensitivity
                  ) != nil else { return nil }
            return result(for: app, isRunning: running.contains(app.bundleIdentifier), searchAliases: aliases,
                searchKeywords: app.normalizedSearchCandidates)
        }

        guard apps.count >= 96 else {
            return apps.compactMap { app in Task.isCancelled ? nil : match(app) }
        }

        let chunkCount = min(4, (apps.count + 63) / 64)
        let chunkSize = (apps.count + chunkCount - 1) / chunkCount
        let chunks = await withTaskGroup(of: (index: Int, results: [CommandResult]).self) { group in
            for chunkIndex in 0..<chunkCount {
                let slice = apps[(chunkIndex * chunkSize)..<min(apps.count, (chunkIndex + 1) * chunkSize)]
                group.addTask { (chunkIndex, slice.compactMap(match)) }
            }
            var chunks: [(index: Int, results: [CommandResult])] = []
            for await chunk in group { chunks.append(chunk) }
            return chunks.sorted { $0.index < $1.index }
        }
        return chunks.flatMap(\.results)
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
        var actions: [CommandAction] = []
        if isRunning, bundleID.isEmpty == false {
            actions += [
                CommandAction(id: "app.\(identity).quit", title: "Quit", behavior: QuitApplicationAction(bundleID: bundleID, name: name)),
                CommandAction(id: "app.\(identity).hide", title: "Hide", behavior: HideApplicationAction(bundleID: bundleID, name: name)),
                CommandAction(id: "app.\(identity).force-quit", title: "Force Quit", behavior: ForceQuitApplicationAction(bundleID: bundleID, name: name))
            ]
        }
        actions += [
            CommandAction(id: "app.\(identity).reveal", title: "Show in Finder", behavior: RevealFileAction(path: path)),
            CommandAction(id: "app.\(identity).copy-path", title: "Copy Path", behavior: CopyToClipboardAction(path))
        ]
        if bundleID.isEmpty == false {
            actions.append(CommandAction(id: "app.\(identity).copy-bundle-id", title: "Copy Bundle ID", behavior: CopyToClipboardAction(bundleID)))
        }
        return actions
    }

    private static func result(for app: InstalledApp, isRunning: Bool, searchAliases: [String]? = nil, searchKeywords: [String]? = nil) -> CommandResult {
        let path = app.path.path
        return CommandResult(
            id: "app.\(app.identity)",
            title: app.name,
            subtitle: nil,
            icon: CommandIcon(fallback: app.fallbackIcon, filePath: path),
            searchAliases: (searchAliases ?? []) + app.normalizedSearchCandidates,
            searchKeywords: searchKeywords ?? [],
            payload: .app(identity: app.identity),
            primaryAction: CommandAction(id: "app.\(app.identity).open", title: "Open", behavior: OpenAppAction(path: path, name: app.name)),
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

private final class InstalledAppCache: Sendable {
    private struct State {
        var apps: [InstalledApp] = []
        var rootSignature: [AppRootSignature] = []
        var hasLoaded = false
        var refreshTask: Task<[InstalledApp], Never>?
        var nextRefresh = Date.distantPast
        /// Live index pushed changes — the next read reloads synchronously.
        var invalidated = false
    }

    private let roots: [URL]
    private let extraApps: [URL]
    private let index: (any AppIndexing)?
    private let diagnostics: DiagnosticsService
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let refreshInterval: TimeInterval = 30

    init(roots: [URL], extraApps: [URL], index: (any AppIndexing)?, diagnostics: DiagnosticsService) {
        self.roots = roots
        self.extraApps = extraApps
        self.index = index
        self.diagnostics = diagnostics
        index?.onUpdate = { [state] in
            state.withLock {
                $0.nextRefresh = .distantPast
                $0.invalidated = true
            }
        }
    }

    func current() async -> [InstalledApp] {
        index?.start()
        let signature = rootSignatures()
        let now = Date()

        let (cached, stale): ([InstalledApp]?, Bool) = state.withLock { state in
            guard state.hasLoaded, signature == state.rootSignature else { return (nil, false) }
            return (state.apps, now >= state.nextRefresh || state.invalidated)
        }
        if let cached {
            if stale {
                let task = loadTask()
                // Index-driven invalidation awaits the reload; the periodic
                // rescan stays stale-while-revalidate to keep search snappy.
                if state.withLock({ $0.invalidated }) {
                    return await finishRefresh(task.value)
                }
                Task { [weak self] in
                    self?.finishRefresh(await task.value)
                }
            }
            return cached
        }

        return await finishRefresh(loadTask().value)
    }

    private func loadTask() -> Task<[InstalledApp], Never> {
        state.withLock { state in
            if let refreshTask = state.refreshTask {
                return refreshTask
            }
            let extraApps = self.extraApps + (self.index?.urls ?? [])
            let task = Task.detached(priority: .utility) {
                AppSearchProvider.loadApps(roots: self.roots, extraApps: extraApps, diagnostics: self.diagnostics)
            }
            state.refreshTask = task
            return task
        }
    }

    @discardableResult
    private func finishRefresh(_ discovered: [InstalledApp]) -> [InstalledApp] {
        state.withLock { state in
            if discovered.isEmpty == false || state.apps.isEmpty {
                state.apps = discovered
            }
            state.rootSignature = rootSignatures()
            state.hasLoaded = true
            state.invalidated = false
            state.nextRefresh = Date().addingTimeInterval(refreshInterval)
            state.refreshTask = nil
            return state.apps
        }
    }

    private func rootSignatures() -> [AppRootSignature] {
        roots.map { root in
            let attributes = FileManager.default.attributesIfPresent(atPath: root.path)
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
    let searchableMask: UInt64

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
        self.searchableMask = self.normalizedSearchCandidates.reduce(0) { $0 | SearchScoring.characterMask($1) }
    }
}
