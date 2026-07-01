import Foundation

final class AppleNotesProvider: CommandProvider {
    let id = "foundry.apple-notes"

    func results(matching query: String) async -> [CommandResult] {
        let search = normalizedSearch(from: query)
        guard search.count >= 2 else { return [] }

        return searchNotes(search).prefix(8).map { note in
            CommandResult(
                id: "apple-note.\(note.id)",
                title: note.title,
                subtitle: note.preview,
                icon: CommandIcon(fallback: "AN", systemName: "note.text"),
                score: 116,
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
                score: 0,
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

    private func searchNotes(_ query: String) -> [AppleNoteResult] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = searchScriptArguments(query: query)
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard process.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        guard let data = output.data(using: .utf8),
              let notes = try? JSONDecoder().decode([AppleNoteResult].self, from: data) else { return [] }
        return notes
    }

    private func searchScriptArguments(query: String) -> [String] {
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

private struct AppleNoteResult: Decodable {
    let id: String
    let title: String
    let preview: String
}
