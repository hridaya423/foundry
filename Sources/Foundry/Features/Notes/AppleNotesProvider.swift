import Foundation
import FoundryDomain
import FoundryServices

final class AppleNotesProvider: CommandProvider {
    enum Lookup: Sendable {
        case results([AppleNoteResult])
        case failed
    }

    let id = "foundry.apple-notes"

    private let lookup: @Sendable (String) -> Lookup

    init(lookup: @escaping @Sendable (String) -> Lookup = { AppleNotesProvider.searchNotes($0) }) {
        self.lookup = lookup
    }

    var searchPolicy: CommandProviderSearchPolicy { CommandProviderSearchPolicy(tier: .deferred) }

    func isActive(for query: String) -> Bool {
        let lowercased = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["apple notes ", "apple note ", "notes ", "note "].contains { lowercased.hasPrefix($0) }
    }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        let search = normalizedSearch(from: request.query)
        guard search.count >= 2 else { return [] }

        switch lookup(search) {
        case .failed:
            return [unavailableResult]
        case let .results(notes):
            return notes.prefix(8).map { note in
            CommandResult(
                id: "apple-note.\(note.id)",
                title: note.title,
                subtitle: note.preview,
                icon: CommandIcon(fallback: "AN", systemName: "note.text"),
                route: .notesSearch,
                primaryAction: CommandAction(id: "apple-note.open.\(note.id)", title: "Open in Apple Notes", kind: .runProcess(path: "/usr/bin/osascript", arguments: openScriptArguments(noteID: note.id))),
                secondaryActions: [
                    CommandAction(id: "apple-note.copy.\(note.id)", title: "Copy Preview", kind: .copyToClipboard(note.preview))
                ]
            )
            }
        }
    }

    func defaultResults() async -> [CommandResult] {
        [
            CommandResult(
                id: "foundry.apple-notes.open",
                title: "Apple Notes",
                subtitle: "Search with: notes <text>",
                icon: CommandIcon(fallback: "AN", systemName: "note.text"),
                primaryAction: CommandAction(id: "foundry.apple-notes.launch", title: "Open", kind: .runProcess(path: "/usr/bin/open", arguments: ["-a", "Notes"])),
                secondaryActions: []
            )
        ]
    }

    private func normalizedSearch(from query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        for prefix in ["apple notes ", "apple note ", "notes ", "note "] where lowercased.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private var unavailableResult: CommandResult {
        CommandResult(
            id: "apple-note.unavailable",
            title: "Couldn't search Apple Notes",
            subtitle: "Foundry needs Automation permission to read your notes",
            icon: CommandIcon(fallback: "AN", systemName: "note.text"),
            primaryAction: CommandAction(id: "apple-note.open-app", title: "Open Notes", kind: .runProcess(path: "/usr/bin/open", arguments: ["-a", "Notes"])),
            secondaryActions: [
                CommandAction(id: "apple-note.privacy", title: "Open Automation Settings", kind: .openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"))
            ]
        )
    }

    private static func searchNotes(_ query: String) -> Lookup {
        guard let result = ProcessRunner.runSynchronously(
            path: "/usr/bin/osascript",
            arguments: searchScriptArguments(query: query),
            timeout: 3,
            outputLimit: 4 * 1024 * 1024
        ), result.succeeded,
        let data = result.stdout.data(using: .utf8),
              let notes = try? JSONDecoder().decode([AppleNoteResult].self, from: data) else { return .failed }
        return .results(notes)
    }

    private static func searchScriptArguments(query: String) -> [String] {
        [
            "-l", "JavaScript",
            "-e", "function run(argv) { const q = String(argv[0] || '').toLowerCase(); const Notes = Application('Notes'); const strip = s => String(s || '').replace(/<[^>]*>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/\\s+/g, ' ').trim(); return JSON.stringify(Notes.notes().map(n => ({ id: n.id(), title: n.name(), preview: strip(n.body()).slice(0, 180) })).filter(n => n.title.toLowerCase().includes(q) || n.preview.toLowerCase().includes(q)).slice(0, 8)); }",
            query
        ]
    }

    private func openScriptArguments(noteID: String) -> [String] {
        [
            "-l", "JavaScript",
            "-e", "function run(argv) { const target = String(argv[0] || ''); const Notes = Application('Notes'); const note = Notes.notes().find(n => n.id() === target); if (note) { Notes.show(note); Notes.activate(); } }",
            noteID
        ]
    }
}

struct AppleNoteResult: Decodable, Sendable {
    let id: String
    let title: String
    let preview: String
}
