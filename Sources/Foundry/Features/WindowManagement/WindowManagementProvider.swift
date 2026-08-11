import Foundation
import FoundryDomain

final class WindowManagementProvider: CommandProvider {
    let id = "foundry.windows"

    var searchPolicy: CommandProviderSearchPolicy {
        CommandProviderSearchPolicy(tier: .immediate, includesSupplementalResults: false)
    }

    var descriptor: CommandProviderDescriptor {
        CommandProviderDescriptor(
            id: id,
            version: "1",
            availability: .available,
            requiredPermissions: ["accessibility"],
            supportedContexts: ["search", "home"],
            searchPolicy: searchPolicy,
            health: nil
        )
    }

    func search(_ request: CommandSearchRequest) async throws -> [CommandResult] {
        let layoutOverviewQuery = WindowLayoutQuery.isOverview(request.query)
        return commands().compactMap { command in
            guard Task.isCancelled == false else { return nil }
            let aliases = request.customAliases[command.id] ?? []
            if layoutOverviewQuery == false {
                guard Self.matches(command, query: request.query, aliases: aliases, sensitivity: request.sensitivity) else { return nil }
            }
            return CommandResult(
                id: command.id,
                title: command.title,
                subtitle: command.subtitle,
                icon: command.icon,
                searchAliases: aliases,
                searchKeywords: command.aliases,
                primaryAction: command.primaryAction,
                secondaryActions: []
            )
        }
    }

    func defaultResults() async throws -> [CommandResult] {
        commands()
            .filter { WindowPlacement.homeDefaults.contains($0.placement) }
            .map(\.result)
    }

    private func commands() -> [WindowCommand] {
        WindowPlacement.allCases.map { placement in
            let metadata = WindowPlacementMetadata(placement)
            let id = "window.\(placement.rawValue)"
            return WindowCommand(
                id: id,
                placement: placement,
                title: metadata.title,
                subtitle: metadata.subtitle,
                aliases: metadata.aliases,
                icon: CommandIcon(fallback: metadata.fallback, systemName: metadata.icon),
                primaryAction: CommandAction(
                    id: "\(id).perform",
                    title: "Tile",
                    kind: .tileWindow(placement)
                )
            )
        }
    }

    private static func matches(_ command: WindowCommand, query: String, aliases: [String], sensitivity: SearchSensitivity) -> Bool {
        SearchScoring.match(query: query, title: command.title, subtitle: command.subtitle, keywords: [], aliases: command.aliases + aliases, sensitivity: sensitivity) != nil
    }
}

private struct WindowCommand {
    let id: String
    let placement: WindowPlacement
    let title: String
    let subtitle: String
    let aliases: [String]
    let icon: CommandIcon
    let primaryAction: CommandAction

    var result: CommandResult {
        CommandResult(
            id: id,
            title: title,
            subtitle: subtitle,
            icon: icon,
            primaryAction: primaryAction,
            secondaryActions: []
        )
    }
}
