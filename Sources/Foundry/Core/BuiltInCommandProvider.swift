import AppKit
import Foundation

final class BuiltInCommandProvider: CommandProvider {
    let id = "foundry.builtin"

    private let diagnostics: DiagnosticsService

    init(config: ConfigService, diagnostics: DiagnosticsService) {
        self.diagnostics = diagnostics
    }

    func results(matching query: String) async -> [CommandResult] {
        commands().compactMap { command in
            guard Task.isCancelled == false else { return nil }
            guard let score = SearchScoring.score(query: query, title: command.title, aliases: command.aliases) else {
                return nil
            }

            return CommandResult(
                id: command.id,
                title: command.title,
                subtitle: command.subtitle,
                icon: CommandIcon(fallback: command.fallback, systemName: command.systemIcon),
                score: score + command.scoreBoost,
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
                score: 0,
                primaryAction: command.primaryAction,
                secondaryActions: []
            )
        }
        .filter { result in
            result.primaryAction.kind != .openActivityMonitor
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
                scoreBoost: 3,
                primaryAction: CommandAction(id: "foundry.emoji-picker.open", title: "Open", kind: .openEmojiPicker),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.activity-monitor",
                title: "Activity Monitor",
                subtitle: "Inspect CPU, memory, and running processes",
                aliases: ["processes", "process monitor", "cpu", "memory", "ram", "system monitor", "task manager"],
                systemIcon: "cpu",
                fallback: "AM",
                scoreBoost: 3,
                primaryAction: CommandAction(id: "foundry.activity-monitor.open", title: "Open", kind: .openActivityMonitor),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.file-shelf",
                title: "File Shelf",
                subtitle: "Hold dragged files temporarily",
                aliases: ["shelf", "files", "drop", "drag", "temporary files"],
                systemIcon: "tray.full",
                fallback: "FS",
                scoreBoost: 3,
                primaryAction: CommandAction(id: "foundry.file-shelf.open", title: "Open", kind: .openFileShelf),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.clipboard-history",
                title: "Clipboard History",
                subtitle: "Search, reuse, and act on copied text, files, and images",
                aliases: ["clipboard", "copyboard", "copy history", "pasteboard", "paste history", "history"],
                systemIcon: "doc.on.clipboard",
                fallback: "CB",
                scoreBoost: 3,
                primaryAction: CommandAction(id: "foundry.clipboard-history.open", title: "Open", kind: .openClipboardHistory),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.translate",
                title: "Translate",
                subtitle: "Translate text with Apple on-device language model",
                aliases: ["translate", "translator", "translation", "language"],
                systemIcon: "globe",
                fallback: "TR",
                scoreBoost: 4,
                primaryAction: CommandAction(id: "foundry.translate.open", title: "Open", kind: .openTranslator()),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.settings",
                title: "Open Foundry Settings",
                subtitle: "Customize widgets and Foundry preferences",
                aliases: ["foundry config", "config", "preferences"],
                systemIcon: "slider.horizontal.3",
                fallback: "ST",
                scoreBoost: 1,
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
                scoreBoost: 0,
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
    let scoreBoost: Double
    let primaryAction: CommandAction
    let secondaryActions: [CommandAction]
}
