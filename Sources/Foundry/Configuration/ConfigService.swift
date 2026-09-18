import Foundation
import FoundryDomain
import FoundryServices

enum WindowMode: String, Codable, CaseIterable, Equatable {
    case standard
    case compact
}

struct FoundryConfig: Codable, Equatable {
    static let currentSchemaVersion = 8

    var schemaVersion = FoundryConfig.currentSchemaVersion
    var hotkey: FoundryHotkey = .optionSpace
    var themeIntensity: Double = 0.72
    var showAgentShelf: Bool = true
    var showMenuBarIcon: Bool = true
    var popToRootAfterSeconds: Double = 90
    var windowMode: WindowMode = .standard
    var widgets: WidgetBoardConfig = .default
    var ai: AIConfig = .default
    var searchSensitivity: SearchSensitivity = .medium
    var commandPreferences: [String: CommandPreference] = [:]
    var providerEnabled: [String: Bool] = [:]
    var clipboard: ClipboardConfig = .default
    var snippetExpansion: SnippetExpansionConfig = .default

    init(hotkey: FoundryHotkey = .optionSpace, themeIntensity: Double = 0.72, showAgentShelf: Bool = true, showMenuBarIcon: Bool = true, popToRootAfterSeconds: Double = 90, windowMode: WindowMode = .standard, widgets: WidgetBoardConfig = .default, ai: AIConfig = .default, searchSensitivity: SearchSensitivity = .medium, commandPreferences: [String: CommandPreference] = [:], providerEnabled: [String: Bool] = [:], clipboard: ClipboardConfig = .default, snippetExpansion: SnippetExpansionConfig = .default) {
        schemaVersion = Self.currentSchemaVersion
        self.hotkey = hotkey
        self.themeIntensity = themeIntensity
        self.showAgentShelf = showAgentShelf
        self.showMenuBarIcon = showMenuBarIcon
        self.popToRootAfterSeconds = popToRootAfterSeconds
        self.windowMode = windowMode
        self.widgets = widgets
        self.ai = ai
        self.searchSensitivity = searchSensitivity
        self.commandPreferences = commandPreferences
        self.providerEnabled = providerEnabled
        self.clipboard = clipboard.normalized
        self.snippetExpansion = snippetExpansion.normalized
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let savedSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard savedSchemaVersion <= Self.currentSchemaVersion else {
            throw FoundryConfigMigrationError.unsupportedVersion(savedSchemaVersion)
        }
        schemaVersion = Self.currentSchemaVersion
        let savedHotkey = try container.decodeIfPresent(FoundryHotkey.self, forKey: .hotkey)
        if let savedHotkey,
           savedHotkey.keyCode == FoundryHotkey.commandSpace.keyCode,
           savedHotkey.modifiers == FoundryHotkey.commandSpace.modifiers {
            hotkey = .commandSpace
        } else {
            hotkey = savedHotkey ?? (savedSchemaVersion < 7 ? .commandSpace : .optionSpace)
        }
        themeIntensity = try container.decodeIfPresent(Double.self, forKey: .themeIntensity) ?? 0.72
        showAgentShelf = try container.decodeIfPresent(Bool.self, forKey: .showAgentShelf) ?? true
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        popToRootAfterSeconds = try container.decodeIfPresent(Double.self, forKey: .popToRootAfterSeconds) ?? 90
        windowMode = try container.decodeIfPresent(WindowMode.self, forKey: .windowMode) ?? .standard
        widgets = try container.decodeIfPresent(WidgetBoardConfig.self, forKey: .widgets) ?? .default
        ai = try container.decodeIfPresent(AIConfig.self, forKey: .ai) ?? .default
        searchSensitivity = try container.decodeIfPresent(SearchSensitivity.self, forKey: .searchSensitivity) ?? .medium
        commandPreferences = try container.decodeIfPresent([String: CommandPreference].self, forKey: .commandPreferences) ?? [:]
        providerEnabled = try container.decodeIfPresent([String: Bool].self, forKey: .providerEnabled) ?? [:]
        var savedClipboard = (try container.decodeIfPresent(ClipboardConfig.self, forKey: .clipboard) ?? .default).normalized
        if savedSchemaVersion < 8,
           savedClipboard.maxItems == ClipboardConfig.legacyDefaultMaxItems,
           savedClipboard.maxBytes == ClipboardConfig.legacyDefaultMaxBytes {
            savedClipboard.maxItems = ClipboardConfig.defaultMaxItems
            savedClipboard.maxBytes = ClipboardConfig.defaultMaxBytes
        }
        clipboard = savedClipboard
        snippetExpansion = (try container.decodeIfPresent(SnippetExpansionConfig.self, forKey: .snippetExpansion) ?? .default).normalized
    }
}

struct ClipboardConfig: Codable, Equatable {
    static let legacyDefaultMaxItems = 40
    static let legacyDefaultMaxBytes = 16 * 1024 * 1024
    static let defaultMaxItems = 1_000
    static let defaultMaxBytes = 1_024 * 1_024 * 1_024
    static let minimumMaxItems = 1
    static let maximumMaxItems = 10_000
    static let minimumMaxBytes = 1 * 1024 * 1024
    static let maximumMaxBytes = 4 * 1_024 * 1_024 * 1_024
    static let defaultMaxAgeDays = 90
    static let minimumMaxAgeDays = 1
    static let maximumMaxAgeDays = 3_650

    var isEnabled = true
    var isPaused = false
    var maxItems = defaultMaxItems
    var maxBytes = defaultMaxBytes
    var maxAgeDays = defaultMaxAgeDays
    var excludedBundleIdentifiers: [String] = []

    static let `default` = ClipboardConfig()

    var normalized: ClipboardConfig {
        var value = self
        value.maxItems = min(max(maxItems, Self.minimumMaxItems), Self.maximumMaxItems)
        value.maxBytes = min(max(maxBytes, Self.minimumMaxBytes), Self.maximumMaxBytes)
        value.maxAgeDays = min(max(maxAgeDays, Self.minimumMaxAgeDays), Self.maximumMaxAgeDays)
        value.excludedBundleIdentifiers = Self.normalizeBundleIdentifiers(excludedBundleIdentifiers)
        return value
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        maxItems = try container.decodeIfPresent(Int.self, forKey: .maxItems) ?? Self.defaultMaxItems
        maxBytes = try container.decodeIfPresent(Int.self, forKey: .maxBytes) ?? Self.defaultMaxBytes
        maxAgeDays = try container.decodeIfPresent(Int.self, forKey: .maxAgeDays) ?? Self.defaultMaxAgeDays
        excludedBundleIdentifiers = try container.decodeIfPresent([String].self, forKey: .excludedBundleIdentifiers) ?? []
        self = normalized
    }

    fileprivate static func normalizeBundleIdentifiers(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        return identifiers.compactMap { identifier in
            let value = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.isEmpty == false, seen.insert(value).inserted else { return nil }
            return value
        }
    }
}

struct SnippetExpansionConfig: Codable, Equatable {
    var isEnabled = false
    var excludedBundleIdentifiers: [String] = []

    static let `default` = SnippetExpansionConfig()

    var normalized: SnippetExpansionConfig {
        var value = self
        value.excludedBundleIdentifiers = ClipboardConfig.normalizeBundleIdentifiers(excludedBundleIdentifiers)
        return value
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        excludedBundleIdentifiers = try container.decodeIfPresent([String].self, forKey: .excludedBundleIdentifiers) ?? []
        self = normalized
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
    var profiles: [AIProviderProfile] = [AIProviderProfile.appleDefault, AIProviderProfile.ollamaDefault]
    var defaultProfileID: UUID? = AIProviderProfile.appleID
    var fallbackProfileIDs: [UUID] = []
    var acceptedCodexPrivateBackendWarning = false
    var codexLoginMethod: OpenAICodexLoginMethod = .browser

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
        if let savedProfiles = try container.decodeIfPresent([AIProviderProfile].self, forKey: .profiles), savedProfiles.isEmpty == false {
            profiles = savedProfiles
        } else {
            var legacyOllama = AIProviderProfile.ollamaDefault
            legacyOllama.enabled = isOllamaEnabled
            legacyOllama.endpoint = ollamaHost
            legacyOllama.model = ollamaModel
            profiles = [AIProviderProfile.appleDefault, legacyOllama]
        }
        profiles = profiles.map { profile in
            guard profile.kind == .openAISubscription else { return profile }
            var migrated = profile
            if CodexModelPolicy.contains(migrated.model) == false {
                migrated.model = CodexModelPolicy.defaultModel
            }
            if migrated.requestOptions.reasoningEffort == nil {
                migrated.requestOptions.reasoningEffort = AIRequestOptions.codexDefault.reasoningEffort
            }
            return migrated
        }
        defaultProfileID = try container.decodeIfPresent(UUID.self, forKey: .defaultProfileID)
            ?? profiles.first(where: { $0.kind == .appleFoundationModels })?.id
        let savedFallbackProfileIDs = try container.decodeIfPresent([UUID].self, forKey: .fallbackProfileIDs) ?? []
        fallbackProfileIDs = savedFallbackProfileIDs.filter { id in
            profiles.first(where: { $0.id == id })?.kind != .ollama
        }
        acceptedCodexPrivateBackendWarning = try container.decodeIfPresent(Bool.self, forKey: .acceptedCodexPrivateBackendWarning) ?? false
        codexLoginMethod = try container.decodeIfPresent(OpenAICodexLoginMethod.self, forKey: .codexLoginMethod) ?? .browser
        if let index = profiles.firstIndex(where: { $0.kind == .ollama }) {
            isOllamaEnabled = profiles[index].enabled
            ollamaHost = profiles[index].endpoint ?? ollamaHost
            ollamaModel = profiles[index].model
        }
    }

    func profile(for backend: AIBackend) -> AIProviderProfile {
        AIProfileResolver.profile(for: backend, in: self)
    }

    mutating func syncProfilesFromLegacyFields() {
        guard let index = profiles.firstIndex(where: { $0.kind == .ollama }) else { return }
        profiles[index].enabled = isOllamaEnabled
        profiles[index].endpoint = ollamaHost
        profiles[index].model = ollamaModel
    }

    static func == (lhs: AIConfig, rhs: AIConfig) -> Bool {
        var left = lhs
        var right = rhs
        left.syncProfilesFromLegacyFields()
        right.syncProfilesFromLegacyFields()
        return left.preferredBackend == right.preferredBackend
            && left.isOllamaEnabled == right.isOllamaEnabled
            && left.ollamaHost == right.ollamaHost
            && left.ollamaModel == right.ollamaModel
            && left.openAIModel == right.openAIModel
            && left.anthropicModel == right.anthropicModel
            && left.geminiModel == right.geminiModel
            && left.profiles == right.profiles
            && left.defaultProfileID == right.defaultProfileID
            && left.fallbackProfileIDs == right.fallbackProfileIDs
            && left.acceptedCodexPrivateBackendWarning == right.acceptedCodexPrivateBackendWarning
            && left.codexLoginMethod == right.codexLoginMethod
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

final class ConfigService: @unchecked Sendable {
    private let diagnostics: DiagnosticsService
    private let url: URL
    private let lock = NSLock()
    private var storedCurrent: FoundryConfig
    private var loadError: String?

    var current: FoundryConfig {
        lock.withLock { storedCurrent }
    }

    var loadErrorMessage: String? {
        lock.withLock { loadError }
    }

    private(set) var existedAtLaunch = false

    init(diagnostics: DiagnosticsService, url: URL = ConfigService.configURL) {
        self.diagnostics = diagnostics
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            existedAtLaunch = true
            do {
                let data = try Data(contentsOf: url)
                self.storedCurrent = try FoundryConfigMigration.migrate(data)
                self.loadError = nil
            } catch {
                self.storedCurrent = FoundryConfig()
                self.loadError = error.localizedDescription
                diagnostics.log("Could not load config at \(url.path): \(error.localizedDescription)")
            }
        } else {
            self.storedCurrent = FoundryConfig()
            self.loadError = nil
        }
    }

    static var configURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/foundry/config.json")
    }

    func updateWidgets(_ widgets: WidgetBoardConfig, showAgentShelf: Bool? = nil) throws {
        try update { candidate in
            candidate.widgets = widgets
            if let showAgentShelf {
                candidate.showAgentShelf = showAgentShelf
            }
        }
    }

    func updateAgentShelfVisibility(_ isVisible: Bool) throws {
        try update { $0.showAgentShelf = isVisible }
    }

    func updateMenuBarIconVisibility(_ isVisible: Bool) throws {
        try update { $0.showMenuBarIcon = isVisible }
    }

    func updateHotkey(_ hotkey: FoundryHotkey) throws {
        try update { $0.hotkey = hotkey }
    }

    func updateThemeIntensity(_ intensity: Double) throws {
        try update { $0.themeIntensity = intensity }
    }

    func updatePopToRootAfter(_ seconds: Double) throws {
        try update { $0.popToRootAfterSeconds = seconds }
    }

    func updateWindowMode(_ mode: WindowMode) throws {
        try update { $0.windowMode = mode }
    }

    func updateAIConfig(_ ai: AIConfig) throws {
        try update { candidate in
            var normalized = ai
            normalized.syncProfilesFromLegacyFields()
            candidate.ai = normalized
        }
    }

    func updateAIProfile(_ profile: AIProviderProfile) throws {
        try update { candidate in
            if let index = candidate.ai.profiles.firstIndex(where: { $0.id == profile.id }) {
                candidate.ai.profiles[index] = profile
            } else {
                candidate.ai.profiles.append(profile)
            }
            if profile.kind == .ollama {
                candidate.ai.isOllamaEnabled = profile.enabled
                candidate.ai.ollamaHost = profile.endpoint ?? candidate.ai.ollamaHost
                candidate.ai.ollamaModel = profile.model
            }
        }
    }

    func removeAIProfile(id: UUID) throws {
        try update { candidate in
            guard candidate.ai.profiles.contains(where: { $0.id == id }) else { return }
            candidate.ai.profiles.removeAll { $0.id == id }
            candidate.ai.fallbackProfileIDs.removeAll { $0 == id }
            if candidate.ai.defaultProfileID == id {
                candidate.ai.defaultProfileID = candidate.ai.profiles.first(where: { $0.enabled })?.id
            }
        }
    }

    func setDefaultAIProfile(id: UUID?) throws {
        try update { candidate in
            guard id == nil || candidate.ai.profiles.contains(where: { $0.id == id }) else { return }
            candidate.ai.defaultProfileID = id
        }
    }

    func setAIFallbackProfiles(_ ids: [UUID]) throws {
        try update { candidate in
            let available = Set(candidate.ai.profiles.map(\.id))
            candidate.ai.fallbackProfileIDs = ids.filter { available.contains($0) }
        }
    }

    func updateSearchSensitivity(_ sensitivity: SearchSensitivity) throws {
        try update { $0.searchSensitivity = sensitivity }
    }

    func updateCommandPreference(_ preference: CommandPreference, for commandID: String) throws {
        let normalizedID = commandID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedID.isEmpty == false else { return }
        try update { $0.commandPreferences[normalizedID] = preference }
    }

    func updateProviderEnabled(_ isEnabled: Bool, for providerID: String) throws {
        let normalizedID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedID.isEmpty == false else { return }
        try update { $0.providerEnabled[normalizedID] = isEnabled }
    }

    func updateClipboardConfig(_ clipboard: ClipboardConfig) throws {
        try update { $0.clipboard = clipboard.normalized }
    }

    func updateSnippetExpansionConfig(_ snippetExpansion: SnippetExpansionConfig) throws {
        try update { $0.snippetExpansion = snippetExpansion.normalized }
    }

    func resetToDefaults() throws {
        let defaults = FoundryConfig()
        try write(defaults)
    }

    private func update(_ mutate: (inout FoundryConfig) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        if let loadError {
            throw ConfigServiceError.readOnly(loadError)
        }

        var candidate = storedCurrent
        mutate(&candidate)
        try writeLocked(candidate)
    }

    private func write(_ candidate: FoundryConfig) throws {
        lock.lock()
        defer { lock.unlock() }
        try writeLocked(candidate)
    }

    private func writeLocked(_ candidate: FoundryConfig) throws {

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(candidate)
            try data.write(to: url, options: .atomic)
            storedCurrent = candidate
            loadError = nil
            diagnostics.log("Saved config to \(url.path)")
        } catch {
            diagnostics.log("Failed to save config: \(error.localizedDescription)")
            throw error
        }
    }
}

enum ConfigServiceError: LocalizedError, Equatable {
    case readOnly(String)

    var errorDescription: String? {
        switch self {
        case let .readOnly(reason):
            "Foundry settings are read-only until the incompatible configuration is reset: \(reason)"
        }
    }
}

enum FoundryConfigMigrationError: LocalizedError, Equatable {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            "Config schema version \(version) is newer than this build supports"
        }
    }
}

enum FoundryConfigMigration {
    static func migrate(_ data: Data) throws -> FoundryConfig {
        try JSONDecoder().decode(FoundryConfig.self, from: data)
    }

    static func sourceVersion(in data: Data) -> Int {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["schemaVersion"] as? Int else {
            return 1
        }
        return version
    }
}
