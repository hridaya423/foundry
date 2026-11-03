import AppKit
import SwiftUI

struct AgentProviderIcon: View {
    let provider: AgentProviderKind
    let size: CGFloat
    @State private var brandImage: NSImage?

    var body: some View {
        Group {
            if let path = Self.applicationPath(for: provider) {
                FileIcon(path: path) { brandOrFallback }
            } else {
                brandOrFallback
            }
        }
        .frame(width: size, height: size)
        .task(id: provider) {
            brandImage = await AgentProviderIconCache.shared.brandIcon(for: provider)
        }
    }

    @ViewBuilder
    private var brandOrFallback: some View {
        if let image = brandImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: provider.symbol)
                .font(FoundryTheme.glyph(size * 0.52))
                .foregroundStyle(FoundryTheme.textSecondary)
        }
    }

    nonisolated static func brandResourceURL(for provider: AgentProviderKind) -> URL? {
        guard let resource = brandResources[provider] else { return nil }
        return Bundle.packagedResources?.url(forResource: resource, withExtension: "svg")
            ?? Bundle.packagedResources?.url(forResource: resource, withExtension: "svg", subdirectory: "ProviderIcons")
    }

    nonisolated static func applicationPath(for provider: AgentProviderKind) -> String? {
        applicationPaths[provider]?.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    nonisolated fileprivate static let applicationPaths: [AgentProviderKind: [String]] = [
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

private actor AgentProviderIconCache {
    static let shared = AgentProviderIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private var missing: Set<String> = []
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    init() {
        cache.countLimit = 32
        cache.totalCostLimit = 2 * 1024 * 1024
    }

    func brandIcon(for provider: AgentProviderKind) async -> NSImage? {
        let key = "brand.\(provider.rawValue)" as NSString
        if let image = cache.object(forKey: key) { return image }
        if missing.contains(key as String) { return nil }
        if let task = inFlight[key as String] { return await task.value }
        let task = Task.detached(priority: .utility) {
            guard let url = AgentProviderIcon.brandResourceURL(for: provider),
                  let image = NSImage(contentsOf: url) else { return nil as NSImage? }
            image.size = NSSize(width: 32, height: 32)
            return image
        }
        inFlight[key as String] = task
        let image = await task.value
        inFlight[key as String] = nil
        guard let image else {
            missing.insert(key as String)
            return nil
        }
        cache.setObject(image, forKey: key, cost: 32 * 32 * 4)
        return image
    }
}
