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
        AgentProviderIconCache.shared.brandIcon(for: provider)
    }

    nonisolated static func brandResourceURL(for provider: AgentProviderKind) -> URL? {
        guard let resource = brandResources[provider] else { return nil }
        return Bundle.module.url(forResource: resource, withExtension: "svg")
            ?? Bundle.module.url(forResource: resource, withExtension: "svg", subdirectory: "ProviderIcons")
    }

    private var appIcon: NSImage? {
        AgentProviderIconCache.shared.appIcon(for: provider)
    }

    fileprivate static let applicationPaths: [AgentProviderKind: [String]] = [
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

@MainActor
private final class AgentProviderIconCache {
    static let shared = AgentProviderIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private var missing: Set<String> = []

    init() {
        cache.countLimit = 32
        cache.totalCostLimit = 2 * 1024 * 1024
    }

    func appIcon(for provider: AgentProviderKind) -> NSImage? {
        let key = "app.\(provider.rawValue)" as NSString
        if let image = cache.object(forKey: key) { return image }
        if missing.contains(key as String) { return nil }
        guard let paths = AgentProviderIcon.applicationPaths[provider],
              let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            missing.insert(key as String)
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 32, height: 32)
        cache.setObject(image, forKey: key, cost: 32 * 32 * 4)
        return image
    }

    func brandIcon(for provider: AgentProviderKind) -> NSImage? {
        let key = "brand.\(provider.rawValue)" as NSString
        if let image = cache.object(forKey: key) { return image }
        if missing.contains(key as String) { return nil }
        guard let url = AgentProviderIcon.brandResourceURL(for: provider),
              let image = NSImage(contentsOf: url) else {
            missing.insert(key as String)
            return nil
        }
        image.size = NSSize(width: 32, height: 32)
        cache.setObject(image, forKey: key, cost: 32 * 32 * 4)
        return image
    }
}
