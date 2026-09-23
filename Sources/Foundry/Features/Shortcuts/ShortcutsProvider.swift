import Foundation
import FoundryDomain
import FoundryServices

final class ShortcutsProvider: CommandProvider, @unchecked Sendable {
    let id = "foundry.shortcuts"
    static let cliPath = "/usr/bin/shortcuts"

    private let listShortcuts: @Sendable () -> [String]?
    private let refreshInterval: TimeInterval
    private let lock = NSLock()
    private var names: [String] = []
    private var refreshedAt: Date?
    private var refreshing = false

    init(refreshInterval: TimeInterval = 60, listShortcuts: @escaping @Sendable () -> [String]? = ShortcutsProvider.listWithCLI) {
        self.refreshInterval = refreshInterval
        self.listShortcuts = listShortcuts
    }

    static func listWithCLI() -> [String]? {
        guard FileManager.default.isExecutableFile(atPath: cliPath),
              let result = ProcessRunner.runSynchronously(path: cliPath, arguments: ["list"], timeout: 5),
              result.succeeded else { return nil }
        return parse(result.stdout)
    }

    static func parse(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.isEmpty == false }
    }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        let query = request.query.trimmingCharacters(in: .whitespaces)
        guard query.isEmpty == false else { return [] }
        return cachedNames().compactMap { name in
            let id = "shortcut.\(name)"
            let aliases = request.customAliases[id] ?? []
            guard SearchScoring.match(query: query, title: name, subtitle: nil, keywords: ["shortcut"], aliases: aliases, sensitivity: request.sensitivity) != nil else { return nil }
            return CommandResult(
                id: id,
                title: name,
                subtitle: "Shortcut",
                icon: CommandIcon(fallback: "SC", systemName: "square.2.layers.3d"),
                searchAliases: aliases,
                searchKeywords: ["shortcut"],
                primaryAction: CommandAction(id: "\(id).run", title: "Run Shortcut", kind: .runProcess(path: Self.cliPath, arguments: ["run", name])),
                secondaryActions: [CommandAction(id: "\(id).edit", title: "Edit in Shortcuts", kind: .openURL("shortcuts://open-shortcut?name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)"))]
            )
        }
    }

    func cachedNames(now: Date = Date()) -> [String] {
        let (current, needsRefresh) = lock.withLock { () -> ([String], Bool) in
            let stale = refreshedAt.map { now.timeIntervalSince($0) >= refreshInterval } ?? true
            guard stale, refreshing == false else { return (names, false) }
            refreshing = true
            return (names, true)
        }
        if needsRefresh {
            Task.detached(priority: .utility) { [weak self] in self?.refresh() }
        }
        return current
    }

    func refresh() {
        let listed = listShortcuts()
        lock.withLock {
            if let listed { names = listed }
            refreshedAt = Date()
            refreshing = false
        }
    }
}
