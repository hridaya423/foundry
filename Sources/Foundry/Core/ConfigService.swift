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

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferredBackend = try container.decodeIfPresent(AIBackend.self, forKey: .preferredBackend) ?? .appleFoundationModels
        isOllamaEnabled = try container.decodeIfPresent(Bool.self, forKey: .isOllamaEnabled) ?? false
        ollamaHost = try container.decodeIfPresent(String.self, forKey: .ollamaHost) ?? "http://127.0.0.1:11434"
        ollamaModel = try container.decodeIfPresent(String.self, forKey: .ollamaModel) ?? "llama3.1"
        openAIModel = try container.decodeIfPresent(String.self, forKey: .openAIModel) ?? "gpt-4.1-mini"
        anthropicModel = try container.decodeIfPresent(String.self, forKey: .anthropicModel) ?? "claude-3-5-sonnet-latest"
        geminiModel = try container.decodeIfPresent(String.self, forKey: .geminiModel) ?? "gemini-2.0-flash"
    }
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
    private let url: URL
    private(set) var current: FoundryConfig

    init(diagnostics: DiagnosticsService, url: URL = ConfigService.configURL) {
        self.diagnostics = diagnostics
        self.url = url
        self.current = Self.load(from: url) ?? FoundryConfig()
    }

    static var configURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/foundry/config.json")
    }

    func updateWidgets(_ widgets: WidgetBoardConfig, showAgentShelf: Bool? = nil) throws {
        var candidate = current
        candidate.widgets = widgets
        if let showAgentShelf {
            candidate.showAgentShelf = showAgentShelf
        }
        try commit(candidate)
    }

    func updateAgentShelfVisibility(_ isVisible: Bool) throws {
        var candidate = current
        candidate.showAgentShelf = isVisible
        try commit(candidate)
    }

    func updateHotkey(_ hotkey: FoundryHotkey) throws {
        var candidate = current
        candidate.hotkey = hotkey
        try commit(candidate)
    }

    func updateThemeIntensity(_ intensity: Double) throws {
        var candidate = current
        candidate.themeIntensity = intensity
        try commit(candidate)
    }

    func updateAIConfig(_ ai: AIConfig) throws {
        var candidate = current
        candidate.ai = ai
        try commit(candidate)
    }

    func save() throws {
        try commit(current)
    }

    private func commit(_ candidate: FoundryConfig) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(candidate)
            try data.write(to: url, options: .atomic)
            current = candidate
            diagnostics.log("Saved config to \(url.path)")
        } catch {
            diagnostics.log("Failed to save config: \(error.localizedDescription)")
            throw error
        }
    }

    private static func load(from url: URL) -> FoundryConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FoundryConfig.self, from: data)
    }
}
