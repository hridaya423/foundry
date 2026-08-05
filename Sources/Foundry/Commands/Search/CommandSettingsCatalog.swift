import Foundation
import FoundryDomain

struct CommandSettingsRowModel: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let sourceLabel: String
    let icon: CommandIcon
    let searchText: String
    let preference: CommandPreference

    init(descriptor: CommandDescriptor, preference: CommandPreference) {
        id = descriptor.id
        title = descriptor.title
        subtitle = descriptor.subtitle ?? Self.sourceLabel(for: descriptor.sourceID)
        sourceLabel = Self.sourceLabel(for: descriptor.sourceID)
        icon = descriptor.icon
        self.preference = preference
        searchText = [
            descriptor.title,
            descriptor.subtitle ?? "",
            descriptor.sourceID,
            descriptor.category,
            preference.aliases.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private static func sourceLabel(for sourceID: String) -> String {
        switch sourceID {
        case "foundry.apps": "Applications"
        case "foundry.builtin": "Foundry"
        case "foundry.system": "System"
        case "foundry.browser": "Browsers"
        default: sourceID.replacingOccurrences(of: "foundry.", with: "").capitalized
        }
    }
}

enum CommandSettingsCatalog {
    static func build(
        descriptors: [CommandDescriptor],
        preferences: [String: CommandPreference],
        query: String
    ) -> (rows: [CommandSettingsRowModel], visibleRows: [CommandSettingsRowModel]) {
        let rows = descriptors.map { descriptor in
            CommandSettingsRowModel(
                descriptor: descriptor,
                preference: preferences[descriptor.id] ?? CommandPreference()
            )
        }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let visibleRows = rows
            .filter { normalizedQuery.isEmpty || $0.searchText.contains(normalizedQuery) }
            .sorted { lhs, rhs in
                switch (lhs.preference.favoriteRank, rhs.preference.favoriteRank) {
                case let (lhsRank?, rhsRank?):
                    if lhsRank != rhsRank { return lhsRank < rhsRank }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    break
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        return (rows: rows, visibleRows: visibleRows)
    }
}
