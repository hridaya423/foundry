import Foundation
import FoundryDomain

final class WindowManagementProvider: CommandProvider {
    let id = "foundry.windows"

    private let commands = WindowPlacement.allCases.map { placement in
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
                behavior: TileWindowAction(placement)
            )
        )
    }

    var searchPolicy: CommandProviderSearchPolicy {
        CommandProviderSearchPolicy(tier: .immediate, includesSupplementalResults: false)
    }

    func search(_ request: CommandSearchRequest) async throws -> [CommandResult] {
        let layoutOverviewQuery = WindowLayoutQuery.isOverview(request.query)
        let prepared = SearchScoring.PreparedQuery(query: request.query)
        return commands.compactMap { command in
            guard Task.isCancelled == false else { return nil }
            let aliases = request.customAliases[command.id] ?? []
            if layoutOverviewQuery == false {
                guard Self.matches(command, query: prepared, aliases: aliases, sensitivity: request.sensitivity) else { return nil }
            }
            return CommandResult(
                id: command.id,
                title: command.title,
                subtitle: command.subtitle,
                icon: command.icon,
                searchAliases: command.aliases + aliases,
                searchKeywords: [],
                payload: .command,
                primaryAction: command.primaryAction,
                secondaryActions: []
            )
        }
    }

    func defaultResults() async throws -> [CommandResult] {
        commands
            .filter { WindowPlacement.homeDefaults.contains($0.placement) }
            .map(\.result)
    }

    private static func matches(_ command: WindowCommand, query: SearchScoring.PreparedQuery, aliases: [String], sensitivity: SearchSensitivity) -> Bool {
        var searchableMask = command.searchableMask
        for alias in aliases {
            searchableMask |= SearchScoring.characterMask(SearchScoring.normalize(alias))
        }
        guard SearchScoring.probableMatch(query: query, searchableMask: searchableMask, sensitivity: sensitivity) else { return false }
        let normalizedAliases = aliases.isEmpty
            ? command.normalizedAliases
            : command.normalizedAliases + aliases.map(SearchScoring.normalize)
        return SearchScoring.matchPrepared(query: query, normalizedTitle: command.normalizedTitle,
            normalizedSubtitle: command.normalizedSubtitle, normalizedKeywords: [], normalizedAliases: normalizedAliases,
            sensitivity: sensitivity) != nil
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
    let normalizedTitle: String
    let normalizedSubtitle: String
    let normalizedAliases: [String]
    let searchableMask: UInt64

    init(id: String, placement: WindowPlacement, title: String, subtitle: String, aliases: [String],
         icon: CommandIcon, primaryAction: CommandAction) {
        self.id = id
        self.placement = placement
        self.title = title
        self.subtitle = subtitle
        self.aliases = aliases
        self.icon = icon
        self.primaryAction = primaryAction
        self.normalizedTitle = SearchScoring.normalize(title)
        self.normalizedSubtitle = SearchScoring.normalize(subtitle)
        self.normalizedAliases = aliases.map(SearchScoring.normalize)
        self.searchableMask = ([title, subtitle] + aliases).reduce(0) { $0 | SearchScoring.characterMask($1) }
    }

    var result: CommandResult {
        CommandResult(
            id: id,
            title: title,
            subtitle: subtitle,
            icon: icon,
            payload: .command,
            primaryAction: primaryAction,
            secondaryActions: []
        )
    }
}
