import Foundation
import FoundryDomain

final class LibraryProvider: CommandProvider {
    let id = "foundry.library"
    private let snippetsCache: StoredSnippetCache

    init(store: any SnippetStore = FileSnippetStore()) {
        snippetsCache = StoredSnippetCache(store: store)
    }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        let trimmed = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }

        let snippetResults = snippetsCache.current()
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
                return lhs.updatedAt > rhs.updatedAt
            }
            .filter { snippet in
                SearchScoring.match(
                    query: trimmed,
                    title: snippet.title,
                    subtitle: snippet.content,
                    keywords: [snippet.keyword] + snippet.tags,
                    aliases: [],
                    sensitivity: request.sensitivity
                ) != nil
            }
            .prefix(32)
            .map { snippet in
                return CommandResult(
                    id: "snippet.\(snippet.id)",
                    title: snippet.title,
                    subtitle: ([snippet.keyword.isEmpty ? nil : snippet.keyword, snippet.tags.isEmpty ? nil : snippet.tags.map { "#\($0)" }.joined(separator: " "), snippet.content.replacingOccurrences(of: "\n", with: " ")].compactMap { $0 }).joined(separator: " • "),
                    icon: CommandIcon(fallback: "SN", systemName: "curlybraces"),
                    searchKeywords: [snippet.keyword] + snippet.tags,
                    primaryAction: CommandAction(id: "snippet.insert.\(snippet.id)", title: "Insert Snippet", kind: .pasteSnippet(id: snippet.id)),
                    secondaryActions: [
                        CommandAction(id: "snippet.copy.\(snippet.id)", title: "Copy Snippet", kind: .copySnippet(id: snippet.id)),
                        CommandAction(id: "snippet.open.\(snippet.id)", title: "Open Snippets", kind: .openSnippets)
                    ]
                )
            }

        return snippetResults
    }
}

private final class StoredSnippetCache: @unchecked Sendable {
    private let store: any SnippetStore
    private let lock = NSLock()
    private var signature: StoredSnippetFileSignature?
    private var snippets: [StoredSnippet] = []

    init(store: any SnippetStore) {
        self.store = store
    }

    func current() -> [StoredSnippet] {
        let url = store.url
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let nextSignature = StoredSnippetFileSignature(
            modificationDate: values?.contentModificationDate,
            fileSize: values?.fileSize
        )
        return lock.withLock {
            if signature == nextSignature {
                return snippets
            }
            snippets = store.load()
            signature = nextSignature
            return snippets
        }
    }
}

private struct StoredSnippetFileSignature: Equatable {
    let modificationDate: Date?
    let fileSize: Int?
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
