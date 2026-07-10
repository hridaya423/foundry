import Foundation

struct FoundryConfig: Codable, Equatable {
    var hotkey: FoundryHotkey = .commandSpace
    var themeIntensity: Double = 0.72
    var showAgentShelf: Bool = true
    var widgets: WidgetBoardConfig = .default

    init(hotkey: FoundryHotkey = .commandSpace, themeIntensity: Double = 0.72, showAgentShelf: Bool = true, widgets: WidgetBoardConfig = .default) {
        self.hotkey = hotkey
        self.themeIntensity = themeIntensity
        self.showAgentShelf = showAgentShelf
        self.widgets = widgets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let savedHotkey = try container.decodeIfPresent(FoundryHotkey.self, forKey: .hotkey)
        if let savedHotkey,
           savedHotkey.keyCode == FoundryHotkey.commandSpace.keyCode,
           savedHotkey.modifiers == FoundryHotkey.commandSpace.modifiers {
            hotkey = .commandSpace
        } else if savedHotkey == .optionSpace {
            hotkey = .commandSpace
        } else {
            hotkey = savedHotkey ?? .commandSpace
        }
        themeIntensity = try container.decodeIfPresent(Double.self, forKey: .themeIntensity) ?? 0.72
        showAgentShelf = try container.decodeIfPresent(Bool.self, forKey: .showAgentShelf) ?? true
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

    func updateAgentShelfVisibility(_ isVisible: Bool) {
        current.showAgentShelf = isVisible
        save()
    }

    func updateHotkey(_ hotkey: FoundryHotkey) {
        current.hotkey = hotkey
        save()
    }

    func updateThemeIntensity(_ intensity: Double) {
        current.themeIntensity = intensity
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
