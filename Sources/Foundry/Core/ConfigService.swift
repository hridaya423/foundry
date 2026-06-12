import Foundation

struct FoundryConfig: Codable, Equatable {
    var hotkey: FoundryHotkey = .optionSpace
    var themeIntensity: Double = 0.72
}

final class ConfigService {
    private let diagnostics: DiagnosticsService
    private(set) var current: FoundryConfig

    init(diagnostics: DiagnosticsService) {
        self.diagnostics = diagnostics
        self.current = Self.load() ?? FoundryConfig()
    }

    static var configURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/foundry/config.json")
    }

    func save() {
        do {
            let url = Self.configURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(current)
            try data.write(to: url, options: .atomic)
            diagnostics.log("Saved config to \(url.path)")
        } catch {
            diagnostics.log("Failed to save config: \(error.localizedDescription)")
        }
    }

    private static func load() -> FoundryConfig? {
        let url = configURL
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FoundryConfig.self, from: data)
    }
}
