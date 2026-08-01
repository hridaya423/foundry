import Foundation

final class LibraryProvider: CommandProvider {
    let id = "foundry.library"

    func results(matching query: String) async -> [CommandResult] {
        await results(matching: query, customAliases: [:], sensitivity: .medium)
    }

    func results(matching query: String, customAliases: [String: [String]], sensitivity: SearchSensitivity) async -> [CommandResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }

        let snippetResults = LibraryPersistence.loadSnippets()
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
                    sensitivity: sensitivity
                ) != nil
            }
            .prefix(32)
            .map { snippet in
                let rendered = SnippetRenderer.render(snippet.content)
                return CommandResult(
                    id: "snippet.\(snippet.id)",
                    title: snippet.title,
                    subtitle: ([snippet.keyword.isEmpty ? nil : snippet.keyword, snippet.tags.isEmpty ? nil : snippet.tags.map { "#\($0)" }.joined(separator: " "), snippet.content.replacingOccurrences(of: "\n", with: " ")].compactMap { $0 }).joined(separator: " • "),
                    icon: CommandIcon(fallback: "SN", systemName: "curlybraces"),
                    searchKeywords: [snippet.keyword] + snippet.tags,
                    primaryAction: CommandAction(id: "snippet.insert.\(snippet.id)", title: "Insert Snippet", kind: .pasteText(rendered)),
                    secondaryActions: [
                        CommandAction(id: "snippet.copy.\(snippet.id)", title: "Copy Snippet", kind: .copyToClipboard(rendered)),
                        CommandAction(id: "snippet.open.\(snippet.id)", title: "Open Snippets", kind: .openSnippets)
                    ]
                )
            }

        return snippetResults
    }
}
