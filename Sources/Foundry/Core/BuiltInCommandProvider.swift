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

    private func commands() -> [BuiltInCommand] {
        [
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
                id: "foundry.settings",
                title: "Open Foundry Settings",
                subtitle: "Open the local Foundry config folder",
                aliases: ["foundry config", "config", "preferences"],
                systemIcon: "slider.horizontal.3",
                fallback: "ST",
                scoreBoost: 1,
                primaryAction: CommandAction(id: "foundry.settings.open", title: "Open", kind: .openConfigFolder),
                secondaryActions: []
            ),
            BuiltInCommand(
                id: "foundry.rebuild-file-index",
                title: "Rebuild File Index",
                subtitle: "Rescan files and prune ignored package/cache folders",
                aliases: ["reindex", "refresh files", "scan files", "file index", "rebuild index"],
                systemIcon: "arrow.clockwise",
                fallback: "RI",
                scoreBoost: 2,
                primaryAction: CommandAction(id: "foundry.rebuild-file-index.perform", title: "Rebuild", kind: .rebuildFileIndex),
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
