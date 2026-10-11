import AppKit
import Foundation
import FoundryDomain
import FoundryServices
import os

final class FileSearchProvider: CommandProvider, Sendable {
    let id = "foundry.files"
    var searchPolicy: CommandProviderSearchPolicy { CommandProviderSearchPolicy(tier: .deferred) }
    var searchTimeout: Duration? { .milliseconds(3_500) }

    static let prefix = "f "
    static let resultLimit = 12
    static let streamLimit = 200
    static let ignoredComponents: Set<String> = ["Library", "node_modules", ".git", ".Trash", "DerivedData", ".build"]
    static let commandID = "foundry.files.search"

    static let kindPredicates: [String: String] = [
        "pdf": "kMDItemContentType == 'com.adobe.pdf'",
        "image": "kMDItemContentTypeTree == 'public.image'",
        "photo": "kMDItemContentTypeTree == 'public.image'",
        "folder": "kMDItemContentType == 'public.folder'",
        "doc": "(kMDItemContentTypeTree == 'public.text' || kMDItemContentType == 'com.adobe.pdf' || kMDItemContentTypeTree == 'public.presentation' || kMDItemContentTypeTree == 'public.spreadsheet')",
        "document": "(kMDItemContentTypeTree == 'public.text' || kMDItemContentType == 'com.adobe.pdf' || kMDItemContentTypeTree == 'public.presentation' || kMDItemContentTypeTree == 'public.spreadsheet')",
        "code": "kMDItemContentTypeTree == 'public.source-code'",
        "audio": "kMDItemContentTypeTree == 'public.audio'",
        "music": "kMDItemContentTypeTree == 'public.audio'",
        "video": "kMDItemContentTypeTree == 'public.movie'",
        "movie": "kMDItemContentTypeTree == 'public.movie'",
        "archive": "kMDItemContentTypeTree == 'public.archive'",
        "app": "kMDItemContentType == 'com.apple.application-bundle'",
        "application": "kMDItemContentType == 'com.apple.application-bundle'",
        "text": "kMDItemContentTypeTree == 'public.text'"
    ]

    private let scope: URL
    private let find: @Sendable (_ predicate: String, _ scope: URL) async throws -> [String]
    private let spotlightProbe = SpotlightProbe()

    init(scope: URL = FileManager.default.homeDirectoryForCurrentUser, find: @escaping @Sendable (String, URL) async throws -> [String] = FileSearchProvider.spotlight) {
        self.scope = scope
        self.find = find
    }

    func isActive(for query: String) -> Bool {
        Self.fileQuery(query) != nil || Self.matchesCommand(query)
    }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        guard let query = Self.fileQuery(request.query) else {
            return Self.matchesCommand(request.query) ? [Self.searchFilesCommand] : []
        }
        let parsed = Self.parse(query)
        guard parsed.term.isEmpty || parsed.term.count >= 2 || parsed.kinds.isEmpty == false else { return [] }
        let paths: [String]
        do {
            paths = try await find(Self.predicate(for: parsed), scope)
        } catch FileSearchError.spotlightDisabled {
            return [Self.spotlightDisabledResult]
        } catch {
            return []
        }
        guard Task.isCancelled == false else { return [] }
        let usable = Self.filter(paths, scope: scope)
        // NSMetadataQuery can't tell "no matches" from "indexing off" —
        // probe once per launch only when a search comes back empty.
        if usable.isEmpty, await spotlightProbe.isDisabled(scope: scope) {
            return [Self.spotlightDisabledResult]
        }
        let ranked = parsed.term.isEmpty ? Self.recent(usable) : Self.rank(usable, term: parsed.term)
        return ranked.map(Self.result)
    }

    func defaultResults() async -> [CommandResult] { [Self.searchFilesCommand] }

    func fallbackResults(matching query: String, sensitivity _: SearchSensitivity) async -> [CommandResult] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2, Self.fileQuery(query) == nil else { return [] }
        return [CommandResult(
            id: Self.commandID,
            title: "Search Files for \u{201C}\(term)\u{201D}",
            subtitle: "Spotlight, in your home folder",
            icon: Self.searchFilesCommand.icon,
            payload: .command,
            primaryAction: CommandAction(id: "\(Self.commandID).fill", title: "Search Files", behavior: FillQueryAction(Self.prefix + term)),
            secondaryActions: []
        )]
    }

    static func fileQuery(_ query: String) -> String? {
        guard query.lowercased().hasPrefix(prefix) else { return nil }
        return query.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines).filter { "'\"\\*".contains($0) == false }
    }

    static func matchesCommand(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        return query.count >= 2 && ["search files", "files", "find file"].contains { $0.hasPrefix(query) }
    }

    static let searchFilesCommand = CommandResult(
        id: commandID,
        title: "Search Files",
        subtitle: "Type f and a file name — filter with kind:folder, kind:image, kind:doc, kind:code",
        icon: CommandIcon(fallback: "FI", systemName: "doc.text.magnifyingglass"),
        payload: .command,
        primaryAction: CommandAction(id: "\(commandID).fill", title: "Search Files", behavior: FillQueryAction(prefix)),
        secondaryActions: []
    )

    static func parse(_ query: String) -> (term: String, kinds: [String]) {
        var terms: [String] = []
        var kinds: [String] = []
        for token in query.split(separator: " ") {
            let lower = token.lowercased()
            if lower.hasPrefix("kind:") {
                if kindPredicates[String(lower.dropFirst(5))] != nil {
                    kinds.append(String(lower.dropFirst(5)))
                }
                continue
            }
            terms.append(String(token))
        }
        return (terms.joined(separator: " "), kinds)
    }

    static func predicate(for parsed: (term: String, kinds: [String])) -> String {
        var parts: [String] = []
        if parsed.term.isEmpty {
            parts.append("kMDItemContentChangeDate >= $time.this_week")
        } else {
            parts.append("kMDItemFSName == '*\(parsed.term)*'cd")
        }
        parts += parsed.kinds.compactMap { kindPredicates[$0] }
        return parts.joined(separator: " && ")
    }

    static func recent(_ paths: [String]) -> [String] {
        let fm = FileManager.default
        return paths.sorted { lhs, rhs in
            let dl = fm.attributesIfPresent(atPath: lhs)?[.modificationDate] as? Date ?? .distantPast
            let dr = fm.attributesIfPresent(atPath: rhs)?[.modificationDate] as? Date ?? .distantPast
            return dl > dr
        }.prefix(resultLimit).map { $0 }
    }

    /// Spotlight returns index order, which is meaningless to the user —
    /// score each path's basename against the term and take the best.
    static func rank(_ paths: [String], term: String) -> [String] {
        let query = SearchScoring.PreparedQuery(query: term)
        return paths
            .map { path in
                (path, SearchScoring.matchPrepared(
                    query: query,
                    normalizedTitle: SearchScoring.normalize(URL(fileURLWithPath: path).lastPathComponent),
                    normalizedSubtitle: nil,
                    normalizedKeywords: [],
                    normalizedAliases: [],
                    sensitivity: .high
                )?.score ?? 0)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
            }
            .prefix(resultLimit)
            .map(\.0)
    }

    static func filter(_ paths: [String], scope: URL) -> [String] {
        let root = scope.standardizedFileURL.path
        return paths.filter { path in
            guard path.hasPrefix(root + "/") else { return false }
            let components = path.dropFirst(root.count + 1).split(separator: "/")
            return components.contains { ignoredComponents.contains(String($0)) || $0.hasPrefix(".") } == false
        }
    }

    static let spotlightDisabledResult = CommandResult(
        id: "foundry.files.spotlight-disabled",
        title: "Spotlight Search Is Off",
        subtitle: "File search needs Spotlight indexing on your home folder",
        icon: CommandIcon(fallback: "FI", systemName: "magnifyingglass"),
        payload: .command,
        primaryAction: CommandAction(id: "foundry.files.spotlight-disabled.open", title: "Open Spotlight Settings", behavior: OpenURLAction("x-apple.systempreferences:com.apple.Siri-Settings.extension")),
        secondaryActions: []
    )

    /// In-process Spotlight search — the same index `mdfind` reads, without
    /// spawning a process per keystroke.
    static func spotlight(_ predicate: String, scope: URL) async throws -> [String] {
        await SpotlightQuery.run(
            predicate: NSPredicate(format: predicate),
            scope: scope,
            limit: streamLimit,
            timeout: .seconds(3)
        )
    }

    static func result(_ path: String) -> CommandResult {
        let url = URL(fileURLWithPath: path)
        let parent = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        let id = "file.\(path)"
        var secondary: [CommandAction] = [
            CommandAction(id: "\(id).reveal", title: "Reveal in Finder", behavior: RevealFileAction(path: path)),
            CommandAction(id: "\(id).copy-file", title: "Copy File", behavior: CopyFileAction(path: path)),
            CommandAction(id: "\(id).copy-path", title: "Copy Path", behavior: CopyToClipboardAction(path)),
        ]
        for app in FileAppResolver.apps(for: url) {
            secondary.append(CommandAction(
                id: "\(id).open-with.\(app.path)",
                title: "Open With \(app.name)",
                behavior: OpenFileWithAppAction(path: path, appPath: app.path)
            ))
        }
        secondary += [
            CommandAction(id: "\(id).shelf", title: "Add to File Shelf", behavior: AddToFileShelfAction(path: path)),
            CommandAction(id: "\(id).convert", title: "Convert…", behavior: OpenFileConverterAction(path: path)),
        ]
        if ConversionGraph.visionReadExts.contains(ConversionGraph.normalizedExtension(of: url)) {
            secondary.append(CommandAction(id: "\(id).ocr", title: "Extract Text", behavior: ExtractTextFromImageAction(path: path)))
            secondary.append(CommandAction(id: "\(id).ocr.preview", title: "Preview Extracted Text", behavior: PreviewExtractedTextAction(path: path)))
        }
        secondary += [
            CommandAction(id: "\(id).compress", title: "Compress", behavior: CompressFileAction(path: path)),
            CommandAction(id: "\(id).share", title: "Share…", behavior: ShareFileAction(path: path)),
            CommandAction(id: "\(id).rename", title: "Rename…", behavior: RenameFileAction(path: path)),
            CommandAction(id: "\(id).trash", title: "Move to Trash", behavior: MoveToTrashAction(path: path)),
        ]
        return CommandResult(
            id: id,
            title: url.lastPathComponent,
            subtitle: parent,
            icon: CommandIcon(fallback: "FI", filePath: path),
            payload: .file(url),
            primaryAction: CommandAction(id: "\(id).open", title: "Open", behavior: OpenURLAction(url.absoluteString)),
            secondaryActions: secondary
        )
    }
}

/// LaunchServices-backed "Open With" listing, cached per file extension —
/// Spotlight can produce dozens of results per keystroke and the lookup is
/// stable for a session.
enum FileAppResolver {
    struct App: Equatable { let name: String; let path: String }

    private static let cache = OSAllocatedUnfairLock(initialState: [String: [App]]())

    static func apps(for url: URL, limit: Int = 4) -> [App] {
        let key = url.pathExtension.lowercased()
        if let cached = cache.withLock({ $0[key] }) { return Array(cached.prefix(limit)) }
        let resolved = NSWorkspace.shared.urlsForApplications(toOpen: url).map {
            App(name: $0.deletingPathExtension().lastPathComponent, path: $0.path)
        }
        cache.withLock { $0[key] = resolved }
        return Array(resolved.prefix(limit))
    }
}

enum FileSearchError: Error {
    case spotlightDisabled
}

/// One-shot NSMetadataQuery bridge: streams result paths as Spotlight
/// gathers them, finishes early at the limit, and cleans up on timeout or
/// cancellation. Lives on the main actor — metadata queries are runloop-based.
@MainActor
private final class SpotlightQuery: NSObject {
    private var query: NSMetadataQuery?
    private var continuation: CheckedContinuation<[String], Never>?
    private var observers: [NSObjectProtocol] = []
    private var timeoutTask: Task<Void, Never>?
    private var paths: [String] = []
    private var seen: Set<String> = []
    private var limit = 0

    static func run(predicate: NSPredicate, scope: URL, limit: Int, timeout: Duration) async -> [String] {
        await SpotlightQuery().collect(predicate: predicate, scope: scope, limit: limit, timeout: timeout)
    }

    private func collect(predicate: NSPredicate, scope: URL, limit: Int, timeout: Duration) async -> [String] {
        let query = NSMetadataQuery()
        query.predicate = predicate
        query.searchScopes = [scope]
        query.notificationBatchingInterval = 0.05
        self.query = query
        self.limit = limit
        observers = [
            NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.drain() }
            },
            NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            },
        ]
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard Task.isCancelled == false else { return }
                    self?.finish()
                }
                query.start()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish() }
        }
    }

    private func drain() {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  seen.insert(path).inserted else { continue }
            paths.append(path)
            if paths.count >= limit {
                finish()
                return
            }
        }
    }

    private func finish() {
        guard continuation != nil else { return }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        timeoutTask?.cancel()
        query?.stop()
        query = nil
        let result = paths
        continuation?.resume(returning: result)
        continuation = nil
    }
}

/// `NSMetadataQuery` silently returns nothing when Spotlight indexing is
/// off, so distinguish "no matches" from "disabled" with a single `mdfind`
/// probe — cached for the life of the provider, run at most once per launch.
private actor SpotlightProbe {
    private var cached: Bool?
    private var inFlight: Task<Bool, Never>?

    func isDisabled(scope: URL) async -> Bool {
        if let cached { return cached }
        if let inFlight { return await inFlight.value }
        let task = Task {
            let result = await BestEffort.attempt("probe spotlight indexing") {
                try await ProcessRunner.run(
                    path: "/usr/bin/mdfind",
                    arguments: ["-onlyin", scope.path, "kMDItemFSName == '*'"],
                    timeout: 3,
                    outputLimit: 64 * 1024
                )
            }
            guard let result, result.succeeded == false else { return false }
            let stderr = result.stderr.lowercased()
            return stderr.contains("disabled") || stderr.contains("indexing")
        }
        inFlight = task
        let value = await task.value
        cached = value
        inFlight = nil
        return value
    }
}
