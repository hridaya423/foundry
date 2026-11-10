import Foundation
import FoundryDomain

final class BuiltInCommandProvider: CommandProvider {
    let id = "foundry.builtin"
    private let commands = BuiltInCommandProvider.makeCommands()

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        let prepared = SearchScoring.PreparedQuery(query: request.query)
        return commands.compactMap { command in
            guard Task.isCancelled == false else { return nil }
            let aliases = request.customAliases[command.id] ?? []
            guard SearchScoring.matches(prepared, searchableMask: command.searchableMask, normalizedTitle: command.normalizedTitle,
                normalizedSubtitle: command.normalizedSubtitle, normalizedAliases: command.normalizedAliases, customAliases: aliases,
                sensitivity: request.sensitivity) else { return nil }

            return CommandResult(
                id: command.id,
                title: command.title,
                subtitle: command.subtitle,
                icon: CommandIcon(fallback: command.fallback, systemName: command.systemIcon),
                searchAliases: command.aliases + aliases,
                searchKeywords: [],
                payload: .command,
                primaryAction: command.primaryAction,
                secondaryActions: []
            )
        }
    }

    func defaultResults() async -> [CommandResult] {
        commands.map { command in
            CommandResult(
                id: command.id,
                title: command.title,
                subtitle: command.subtitle,
                icon: CommandIcon(fallback: command.fallback, systemName: command.systemIcon),
                payload: .command,
                primaryAction: command.primaryAction,
                secondaryActions: []
            )
        }
    }

    private static func makeCommands() -> [BuiltInCommand] {
        [
            BuiltInCommand(
                id: "foundry.emoji-picker",
                title: "Emoji & Symbols",
                subtitle: "Search and copy emoji, symbols, and reactions",
                aliases: ["emoji", "emojis", "symbols", "characters", "reaction", "smiley", "unicode"],
                systemIcon: "face.smiling",
                fallback: "EM",
                primaryAction: CommandAction(id: "foundry.emoji-picker.open", title: "Open", behavior: OpenEmojiPickerAction())
            ),
            BuiltInCommand(
                id: "foundry.downloads",
                title: "Downloads",
                subtitle: "View and manage media downloads",
                aliases: ["download", "downloads", "media downloads", "download queue", "media queue", "download manager"],
                systemIcon: "arrow.down.circle",
                fallback: "DL",
                primaryAction: CommandAction(id: "foundry.downloads.open", title: "Open", behavior: OpenMediaDownloadsAction())
            ),
            BuiltInCommand(
                id: "foundry.file-shelf",
                title: "File Shelf",
                subtitle: "Hold dragged files temporarily",
                aliases: ["shelf", "files", "drop", "drag", "temporary files"],
                systemIcon: "tray.full",
                fallback: "FS",
                primaryAction: CommandAction(id: "foundry.file-shelf.open", title: "Open", behavior: OpenFileShelfAction())
            ),
            BuiltInCommand(
                id: "foundry.file-convert",
                title: "Convert File",
                subtitle: "Convert images, documents, audio, and video locally",
                aliases: ["convert", "converter", "file convert", "transcode", "reformat"],
                systemIcon: "arrow.triangle.2.circlepath",
                fallback: "CV",
                primaryAction: CommandAction(id: "foundry.file-convert.open", title: "Open", behavior: OpenFileConverterAction())
            ),
            BuiltInCommand(
                id: "foundry.clipboard-history",
                title: "Clipboard History",
                subtitle: "Search, reuse, and act on copied text, files, and images",
                aliases: ["clipboard", "copyboard", "copy history", "pasteboard", "paste history", "history"],
                systemIcon: "doc.on.clipboard",
                fallback: "CB",
                primaryAction: CommandAction(id: "foundry.clipboard-history.open", title: "Open", behavior: OpenClipboardHistoryAction())
            ),
            BuiltInCommand(
                id: "foundry.snippets",
                title: "Snippets",
                subtitle: "Search, edit, pin, copy, and insert snippets",
                aliases: ["snippets", "snippet", "search snippets", "code snippets", "templates"],
                systemIcon: "curlybraces",
                fallback: "SN",
                primaryAction: CommandAction(id: "foundry.snippets.open", title: "Open", behavior: OpenSnippetsAction())
            ),
            BuiltInCommand(
                id: "foundry.snippets.create-from-clipboard",
                title: "Create Snippet from Clipboard",
                subtitle: "Save copied text as a reusable snippet",
                aliases: ["new snippet", "create snippet", "clipboard snippet", "save snippet"],
                systemIcon: "plus.rectangle.on.rectangle",
                fallback: "SN",
                primaryAction: CommandAction(id: "foundry.snippets.create-from-clipboard.perform", title: "Create",
                    behavior: CreateSnippetFromClipboardAction())
            ),
            BuiltInCommand(
                id: "foundry.snippets.import",
                title: "Import Snippets",
                subtitle: "Import Raycast snippets JSON",
                aliases: ["import snippets", "raycast snippets", "snippets json"],
                systemIcon: "square.and.arrow.down",
                fallback: "SN",
                primaryAction: CommandAction(id: "foundry.snippets.import.perform", title: "Import", behavior: ImportSnippetsAction())
            ),
            BuiltInCommand(
                id: "foundry.snippets.export",
                title: "Export Snippets",
                subtitle: "Save your snippets as Raycast-compatible JSON",
                aliases: ["export snippets", "backup snippets", "snippets backup"],
                systemIcon: "square.and.arrow.up",
                fallback: "SN",
                primaryAction: CommandAction(id: "foundry.snippets.export.perform", title: "Export", behavior: ExportSnippetsAction())
            ),
            BuiltInCommand(
                id: "foundry.translate",
                title: "Translate",
                 subtitle: "Translate text between languages",
                aliases: ["translate", "translator", "translation", "language"],
                systemIcon: "globe",
                fallback: "TR",
                primaryAction: CommandAction(id: "foundry.translate.open", title: "Open", behavior: OpenTranslatorAction())
            ),
            BuiltInCommand(
                id: "foundry.ai",
                title: "Ask AI",
                subtitle: "Ask a question or draft text with your AI model",
                aliases: ["ask ai", "ai", "plan", "draft"],
                systemIcon: "sparkles",
                fallback: "AI",
                primaryAction: CommandAction(id: "foundry.ai.open", title: "Open", behavior: OpenQuickAIAction(prompt: ""))
            ),
            BuiltInCommand(
                id: "foundry.developer-tools",
                title: "Developer Tools",
                subtitle: "Base conversion, bitwise operations, and text transforms",
                aliases: ["developer tools", "base convert", "bitwise", "radix", "binary", "hex"],
                systemIcon: "hammer",
                fallback: "DT",
                primaryAction: CommandAction(id: "foundry.developer-tools.open", title: "Open", behavior: OpenDeveloperToolsAction())
            ),
            BuiltInCommand(
                id: "foundry.extract-text",
                title: "Extract Text from Image",
                subtitle: "Run OCR on an image and copy the text",
                aliases: ["ocr", "recognize text", "read text", "text from image", "vision"],
                systemIcon: "text.viewfinder",
                fallback: "OCR",
                primaryAction: CommandAction(id: "foundry.extract-text.perform", title: "Choose Image", behavior: ExtractTextFromImageAction(path: nil))
            ),
            BuiltInCommand(
                id: "foundry.pick-color",
                title: "Pick Color",
                subtitle: "Sample a color anywhere on screen and copy the hex value",
                aliases: ["color picker", "eyedropper", "hex color", "sample color"],
                systemIcon: "eyedropper.halffull",
                fallback: "CL",
                primaryAction: CommandAction(id: "foundry.pick-color.perform", title: "Pick Color", behavior: PickColorAction())
            ),
            BuiltInCommand(
                id: "foundry.qr-generate",
                title: "Generate QR Code",
                subtitle: "Encode the clipboard text as a QR code image",
                aliases: ["qr code", "qr generate", "make qr", "barcode"],
                systemIcon: "qrcode",
                fallback: "QR",
                primaryAction: CommandAction(id: "foundry.qr-generate.perform", title: "Generate", behavior: GenerateQRCodeAction())
            ),
            BuiltInCommand(
                id: "foundry.qr-read",
                title: "Read QR Code",
                subtitle: "Decode a QR code or barcode from an image",
                aliases: ["qr scan", "decode qr", "read barcode", "scan code"],
                systemIcon: "qrcode.viewfinder",
                fallback: "QR",
                primaryAction: CommandAction(id: "foundry.qr-read.perform", title: "Choose Image", behavior: ReadQRCodeAction())
            ),
            BuiltInCommand(
                id: "foundry.qr-wifi",
                title: "Wi-Fi QR Code",
                subtitle: "Generate a QR code that joins guests to a Wi-Fi network",
                aliases: ["wifi qr", "wifi code", "share wifi", "network qr"],
                systemIcon: "wifi",
                fallback: "WF",
                primaryAction: CommandAction(id: "foundry.qr-wifi.perform", title: "Generate", behavior: GenerateWiFiQRCodeAction())
            ),
            BuiltInCommand(
                id: "foundry.screen-ocr",
                title: "Capture Text from Screen",
                subtitle: "Select a screen region and copy its text",
                aliases: ["screen ocr", "screenshot text", "grab text", "capture text", "screen capture ocr"],
                systemIcon: "text.viewfinder",
                fallback: "SO",
                primaryAction: CommandAction(id: "foundry.screen-ocr.perform", title: "Capture", behavior: RecognizeScreenTextAction())
            ),
            BuiltInCommand(
                id: "foundry.empty-trash",
                title: "Empty Trash",
                subtitle: "Permanently delete everything in the Trash",
                aliases: ["trash", "empty bin", "delete trash"],
                systemIcon: "trash.slash",
                fallback: "TR",
                primaryAction: CommandAction(id: "foundry.empty-trash.perform", title: "Empty Trash", behavior: EmptyTrashAction())
            ),
            BuiltInCommand(
                id: "foundry.desktop-icons",
                title: "Toggle Desktop Icons",
                subtitle: "Show or hide the icons on your desktop",
                aliases: ["desktop icons", "hide desktop", "show desktop", "clean desktop"],
                systemIcon: "macwindow.on.rectangle",
                fallback: "DI",
                primaryAction: CommandAction(id: "foundry.desktop-icons.perform", title: "Toggle", behavior: ToggleDesktopIconsAction())
            ),
            BuiltInCommand(
                id: "foundry.paste-plain",
                title: "Paste Clipboard as Plain Text",
                subtitle: "Insert the clipboard text into the previous app",
                aliases: ["paste plain", "paste without formatting", "plain paste", "strip formatting"],
                systemIcon: "doc.plaintext",
                fallback: "PP",
                primaryAction: CommandAction(id: "foundry.paste-plain.perform", title: "Paste", behavior: PasteClipboardAsPlainTextAction())
            ),
            BuiltInCommand(
                id: "foundry.confetti",
                title: "Make Confetti",
                subtitle: "Celebrate something",
                aliases: ["confetti", "celebrate", "party"],
                systemIcon: "party.popper.fill",
                fallback: "🎉",
                primaryAction: CommandAction(id: "foundry.confetti.perform", title: "Celebrate", behavior: CelebrateAction())
            ),
            BuiltInCommand(
                id: "foundry.settings",
                title: "Foundry Settings",
                subtitle: "Customize Home, commands, and Foundry preferences",
                aliases: ["foundry config", "config", "preferences"],
                systemIcon: "slider.horizontal.3",
                fallback: "ST",
                primaryAction: CommandAction(id: "foundry.settings.open", title: "Open", behavior: OpenSettingsAction())
            ),
            BuiltInCommand(
                id: "foundry.welcome",
                title: "Welcome to Foundry",
                subtitle: "Replay the setup guide",
                aliases: ["welcome", "onboarding", "setup", "guide", "getting started", "tutorial"],
                systemIcon: "sparkles.rectangle.stack",
                fallback: "WG",
                primaryAction: CommandAction(id: "foundry.welcome.open", title: "Open", behavior: OpenWelcomeGuideAction())
            ),
            BuiltInCommand(
                id: "foundry.quit",
                title: "Quit Foundry",
                subtitle: "Quit Foundry and stop background features.",
                aliases: ["exit", "close foundry"],
                systemIcon: "power",
                fallback: "QT",
                primaryAction: CommandAction(id: "foundry.quit.perform", title: "Quit", behavior: QuitAction())
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
    let normalizedTitle: String
    let normalizedSubtitle: String
    let normalizedAliases: [String]
    let searchableMask: UInt64

    init(id: String, title: String, subtitle: String, aliases: [String], systemIcon: String, fallback: String,
         primaryAction: CommandAction) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.aliases = aliases
        self.systemIcon = systemIcon
        self.fallback = fallback
        self.primaryAction = primaryAction
        self.normalizedTitle = SearchScoring.normalize(title)
        self.normalizedSubtitle = SearchScoring.normalize(subtitle)
        self.normalizedAliases = aliases.map(SearchScoring.normalize)
        self.searchableMask = ([normalizedTitle, normalizedSubtitle] + normalizedAliases).reduce(0) { $0 | SearchScoring.characterMask($1) }
    }
}
