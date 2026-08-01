import AppKit
import SwiftUI

struct AgentProviderIcon: View {
    let provider: AgentProviderKind
    let size: CGFloat

    var body: some View {
        Group {
            if let image = appIcon {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else if let image = brandIcon {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: provider.symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
            }
        }
        .frame(width: size, height: size)
    }

    private var brandIcon: NSImage? {
        guard let url = Self.brandResourceURL(for: provider),
              let image = NSImage(contentsOf: url) else { return nil }
        return image
    }

    nonisolated static func brandResourceURL(for provider: AgentProviderKind) -> URL? {
        guard let resource = brandResources[provider] else { return nil }
        return Bundle.module.url(forResource: resource, withExtension: "svg")
            ?? Bundle.module.url(forResource: resource, withExtension: "svg", subdirectory: "ProviderIcons")
    }

    private var appIcon: NSImage? {
        guard let paths = Self.applicationPaths[provider],
              let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }

    private static let applicationPaths: [AgentProviderKind: [String]] = [
        .cursor: ["/Applications/Cursor.app", "~/Applications/Cursor.app"].map(expandHome),
        .codex: ["/Applications/Codex.app", "~/Applications/Codex.app", "/Applications/ChatGPT.app", "~/Applications/ChatGPT.app"].map(expandHome),
        .claude: ["/Applications/Claude.app", "~/Applications/Claude.app"].map(expandHome),
        .opencode: ["/Applications/OpenCode.app", "~/Applications/OpenCode.app"].map(expandHome)
    ]

    nonisolated private static let brandResources: [AgentProviderKind: String] = [
        .claude: "anthropic",
        .opencode: "opencode"
    ]

    nonisolated private static func expandHome(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
