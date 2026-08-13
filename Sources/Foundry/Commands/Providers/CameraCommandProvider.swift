import Foundation
import FoundryDomain

final class CameraCommandProvider: CommandProvider {
    let id = "foundry.camera"

    var descriptor: CommandProviderDescriptor {
        CommandProviderDescriptor(id: id, version: "1", availability: .available, requiredPermissions: ["camera"], supportedContexts: ["search", "home"], searchPolicy: searchPolicy, health: nil)
    }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        let aliases = request.customAliases[id] ?? []
        guard SearchScoring.match(query: request.query, title: "Camera", subtitle: "Live camera preview inside Foundry", keywords: [], aliases: ["camera", "webcam", "preview", "cam"] + aliases, sensitivity: request.sensitivity) != nil else { return [] }
        return [CommandResult(id: id, title: "Camera", subtitle: "Live camera preview inside Foundry", icon: CommandIcon(fallback: "CM", systemName: "camera"), searchAliases: aliases, searchKeywords: ["camera", "webcam", "preview", "cam"], primaryAction: CommandAction(id: "foundry.camera.open", title: "Open", kind: .openCamera), secondaryActions: [])]
    }

    func defaultResults() async -> [CommandResult] { await search(CommandSearchRequest(query: "camera")) }
}
