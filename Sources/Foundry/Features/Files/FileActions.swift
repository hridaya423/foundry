import AppKit
import Foundation
import FoundryDomain
import FoundryServices

struct RevealFileAction: ResultAction, Equatable {
    let path: String

    var icon: String? { "folder" }
    var shortcut: ActionShortcut? { ActionShortcut(key: "r", modifiers: [.shift, .command]) }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        .fileResults([URL(fileURLWithPath: path)])
    }
}

struct CompressFileAction: ResultAction, Equatable {
    let path: String

    var icon: String? { "archivebox" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let source = URL(fileURLWithPath: path)
        let destination = Self.uniqueArchiveDestination(for: source)
        do {
            _ = try await ProcessRunner.run(path: "/usr/bin/ditto", arguments: ["-c", "-k", "--keepParent", source.path, destination.path])
            ctx.diagnostics.log("Compressed \(source.lastPathComponent) → \(destination.lastPathComponent)")
            ctx.emit(.feedback(.success("Created \u{201C}\(destination.lastPathComponent)\u{201D}")))
            return .fileResults([destination])
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: destination)
            return .cancelled
        } catch {
            try? FileManager.default.removeItem(at: destination)
            ctx.diagnostics.log("Compress failed for \(path): \(error.localizedDescription)")
            return ctx.finish(.failure(message: String(localized: "Could not compress \u{201C}\(source.lastPathComponent)\u{201D}"), retryable: true))
        }
    }

    private static func uniqueArchiveDestination(for source: URL) -> URL {
        let folder = source.deletingLastPathComponent()
        let base = source.lastPathComponent
        var candidate = folder.appendingPathComponent("\(base).zip")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(counter).zip")
            counter += 1
        }
        return candidate
    }
}

struct ShareFileAction: ResultAction, Equatable {
    let path: String

    var icon: String? { "square.and.arrow.up" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        shareFile(path: path)
    }
}

/// Present the share picker for a file path — used by conversion results
/// and any surface that already holds a URL (no command-result plumbing).
@MainActor
@discardableResult
func shareFile(path: String) -> CommandOutcome {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else {
        return .failure(message: String(localized: "The file no longer exists"), retryable: false)
    }
    // Anchor to the Foundry panel (or any app window) — the share picker
    // needs a live view to present from.
    guard let anchor = (NSApp.windows.first { $0 is FoundryPanel } ?? NSApp.keyWindow)?.contentView else {
        return .failure(message: String(localized: "Could not open the share menu"), retryable: false)
    }
    let picker = NSSharingServicePicker(items: [url])
    let rect = NSRect(x: anchor.bounds.midX, y: anchor.bounds.maxY - 40, width: 1, height: 1)
    picker.show(relativeTo: rect, of: anchor, preferredEdge: .minY)
    return .stayOpen(message: nil)
}

@MainActor
func shareFile(at url: URL) {
    _ = shareFile(path: url.path)
}

struct RenameFileAction: ResultAction, Equatable {
    let path: String

    var icon: String? { "pencil" }
    var shortcut: ActionShortcut? { ActionShortcut(key: "e", modifiers: [.command]) }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let source = URL(fileURLWithPath: path)
        let icon = await Task.detached(priority: .utility) {
            NSWorkspace.shared.icon(forFile: path)
        }.value
        let prompt = await ctx.panel.requestPrompt(PanelPromptSpec(
            title: "Rename \u{201C}\(source.lastPathComponent)\u{201D}",
            message: "Enter a new name.",
            fields: [PanelPromptSpec.Field(id: "name", placeholder: "New name", initial: source.lastPathComponent)],
            image: icon,
            confirmLabel: "Rename"
        ))
        guard prompt.confirmed else { return .cancelled }
        let newName = (prompt.texts.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard newName.isEmpty == false, newName != source.lastPathComponent else { return .cancelled }
        guard newName.contains("/") == false, newName.contains(":") == false else {
            ctx.emit(.feedback(.failure("Names can\u{2019}t contain / or :")))
            return .failure(message: String(localized: "Invalid name"), retryable: true)
        }
        let destination = source.deletingLastPathComponent().appendingPathComponent(newName)
        guard FileManager.default.fileExists(atPath: destination.path) == false else {
            ctx.emit(.feedback(.failure("\u{201C}\(newName)\u{201D} already exists")))
            return .failure(message: String(localized: "A file with that name already exists"), retryable: true)
        }
        do {
            try FileManager.default.moveItem(at: source, to: destination)
            ctx.diagnostics.log("Renamed \(source.lastPathComponent) → \(newName)")
            return .refreshResults(message: String(localized: "Renamed to \u{201C}\(newName)\u{201D}"))
        } catch {
            ctx.diagnostics.log("Rename failed for \(path): \(error.localizedDescription)")
            return ctx.finish(.failure(message: String(localized: "Could not rename file"), retryable: true))
        }
    }
}

struct MoveToTrashAction: ResultAction, Equatable {
    let path: String

    var icon: String? { "trash" }
    var style: ActionStyle { .destructive }
    var shortcut: ActionShortcut? { ActionShortcut(key: "\u{7f}", modifiers: [.command]) }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let url = URL(fileURLWithPath: path)
        do {
            try ctx.trashItem(url)
            ctx.diagnostics.log("Moved to Trash: \(path)")
            return ctx.finish(
                .refreshResults(message: String(localized: "Moved to Trash")),
                 feedback: .success(String(localized: "Moved \u{201C}\(url.lastPathComponent)\u{201D} to Trash")))
        } catch {
            ctx.diagnostics.log("Trash failed for \(path): \(error.localizedDescription)")
            return ctx.finish(
                .failure(message: String(localized: "Could not move to Trash"), retryable: true),
                 feedback: .failure(String(localized: "Could not move to Trash")))
        }
    }
}

struct AddToFileShelfAction: ResultAction, Equatable {
    let path: String

    var icon: String? { "tray.and.arrow.down" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        .addToFileShelf(urls: [URL(fileURLWithPath: path)])
    }
}
