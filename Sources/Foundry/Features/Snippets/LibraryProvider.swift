import Foundation
import FoundryDomain
import FoundryServices
import os

final class LibraryProvider: CommandProvider {
    let id = "foundry.library"
    private let snippetsCache: StoredSnippetCache

    init(store: any SnippetStore = FileSnippetStore()) {
        snippetsCache = StoredSnippetCache(store: store)
    }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        let trimmed = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }
        let prepared = SearchScoring.PreparedQuery(query: trimmed)

        let snippetResults = snippetsCache.current()
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
                return lhs.updatedAt > rhs.updatedAt
            }
            .filter { snippet in
                SearchScoring.match(
                    query: prepared,
                    title: snippet.title,
                    subtitle: snippet.content,
                    keywords: [snippet.keyword] + snippet.tags,
                    aliases: [],
                    sensitivity: request.sensitivity
                ) != nil
            }
            .prefix(32)
            .map { snippet in
                let insertAction = CommandAction(id: "snippet.insert.\(snippet.id)", title: "Insert Snippet", behavior: PasteSnippetAction(id: snippet.id))
                let copyAction = CommandAction(id: "snippet.copy.\(snippet.id)", title: "Copy Snippet", behavior: CopySnippetAction(id: snippet.id))
                let insertPrimary = request.snippetInsertAsPrimary
                return CommandResult(
                    id: "snippet.\(snippet.id)",
                    title: snippet.title,
                    subtitle: [
                        snippet.keyword.isEmpty ? nil : snippet.keyword,
                        snippet.tags.isEmpty ? nil : snippet.tags.map { "#\($0)" }.joined(separator: " "),
                        snippet.content.replacingOccurrences(of: "\n", with: " "),
                    ].compactMap { $0 }.joined(separator: " • "),
                    icon: CommandIcon(fallback: "SN", systemName: "curlybraces"),
                    searchAliases: [snippet.keyword].filter { $0.isEmpty == false },
                    searchKeywords: snippet.tags,
                    payload: .snippet(id: snippet.id),
                    primaryAction: insertPrimary ? insertAction : copyAction,
                    secondaryActions: [
                        insertPrimary ? copyAction : insertAction,
                        CommandAction(id: "snippet.edit.\(snippet.id)", title: "Edit Snippet", behavior: EditSnippetAction(id: snippet.id)),
                        CommandAction(id: "snippet.delete.\(snippet.id)", title: "Delete Snippet", behavior: DeleteSnippetAction(id: snippet.id))
                    ]
                )
            }

        return snippetResults
    }
}

private final class StoredSnippetCache: Sendable {
    private let store: any SnippetStore
    private let state = OSAllocatedUnfairLock<(signature: StoredSnippetFileSignature?, snippets: [StoredSnippet])>(initialState: (nil, []))

    init(store: any SnippetStore) {
        self.store = store
    }

    func current() -> [StoredSnippet] {
        let url = store.url
        let values = url.fileResourceValues([.contentModificationDateKey, .fileSizeKey])
        let nextSignature = StoredSnippetFileSignature(
            modificationDate: values?.contentModificationDate,
            fileSize: values?.fileSize
        )
        return state.withLockUnchecked { state in
            if state.signature == nextSignature {
                return state.snippets
            }
            state.snippets = store.load()
            state.signature = nextSignature
            return state.snippets
        }
    }
}

private struct StoredSnippetFileSignature: Equatable {
    let modificationDate: Date?
    let fileSize: Int?
}
