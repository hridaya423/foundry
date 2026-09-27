import Foundation
import FoundryDomain
import FoundryServices
import os

final class FileSearchProvider: CommandProvider, @unchecked Sendable {
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

    init(scope: URL = FileManager.default.homeDirectoryForCurrentUser, find: @escaping @Sendable (String, URL) async throws -> [String] = FileSearchProvider.mdfind) {
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
        let ranked = parsed.term.isEmpty ? Self.recent(usable) : Array(usable.prefix(Self.resultLimit))
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
            primaryAction: CommandAction(id: "\(Self.commandID).fill", title: "Search Files", kind: .fillQuery(Self.prefix + term)),
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
        primaryAction: CommandAction(id: "\(commandID).fill", title: "Search Files", kind: .fillQuery(prefix)),
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
            let dl = (try? fm.attributesOfItem(atPath: lhs)[.modificationDate] as? Date) ?? .distantPast
            let dr = (try? fm.attributesOfItem(atPath: rhs)[.modificationDate] as? Date) ?? .distantPast
            return dl > dr
        }.prefix(resultLimit).map { $0 }
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
        primaryAction: CommandAction(id: "foundry.files.spotlight-disabled.open", title: "Open Spotlight Settings", kind: .openURL("x-apple.systempreferences:com.apple.Siri-Settings.extension")),
        secondaryActions: []
    )

    static func mdfind(_ predicate: String, scope: URL) async throws -> [String] {
        let state = OSAllocatedUnfairLock(initialState: (paths: [String](), disabled: false, run: Task<Void, Never>?.none))
        let run = Task {
            let result = try? await ProcessRunner.run(path: "/usr/bin/mdfind", arguments: ["-onlyin", scope.path, predicate], timeout: 3, outputLimit: 64 * 1024) { output in
                guard output.stream == .stdout, filter([output.line], scope: scope).isEmpty == false else { return }
                let full = state.withLock { state -> Task<Void, Never>? in
                    guard state.paths.count < streamLimit else { return nil }
                    state.paths.append(output.line)
                    return state.paths.count == streamLimit ? state.run : nil
                }
                full?.cancel()
            }
            if let result, result.succeeded == false {
                let stderr = result.stderr.lowercased()
                if stderr.contains("disabled") || stderr.contains("indexing") {
                    state.withLock { $0.disabled = true }
                }
            }
        }
        if state.withLock({ $0.run = run; return $0.paths.count >= streamLimit }) { run.cancel() }
        await withTaskCancellationHandler { await run.value } onCancel: { run.cancel() }
        let outcome = state.withLock { ($0.paths, $0.disabled) }
        if outcome.1 { throw FileSearchError.spotlightDisabled }
        return outcome.0
    }

    static func result(_ path: String) -> CommandResult {
        let url = URL(fileURLWithPath: path)
        let parent = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        let id = "file.\(path)"
        return CommandResult(
            id: id,
            title: url.lastPathComponent,
            subtitle: parent,
            icon: CommandIcon(fallback: "FI", filePath: path),
            primaryAction: CommandAction(id: "\(id).open", title: "Open", kind: .openURL(url.absoluteString)),
            secondaryActions: [
                CommandAction(id: "\(id).copy-file", title: "Copy File", kind: .copyFile(path: path)),
                CommandAction(id: "\(id).shelf", title: "Add to File Shelf", kind: .addToFileShelf(path: path)),
                CommandAction(id: "\(id).convert", title: "Convert…", kind: .openFileConverter(path: path))
            ]
        )
    }
}

enum FileSearchError: Error {
    case spotlightDisabled
}
