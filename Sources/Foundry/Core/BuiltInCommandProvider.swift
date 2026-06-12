import AppKit
import Foundation

final class BuiltInCommandProvider: CommandProvider {
    let id = "foundry.builtin"

    private let config: ConfigService
    private let diagnostics: DiagnosticsService

    init(config: ConfigService, diagnostics: DiagnosticsService) {
        self.config = config
        self.diagnostics = diagnostics
    }

    func results(matching query: String) -> [CommandResult] {
        commands().compactMap { command in
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
                id: "foundry.settings",
                title: "Open Foundry Settings",
                subtitle: "Open the local Foundry config folder",
                aliases: ["foundry config", "config", "preferences"],
                systemIcon: "slider.horizontal.3",
                fallback: "ST",
                scoreBoost: 1,
                primaryAction: CommandAction(id: "foundry.settings.open", title: "Open") { [diagnostics] in
                    let folder = ConfigService.configURL.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    diagnostics.log("Opening Foundry config folder")
                    DispatchQueue.main.async {
                        NSWorkspace.shared.open(folder)
                    }
                },
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
                primaryAction: CommandAction(id: "foundry.quit.perform", title: "Quit") {
                    DispatchQueue.main.async {
                        NSApp.terminate(nil)
                    }
                },
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
