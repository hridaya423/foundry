import Foundation
import FoundryDomain
import FoundryServices
import os

final class AppleNotesProvider: CommandProvider {
    let id = "foundry.apple-notes"

    private let runScript: @Sendable ([String]) -> ProcessResult?

    init(runScript: @escaping @Sendable ([String]) -> ProcessResult? = {
        ProcessRunner.runSynchronously(path: "/usr/bin/osascript", arguments: $0, timeout: 20, outputLimit: 4 * 1024 * 1024)
    }) {
        self.runScript = runScript
    }

    var searchPolicy: CommandProviderSearchPolicy { CommandProviderSearchPolicy(tier: .deferred) }

    func isActive(for query: String) -> Bool {
        let lowercased = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["apple notes ", "apple note ", "notes ", "note "].contains { lowercased.hasPrefix($0) }
    }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        let search = normalizedSearch(from: request.query)
        guard search.count >= 2 else { return [] }

        let notes: [AppleNoteResult]
        switch notesCache.fetch(refresh: fetchAllNotes) {
        case let .notes(fetched): notes = fetched
        case .denied: return [deniedResult]
        case .failed: return [failedResult]
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
                payload: .note(id: note.id),
                primaryAction: CommandAction(id: "apple-note.open.\(note.id)", title: "Open in Apple Notes",
                    behavior: RunProcessAction(path: "/usr/bin/osascript", arguments: openScriptArguments(noteID: note.id))),
                secondaryActions: [
                    CommandAction(id: "apple-note.copy.\(note.id)", title: "Copy Preview", behavior: CopyToClipboardAction(note.preview))
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
                payload: .command,
                primaryAction: CommandAction(id: "foundry.apple-notes.launch", title: "Open", behavior: RunProcessAction(path: "/usr/bin/open",
                    arguments: ["-a", "Notes"])),
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

    enum Fetch: Sendable {
        case notes([AppleNoteResult])
        case denied
        case failed
    }

    /// Keeps a failure for a short while too, so a slow or refused Notes is not asked again on every keystroke.
    private final class NotesCacheBox: Sendable {
        private let cached = OSAllocatedUnfairLock<(at: Date, fetch: Fetch)?>(initialState: nil)

        func fetch(refresh: () -> Fetch) -> Fetch {
            cached.withLockUnchecked { cached in
                if let cached {
                    let ttl: TimeInterval = if case .notes = cached.fetch { 60 } else { 15 }
                    if Date().timeIntervalSince(cached.at) < ttl { return cached.fetch }
                }
                let fetch = refresh()
                cached = (Date(), fetch)
                return fetch
            }
        }
    }

    private let notesCache = NotesCacheBox()

    private func fetchAllNotes() -> Fetch {
        guard let result = runScript(listScriptArguments()) else { return .failed }
        guard result.succeeded else {
            return result.stderr.contains("-1743") || result.stderr.localizedCaseInsensitiveContains("not authori") ? .denied : .failed
        }
        let notes = BestEffort.attempt("decode notes results") {
            try JSONDecoder().decode([AppleNoteResult].self, from: Data(result.stdout.utf8))
        }
        return notes.map(Fetch.notes) ?? .failed
    }

    private let deniedResult = CommandResult(
        id: "apple-note.unavailable",
        title: "Couldn’t search Apple Notes",
        subtitle: "Check Automation access in System Settings › Privacy & Security",
        icon: CommandIcon(fallback: "AN", systemName: "exclamationmark.triangle"),
        payload: .command,
        primaryAction: CommandAction(
            id: "apple-note.open-privacy",
            title: "Open Privacy Settings",
            behavior: OpenURLAction("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        ),
        secondaryActions: []
    )

    private let failedResult = CommandResult(
        id: "apple-note.failed",
        title: "Apple Notes didn’t answer",
        subtitle: "Try again in a moment",
        icon: CommandIcon(fallback: "AN", systemName: "exclamationmark.triangle"),
        payload: .command,
        primaryAction: CommandAction(id: "apple-note.failed.open", title: "Open Apple Notes",
            behavior: RunProcessAction(path: "/usr/bin/open", arguments: ["-a", "Notes"])),
        secondaryActions: []
    )

    private func listScriptArguments() -> [String] {
        [
            "-l", "JavaScript",
            "-e", """
            function run(argv) {
                const Notes = Application('Notes');
                const strip = s => String(s || '').replace(/\\s+/g, ' ').trim();
                const notes = Notes.notes;
                const ids = notes.id(), titles = notes.name(), texts = notes.plaintext();
                return JSON.stringify(ids.slice(0, 4000).map((id, i) => ({
                    id: id,
                    title: String(titles[i] || ''),
                    preview: strip(texts[i]).slice(0, 180),
                })));
            }
            """
        ]
    }

    private func openScriptArguments(noteID: String) -> [String] {
        [
            "-l", "JavaScript",
            "-e",
                "function run(argv) { const target = String(argv[0] || ''); const Notes = Application('Notes'); const note = Notes.notes().find(n " +
                    "=> n.id() === target); if (note) { Notes.show(note); Notes.activate(); } }",
            noteID
        ]
    }
}

struct AppleNoteResult: Decodable, Sendable {
    let id: String
    let title: String
    let preview: String
}
