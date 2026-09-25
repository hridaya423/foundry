import Foundation
import FoundryDomain
import FoundryServices

final class AppleNotesProvider: CommandProvider {
    let id = "foundry.apple-notes"

    var searchPolicy: CommandProviderSearchPolicy { CommandProviderSearchPolicy(tier: .deferred) }

    func isActive(for query: String) -> Bool {
        let lowercased = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["apple notes ", "apple note ", "notes ", "note "].contains { lowercased.hasPrefix($0) }
    }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        let search = normalizedSearch(from: request.query)
        guard search.count >= 2 else { return [] }

        guard let notes = allNotes() else {
            return [unavailableResult]
        }
        let needle = search.lowercased()
        return notes
            .filter { $0.title.lowercased().contains(needle) || $0.preview.lowercased().contains(needle) }
            .prefix(8)
            .map { note in
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

    private final class NotesCacheBox: @unchecked Sendable {
        private let lock = NSLock()
        private var cached: (at: Date, notes: [AppleNoteResult])?
        private let ttl: TimeInterval = 60

        func notes(refresh: () -> [AppleNoteResult]?) -> [AppleNoteResult]? {
            lock.lock()
            defer { lock.unlock() }
            if let cached, Date().timeIntervalSince(cached.at) < ttl { return cached.notes }
            guard let notes = refresh() else { return cached?.notes }
            cached = (Date(), notes)
            return notes
        }
    }

    private let notesCache = NotesCacheBox()

    private func allNotes() -> [AppleNoteResult]? {
        notesCache.notes(refresh: fetchAllNotes)
    }

    private func fetchAllNotes() -> [AppleNoteResult]? {
        guard let result = ProcessRunner.runSynchronously(
            path: "/usr/bin/osascript",
            arguments: listScriptArguments(),
            timeout: 3,
            outputLimit: 4 * 1024 * 1024
        ), result.succeeded,
        let data = result.stdout.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([AppleNoteResult].self, from: data)
    }

    private let unavailableResult = CommandResult(
        id: "apple-note.unavailable",
        title: "Couldn’t search Apple Notes",
        subtitle: "Check Automation access in System Settings › Privacy & Security",
        icon: CommandIcon(fallback: "AN", systemName: "exclamationmark.triangle"),
        primaryAction: CommandAction(
            id: "apple-note.open-privacy",
            title: "Open Privacy Settings",
            kind: .openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        ),
        secondaryActions: []
    )

    private func listScriptArguments() -> [String] {
        [
            "-l", "JavaScript",
            "-e", "function run(argv) { const Notes = Application('Notes'); const strip = s => String(s || '').replace(/<[^>]*>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/\\s+/g, ' ').trim(); return JSON.stringify(Notes.notes().map(n => ({ id: n.id(), title: n.name(), preview: strip(n.body()).slice(0, 180) })).slice(0, 4000)); }"
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

private struct AppleNoteResult: Decodable {
    let id: String
    let title: String
    let preview: String
}
