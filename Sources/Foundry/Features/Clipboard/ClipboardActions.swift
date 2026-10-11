import AppKit
import Foundation
import FoundryDomain
import FoundryServices

struct CopyToClipboardAction: ResultAction, Equatable {
    let value: String

    init(_ value: String) { self.value = value }

    var icon: String? { "doc.on.doc" }
    var shortcut: ActionShortcut? { ActionShortcut(key: "c", modifiers: [.shift, .command]) }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        ctx.pasteboard.clearContents()
        ctx.pasteboard.setString(value, forType: .string)
        ctx.diagnostics.log("Copied to clipboard")
        return ctx.finish(.copied(content: value), feedback: .success(Self.copiedMessage(for: value)))
    }

    static func copiedMessage(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed.count <= 32, trimmed.contains(where: \.isNewline) == false else { return "Copied to clipboard" }
        return "Copied \(trimmed)"
    }
}

struct CopyFileAction: ResultAction, Equatable {
    let path: String

    var icon: String? { "doc.on.doc" }
    var shortcut: ActionShortcut? { ActionShortcut(key: "c", modifiers: [.command]) }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let url = URL(fileURLWithPath: path)
        ctx.pasteboard.clearContents()
        ctx.pasteboard.writeObjects([url as NSURL])
        ctx.diagnostics.log("Copied file")
        return ctx.finish(.copied(content: path), feedback: .success("Copied \u{201C}\(url.lastPathComponent)\u{201D}"))
    }
}

struct PasteTextAction: ResultAction, Equatable {
    let value: String
    let cursorOffset: Int
    let snippetID: String?

    init(_ value: String, cursorOffset: Int = 0, snippetID: String? = nil) {
        self.value = value
        self.cursorOffset = cursorOffset
        self.snippetID = snippetID
    }

    var icon: String? { "text.insert" }
    var resultSection: ResultSection? { .snippets }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        do {
            try ctx.directPasteService.stage(.text(value), cursorOffset: cursorOffset)
            ctx.diagnostics.log("Staged direct paste")
            return ctx.finish(.pasted(content: value), feedback: .success("Inserted snippet"))
        } catch DirectPasteError.missingTarget {
            return ctx.finish(.stayOpen(message: "No originating application is available"), feedback: .failure("No originating application is available"))
        } catch {
            return ctx.finish(.stayOpen(message: "Could not stage paste"), feedback: .failure("Could not stage paste"))
        }
    }
}

struct PasteClipboardAsPlainTextAction: ResultAction, Equatable {
    var icon: String? { "doc.plaintext" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        guard let text = ctx.pasteboard.string(forType: .string), text.isEmpty == false else {
            return ctx.finish(.failure(message: "Clipboard has no text", retryable: false), feedback: .info("Clipboard has no text"))
        }
        do {
            try ctx.directPasteService.stage(.text(text), cursorOffset: 0)
            return ctx.finish(.pasted(content: text), feedback: .success("Pasted as plain text"))
        } catch DirectPasteError.missingTarget {
            return ctx.finish(.stayOpen(message: "No originating application is available"), feedback: .failure("No originating application is available"))
        } catch {
            return ctx.finish(.stayOpen(message: "Could not stage paste"), feedback: .failure("Could not stage paste"))
        }
    }
}
