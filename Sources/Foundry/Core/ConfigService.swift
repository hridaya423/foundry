import Foundation

struct FoundryConfig: Codable, Equatable {
    var hotkey: FoundryHotkey = .commandSpace
    var themeIntensity: Double = 0.72
    var showAgentShelf: Bool = true
    var widgets: WidgetBoardConfig = .default
    var ai: AIConfig = .default

    init(hotkey: FoundryHotkey = .commandSpace, themeIntensity: Double = 0.72, showAgentShelf: Bool = true, widgets: WidgetBoardConfig = .default, ai: AIConfig = .default) {
        self.hotkey = hotkey
        self.themeIntensity = themeIntensity
        self.showAgentShelf = showAgentShelf
        self.widgets = widgets
        self.ai = ai
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
        ai = try container.decodeIfPresent(AIConfig.self, forKey: .ai) ?? .default
    }
}

struct AIConfig: Codable, Equatable {
    var preferredBackend: AIBackend = .appleFoundationModels
    var isOllamaEnabled: Bool = false
    var ollamaHost: String = "http://127.0.0.1:11434"
    var ollamaModel: String = "llama3.1"
    var openAIModel: String = "gpt-4.1-mini"
    var anthropicModel: String = "claude-3-5-sonnet-latest"
    var geminiModel: String = "gemini-2.0-flash"

    static let `default` = AIConfig()
}

enum AIBackend: String, Codable, CaseIterable, Identifiable {
    case ollama
    case appleFoundationModels
    case openAI
    case anthropic
    case gemini

    var id: String { rawValue }
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

    func updateAIConfig(_ ai: AIConfig) {
        current.ai = ai
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
