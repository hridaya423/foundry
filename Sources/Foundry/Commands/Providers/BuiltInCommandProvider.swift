import AppKit
import Foundation
import FoundryDomain
import FoundryServices

final class BuiltInCommandProvider: CommandProvider {
    let id = "foundry.builtin"

    private let diagnostics: DiagnosticsService

    init(config: ConfigService, diagnostics: DiagnosticsService) {
        self.diagnostics = diagnostics
    }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        commands().compactMap { command in
            guard Task.isCancelled == false else { return nil }
            let aliases = request.customAliases[command.id] ?? []
            guard SearchScoring.match(
                query: request.query,
                title: command.title,
                subtitle: command.subtitle,
                keywords: [],
                aliases: command.aliases + aliases,
                sensitivity: request.sensitivity
            ) != nil else {
                return nil
            }

            return CommandResult(
                id: command.id,
                title: command.title,
                subtitle: command.subtitle,
                icon: CommandIcon(fallback: command.fallback, systemName: command.systemIcon),
                searchAliases: aliases,
                searchKeywords: command.aliases,
                primaryAction: command.primaryAction,
                secondaryActions: []
            )
        }
    }

    func defaultResults() async -> [CommandResult] {
        commands().map { command in
            CommandResult(
                id: command.id,
                title: command.title,
                subtitle: command.subtitle,
                icon: CommandIcon(fallback: command.fallback, systemName: command.systemIcon),
                primaryAction: command.primaryAction,
                secondaryActions: []
            )
        }
    }

    private func commands() -> [BuiltInCommand] {
        [
            BuiltInCommand(
                id: "foundry.emoji-picker",
                title: "Emoji & Symbols",
                subtitle: "Search and copy emoji, symbols, and reactions",
                aliases: ["emoji", "emojis", "symbols", "characters", "reaction", "smiley", "unicode"],
                systemIcon: "face.smiling",
                fallback: "EM",
                primaryAction: CommandAction(id: "foundry.emoji-picker.open", title: "Open", kind: .openEmojiPicker),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.downloads",
                title: "Downloads",
                subtitle: "View and manage media downloads",
                aliases: ["download", "downloads", "media downloads", "download queue", "media queue", "download manager"],
                systemIcon: "arrow.down.circle",
                fallback: "DL",
                primaryAction: CommandAction(id: "foundry.downloads.open", title: "Open", kind: .openMediaDownloads),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.file-shelf",
                title: "File Shelf",
                subtitle: "Hold dragged files temporarily",
                aliases: ["shelf", "files", "drop", "drag", "temporary files"],
                systemIcon: "tray.full",
                fallback: "FS",
                primaryAction: CommandAction(id: "foundry.file-shelf.open", title: "Open", kind: .openFileShelf),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.file-convert",
                title: "Convert File",
                subtitle: "Convert images, documents, audio, and video locally",
                aliases: ["convert", "converter", "file convert", "transcode", "reformat"],
                systemIcon: "arrow.triangle.2.circlepath",
                fallback: "CV",
                primaryAction: CommandAction(id: "foundry.file-convert.open", title: "Open", kind: .openFileConverter()),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.clipboard-history",
                title: "Clipboard History",
                subtitle: "Search, reuse, and act on copied text, files, and images",
                aliases: ["clipboard", "copyboard", "copy history", "pasteboard", "paste history", "history"],
                systemIcon: "doc.on.clipboard",
                fallback: "CB",
                primaryAction: CommandAction(id: "foundry.clipboard-history.open", title: "Open", kind: .openClipboardHistory),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.snippets",
                title: "Snippets",
                subtitle: "Search, edit, pin, copy, and insert snippets",
                aliases: ["snippets", "snippet", "search snippets", "code snippets", "templates"],
                systemIcon: "curlybraces",
                fallback: "SN",
                primaryAction: CommandAction(id: "foundry.snippets.open", title: "Open", kind: .openSnippets),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.snippets.create-from-clipboard",
                title: "Create Snippet from Clipboard",
                subtitle: "Save copied text as a reusable snippet",
                aliases: ["new snippet", "create snippet", "clipboard snippet", "save snippet"],
                systemIcon: "plus.rectangle.on.rectangle",
                fallback: "SN",
                primaryAction: CommandAction(id: "foundry.snippets.create-from-clipboard.perform", title: "Create", kind: .createSnippetFromClipboard),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.snippets.import",
                title: "Import Snippets",
                subtitle: "Import Raycast snippets JSON",
                aliases: ["import snippets", "raycast snippets", "snippets json"],
                systemIcon: "square.and.arrow.down",
                fallback: "SN",
                primaryAction: CommandAction(id: "foundry.snippets.import.perform", title: "Import", kind: .importSnippets),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.camera",
                title: "Camera",
                subtitle: "Live camera preview inside Foundry",
                aliases: ["camera", "webcam", "preview", "cam"],
                systemIcon: "camera",
                fallback: "CM",
                primaryAction: CommandAction(id: "foundry.camera.open", title: "Open", kind: .openCamera),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.translate",
                title: "Translate",
                subtitle: "Translate text with Apple on-device language model",
                aliases: ["translate", "translator", "translation", "language"],
                systemIcon: "globe",
                fallback: "TR",
                primaryAction: CommandAction(id: "foundry.translate.open", title: "Open", kind: .openTranslator()),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.ai",
                title: "Ask AI",
                subtitle: "Apple Foundation Models first, with optional Ollama tools",
                aliases: ["ask ai", "ai", "plan", "draft"],
                systemIcon: "sparkles",
                fallback: "AI",
                primaryAction: CommandAction(id: "foundry.ai.open", title: "Open", kind: .openQuickAI(prompt: "")),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.developer-tools",
                title: "Developer Tools",
                subtitle: "Base conversion, bitwise operations, and text transforms",
                aliases: ["developer tools", "base convert", "bitwise", "radix", "binary", "hex"],
                systemIcon: "hammer",
                fallback: "DT",
                primaryAction: CommandAction(id: "foundry.developer-tools.open", title: "Open", kind: .openDeveloperTools()),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.settings",
                title: "Open Foundry Settings",
                subtitle: "Customize Home, commands, and Foundry preferences",
                aliases: ["foundry config", "config", "preferences"],
                systemIcon: "slider.horizontal.3",
                fallback: "ST",
                primaryAction: CommandAction(id: "foundry.settings.open", title: "Open", kind: .openSettings),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.quit",
                title: "Quit Foundry",
                subtitle: "Stop the local prototype process.",
                aliases: ["exit", "close foundry"],
                systemIcon: "power",
                fallback: "QT",
                primaryAction: CommandAction(id: "foundry.quit.perform", title: "Quit", kind: .quit),
                secondaryActions: []
            )
        ]
    }
}

private struct BuiltInCommand {
    let id: String
    let title: String
    let subtitle: String
    let aliases: [String]
    let systemIcon: String
    let fallback: String
    let primaryAction: CommandAction
    let secondaryActions: [CommandAction]
}
