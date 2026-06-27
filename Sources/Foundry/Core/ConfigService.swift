import Foundation

struct FoundryConfig: Codable, Equatable {
    var hotkey: FoundryHotkey = .optionSpace
    var themeIntensity: Double = 0.72
    var widgets: WidgetBoardConfig = .default

    init(hotkey: FoundryHotkey = .optionSpace, themeIntensity: Double = 0.72, widgets: WidgetBoardConfig = .default) {
        self.hotkey = hotkey
        self.themeIntensity = themeIntensity
        self.widgets = widgets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = try container.decodeIfPresent(FoundryHotkey.self, forKey: .hotkey) ?? .optionSpace
        themeIntensity = try container.decodeIfPresent(Double.self, forKey: .themeIntensity) ?? 0.72
        widgets = try container.decodeIfPresent(WidgetBoardConfig.self, forKey: .widgets) ?? .default
    }
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

    func updateWidgets(_ widgets: WidgetBoardConfig) {
        current.widgets = widgets
        save()
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
