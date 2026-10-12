import AppKit
import Foundation
import FoundryDomain
import FoundryServices

private let snippetLimit = 65_536

private func recordSnippetUse(id: String, in ctx: ActionContext) {
    var snippets = ctx.snippetStore.load()
    guard let index = snippets.firstIndex(where: { $0.id == id }) else { return }
    snippets[index].recordUse()
    _ = ctx.snippetStore.save(snippets)
}

private func snippetTitle(from content: String) -> String {
    let firstLine = content.split(separator: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return firstLine.isEmpty ? "Clipboard Snippet" : String(firstLine.prefix(60))
}

private struct RaycastSnippetImport: Decodable {
    let name: String
    let text: String
    let keyword: String?
}

private struct RaycastSnippetExport: Encodable {
    let name: String
    let text: String
    let keyword: String?
}

struct CopySnippetAction: ResultAction, Equatable {
    let id: String

    var icon: String? { "doc.on.doc" }
    var resultSection: ResultSection? { .snippets }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        guard let snippet = ctx.snippetStore.load(
            ).first(where: { $0.id == id }) else { return .failure(message: String(localized: "Snippet not found"),
             retryable: false) }
        let rendered = SnippetRenderer.render(snippet.content, context: ctx.snippetContext())
        ctx.pasteboard.clearContents(); ctx.pasteboard.setString(rendered.text, forType: .string)
        recordSnippetUse(id: id, in: ctx)
        return ctx.finish(.copied(content: rendered.text), feedback: .success(String(localized: "Copied to clipboard")))
    }
}

struct PasteSnippetAction: ResultAction, Equatable {
    let id: String

    var icon: String? { "text.insert" }
    var resultSection: ResultSection? { .snippets }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        guard let snippet = ctx.snippetStore.load(
            ).first(where: { $0.id == id }) else { return .failure(message: String(localized: "Snippet not found"),
             retryable: false) }
        let rendered = SnippetRenderer.render(snippet.content, context: ctx.snippetContext())
        do {
            try ctx.directPasteService.stage(.text(rendered.text), cursorOffset: rendered.cursorOffsetFromEnd)
            recordSnippetUse(id: id, in: ctx)
            return ctx.finish(.pasted(content: rendered.text), feedback: .success(String(localized: "Inserted snippet")))
        } catch DirectPasteError.missingTarget {
            return ctx.finish(
                .stayOpen(message: String(localized: "No originating application is available")),
                 feedback: .failure(String(localized: "No originating application is available")))
        } catch {
            return ctx.finish(.stayOpen(message: String(localized: "Could not stage paste")), feedback: .failure(String(localized: "Could not stage paste")))
        }
    }
}

struct DeleteSnippetAction: ResultAction, Equatable {
    let id: String

    var icon: String? { "trash" }
    var style: ActionStyle { .destructive }
    var shortcut: ActionShortcut? { ActionShortcut(key: "x", modifiers: [.control]) }
    var resultSection: ResultSection? { .snippets }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let snippets = ctx.snippetStore.load()
        guard snippets.contains(where: { $0.id == id }) else { return .failure(message: String(localized: "Snippet not found"), retryable: false) }
        _ = ctx.snippetStore.save(snippets.filter { $0.id != id })
        return ctx.finish(.refreshResults(message: String(localized: "Snippet deleted")), feedback: .success(String(localized: "Snippet deleted")))
    }
}

struct CreateSnippetFromClipboardAction: ResultAction, Equatable {
    var icon: String? { "plus.rectangle.on.rectangle" }
    var resultSection: ResultSection? { .snippets }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        guard let content = ctx.pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), content.isEmpty == false else {
            ctx.diagnostics.log("Clipboard is empty")
            return ctx.finish(
                .failure(message: String(localized: "Clipboard is empty"), retryable: false),
                 feedback: .info(String(localized: "Clipboard is empty")))
        }
        var snippets = ctx.snippetStore.load()
        snippets.insert(StoredSnippet(title: snippetTitle(from: content), content: String(content.prefix(snippetLimit))), at: 0)
        if case let .failure(error) = ctx.snippetStore.save(snippets) {
            ctx.diagnostics.log("Failed to save clipboard snippet: \(error.localizedDescription)")
            return ctx.finish(
                .failure(message: String(localized: "Could not save snippet"), retryable: true),
                 feedback: .failure(String(localized: "Could not save snippet")))
        }
        ctx.diagnostics.log("Created snippet from clipboard")
        return ctx.finish(.success(message: String(localized: "Created snippet")), feedback: .success(String(localized: "Created snippet")))
    }
}

struct ImportSnippetsAction: ResultAction, Equatable {
    var icon: String? { "square.and.arrow.down" }
    var resultSection: ResultSection? { .snippets }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }

        do {
            let data = try Data(contentsOf: url)
            let imported = try JSONDecoder().decode([RaycastSnippetImport].self, from: data)
            var snippets = ctx.snippetStore.load()
            var added = 0
            var skipped = 0

            for item in imported {
                let title = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let content = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard title.isEmpty == false, content.isEmpty == false else { skipped += 1; continue }
                if snippets.contains(where: { $0.title == title && $0.content == content }) {
                    skipped += 1
                    continue
                }
                snippets.insert(StoredSnippet(title: title, content: String(content.prefix(snippetLimit)), keyword: item.keyword ?? ""), at: 0)
                added += 1
            }

            if case let .failure(error) = ctx.snippetStore.save(snippets) {
                ctx.diagnostics.log("Failed to save imported snippets: \(error.localizedDescription)")
                return .failure(message: String(localized: "Could not save imported snippets"), retryable: true)
            }
            let message = String(localized: "Imported \(added) snippets, skipped \(skipped) duplicates")
            ctx.diagnostics.log(message)
            return ctx.finish(.success(message: message), feedback: .success(message))
        } catch {
            ctx.diagnostics.log("Snippet import failed: \(error.localizedDescription)")
            return .failure(message: String(localized: "Snippet import failed"), retryable: false)
        }
    }
}

struct ExportSnippetsAction: ResultAction, Equatable {
    var icon: String? { "square.and.arrow.up" }
    var resultSection: ResultSection? { .snippets }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let snippets = ctx.snippetStore.load()
        guard snippets.isEmpty == false else {
            return .failure(message: String(localized: "No snippets to export"), retryable: false)
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "foundry-snippets.json"
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }

        let exported = snippets.map { RaycastSnippetExport(name: $0.title, text: $0.content, keyword: $0.keyword.isEmpty ? nil : $0.keyword) }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(exported).write(to: url, options: .atomic)
            let message = String(localized: "Exported \(snippets.count) snippet\(snippets.count == 1 ? "" : "s")")
            ctx.diagnostics.log("\(message) to \(url.path)")
            return ctx.finish(.success(message: message), feedback: .success(message))
        } catch {
            ctx.diagnostics.log("Snippet export failed: \(error.localizedDescription)")
            return .failure(message: String(localized: "Snippet export failed"), retryable: true)
        }
    }
}
