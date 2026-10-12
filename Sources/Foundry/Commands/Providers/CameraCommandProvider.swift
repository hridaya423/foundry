import Foundation
import FoundryDomain

final class CameraCommandProvider: CommandProvider {
    private static let commandAliases = ["camera", "webcam", "preview", "cam"]
    let id = "foundry.camera"

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        let aliases = request.customAliases[id] ?? []
        let prepared = SearchScoring.PreparedQuery(query: request.query)
        guard SearchScoring.match(
            query: prepared,
            title: "Camera",
            subtitle: "Live camera preview inside Foundry",
            keywords: [],
            aliases: Self.commandAliases + aliases,
            sensitivity: request.sensitivity
        ) != nil else { return [] }
        return [CommandResult(
            id: id,
            title: "Camera",
            subtitle: "Live camera preview inside Foundry",
            icon: CommandIcon(fallback: "CM", systemName: "camera"),
            searchAliases: Self.commandAliases + aliases,
            searchKeywords: [],
            payload: .command,
            primaryAction: CommandAction(id: "foundry.camera.open", title: "Open", behavior: OpenCameraAction()),
            secondaryActions: []
        )]
    }

    func defaultResults() async -> [CommandResult] { await search(CommandSearchRequest(query: "camera")) }
}
