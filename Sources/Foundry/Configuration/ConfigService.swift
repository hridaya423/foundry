import Foundation
import os
import FoundryDomain
import FoundryServices

enum WindowMode: String, Codable, CaseIterable, Equatable {
    case standard
    case compact
}

struct FoundryConfig: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 8

    var schemaVersion = FoundryConfig.currentSchemaVersion
    var hotkey: FoundryHotkey = .commandSpace
    var themeIntensity: Double = 0.72
    var showAgentShelf: Bool = true
    var showMenuBarIcon: Bool = true
    var hapticsEnabled: Bool = true
    var popToRootAfterSeconds: Double = 90
    var windowMode: WindowMode = .standard
    var widgets: WidgetBoardConfig = .default
    var ai: AIConfig = .default
    var searchSensitivity: SearchSensitivity = .medium
    var commandPreferences: [String: CommandPreference] = [:]
    var providerEnabled: [String: Bool] = [:]
    var clipboard: ClipboardConfig = .default
    var snippetExpansion: SnippetExpansionConfig = .default
    var fallbacks: FallbackConfig = .default
    var fileSearch: FileSearchConfig = .default
    var quicklinkSiteIcons = true
    var localState = FoundryLocalState()

    init(
        hotkey: FoundryHotkey = .commandSpace,
        themeIntensity: Double = 0.72,
        showAgentShelf: Bool = true,
        showMenuBarIcon: Bool = true,
        hapticsEnabled: Bool = true,
        popToRootAfterSeconds: Double = 90,
        windowMode: WindowMode = .standard,
        widgets: WidgetBoardConfig = .default,
        ai: AIConfig = .default,
        searchSensitivity: SearchSensitivity = .medium,
        commandPreferences: [String: CommandPreference] = [:],
        providerEnabled: [String: Bool] = [:],
        clipboard: ClipboardConfig = .default,
        snippetExpansion: SnippetExpansionConfig = .default,
        localState: FoundryLocalState = FoundryLocalState()
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.hotkey = hotkey
        self.themeIntensity = themeIntensity
        self.showAgentShelf = showAgentShelf
        self.showMenuBarIcon = showMenuBarIcon
        self.hapticsEnabled = hapticsEnabled
        self.popToRootAfterSeconds = popToRootAfterSeconds
        self.windowMode = windowMode
        self.widgets = widgets
        self.ai = ai
        self.searchSensitivity = searchSensitivity
        self.commandPreferences = commandPreferences
        self.providerEnabled = providerEnabled
        self.clipboard = clipboard.normalized
        self.snippetExpansion = snippetExpansion.normalized
        self.localState = localState
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
            hotkey = savedHotkey ?? .commandSpace
        }
        themeIntensity = try container.decodeIfPresent(Double.self, forKey: .themeIntensity) ?? 0.72
        showAgentShelf = try container.decodeIfPresent(Bool.self, forKey: .showAgentShelf) ?? true
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
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
        fallbacks = try container.decodeIfPresent(FallbackConfig.self, forKey: .fallbacks) ?? .default
        fileSearch = try container.decodeIfPresent(FileSearchConfig.self, forKey: .fileSearch) ?? .default
        quicklinkSiteIcons = try container.decodeIfPresent(Bool.self, forKey: .quicklinkSiteIcons) ?? true
        localState = try container.decodeIfPresent(FoundryLocalState.self, forKey: .localState) ?? FoundryLocalState()
    }
}

/// Machine-local preferences that used to live in scattered UserDefaults
/// keys — remembered panel choices, consent flags, and small feature
/// histories. Kept on FoundryConfig so the debounced writer, backup, and
/// restore cover them for free. Every field decodes with a default so the
/// section can grow without a schema bump.
struct FoundryLocalState: Codable, Equatable, Sendable {
    var mainBrowser: String?
    var preferredCurrencyQuote: String?
    var launchAtLoginConsent = false
    var colorPickerRecents: [String] = []
    var mediaDownloadFolder: String?
    var snippetsLastExportDirectory: String?
    var conversionFirstSuccessCelebrated = false
    var firefoxConnectorPromptShown = false
    var onboardingCompletedVersion: String?
    var onboardingStep: Int?
    var accessibilityPrompted = false
    var screenRecordingPrompted = false
    var launchCount = 0
    var tipShownDay: String?
    var tipShownID: String?
    var tipsDismissed: [String] = []
    var loginNudgeDismissed = false
    var firstRunHintShown = false
    var firstLaunchAcknowledged = false
    var whatsNewSeenVersion: String?
    var emojiRecents: [String] = []
    var emojiColumns: Int?
    var emojiSkinTone = ""
    var scriptDirectories: [String]?
    var trustedScriptDirectories: [String] = []
    var calculatorHistory: [[String]] = []

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mainBrowser = try container.decodeIfPresent(String.self, forKey: .mainBrowser)
        preferredCurrencyQuote = try container.decodeIfPresent(String.self, forKey: .preferredCurrencyQuote)
        launchAtLoginConsent = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginConsent) ?? false
        colorPickerRecents = try container.decodeIfPresent([String].self, forKey: .colorPickerRecents) ?? []
        mediaDownloadFolder = try container.decodeIfPresent(String.self, forKey: .mediaDownloadFolder)
        snippetsLastExportDirectory = try container.decodeIfPresent(String.self, forKey: .snippetsLastExportDirectory)
        conversionFirstSuccessCelebrated = try container.decodeIfPresent(Bool.self, forKey: .conversionFirstSuccessCelebrated) ?? false
        firefoxConnectorPromptShown = try container.decodeIfPresent(Bool.self, forKey: .firefoxConnectorPromptShown) ?? false
        onboardingCompletedVersion = try container.decodeIfPresent(String.self, forKey: .onboardingCompletedVersion)
        onboardingStep = try container.decodeIfPresent(Int.self, forKey: .onboardingStep)
        accessibilityPrompted = try container.decodeIfPresent(Bool.self, forKey: .accessibilityPrompted) ?? false
        screenRecordingPrompted = try container.decodeIfPresent(Bool.self, forKey: .screenRecordingPrompted) ?? false
        launchCount = try container.decodeIfPresent(Int.self, forKey: .launchCount) ?? 0
        tipShownDay = try container.decodeIfPresent(String.self, forKey: .tipShownDay)
        tipShownID = try container.decodeIfPresent(String.self, forKey: .tipShownID)
        tipsDismissed = try container.decodeIfPresent([String].self, forKey: .tipsDismissed) ?? []
        loginNudgeDismissed = try container.decodeIfPresent(Bool.self, forKey: .loginNudgeDismissed) ?? false
        firstRunHintShown = try container.decodeIfPresent(Bool.self, forKey: .firstRunHintShown) ?? false
        firstLaunchAcknowledged = try container.decodeIfPresent(Bool.self, forKey: .firstLaunchAcknowledged) ?? false
        whatsNewSeenVersion = try container.decodeIfPresent(String.self, forKey: .whatsNewSeenVersion)
        emojiRecents = try container.decodeIfPresent([String].self, forKey: .emojiRecents) ?? []
        emojiColumns = try container.decodeIfPresent(Int.self, forKey: .emojiColumns)
        emojiSkinTone = try container.decodeIfPresent(String.self, forKey: .emojiSkinTone) ?? ""
        scriptDirectories = try container.decodeIfPresent([String].self, forKey: .scriptDirectories)
        trustedScriptDirectories = try container.decodeIfPresent([String].self, forKey: .trustedScriptDirectories) ?? []
        calculatorHistory = try container.decodeIfPresent([[String]].self, forKey: .calculatorHistory) ?? []
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
    var delimiters: [String] = Self.defaultDelimiters
    var insertAsPrimary = true

    static let `default` = SnippetExpansionConfig()
    static let defaultDelimiters: [String] = [" ", "\n", "\r", "\t", "'", "\"", "`"]

    var normalized: SnippetExpansionConfig {
        var value = self
        value.excludedBundleIdentifiers = ClipboardConfig.normalizeBundleIdentifiers(excludedBundleIdentifiers)
        var seen = Set<String>()
        value.delimiters = delimiters.filter { delimiter in
            guard delimiter.isEmpty == false, delimiter.count <= 4, seen.contains(delimiter) == false else { return false }
            seen.insert(delimiter)
            return true
        }
        return value
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        excludedBundleIdentifiers = try container.decodeIfPresent([String].self, forKey: .excludedBundleIdentifiers) ?? []
        delimiters = try container.decodeIfPresent([String].self, forKey: .delimiters) ?? Self.defaultDelimiters
        insertAsPrimary = try container.decodeIfPresent(Bool.self, forKey: .insertAsPrimary) ?? true
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

final class ConfigService: Sendable {
    private struct State {
        var current: FoundryConfig
        var loadError: String?
        var pendingPersist: DispatchWorkItem?
        var pendingSnapshot: FoundryConfig?
        var persistedWriteCount = 0
    }

    private let diagnostics: DiagnosticsService
    private let url: URL
    private let state: OSAllocatedUnfairLock<State>
    private let persistDebounce: TimeInterval
    private let persistQueue = DispatchQueue(label: "foundry.config.persist", qos: .utility)

    var current: FoundryConfig {
        state.withLockUnchecked { $0.current }
    }

    var loadErrorMessage: String? {
        state.withLockUnchecked { $0.loadError }
    }

    let existedAtLaunch: Bool

    /// Disk writes performed so far — surfaced for tests and diagnostics.
    var persistedWriteCount: Int { state.withLockUnchecked { $0.persistedWriteCount } }

    init(
        diagnostics: DiagnosticsService,
        url: URL = ConfigService.configURL,
        persistDebounce: TimeInterval = 0.3,
        legacyDefaults: UserDefaults? = .standard
    ) {
        self.diagnostics = diagnostics
        self.url = url
        self.persistDebounce = persistDebounce
        var current = FoundryConfig()
        var loadError: String?
        existedAtLaunch = FileManager.default.fileExists(atPath: url.path)
        if existedAtLaunch {
            do {
                let data = try Data(contentsOf: url)
                current = try FoundryConfigMigration.migrate(data)
            } catch {
                loadError = error.localizedDescription
                diagnostics.log("Could not load config at \(url.path): \(error.localizedDescription)")
            }
        }
        var migrated = false
        if loadError == nil, let legacyDefaults {
            migrated = UserDefaultsMigration.apply(to: &current.localState, defaults: legacyDefaults)
        }
        self.state = OSAllocatedUnfairLock(uncheckedState: State(current: current, loadError: loadError))
        if migrated {
            schedulePersist(current)
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

    func updateHapticsEnabled(_ enabled: Bool) throws {
        try update { $0.hapticsEnabled = enabled }
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

    func updateFallbacks(_ fallbacks: FallbackConfig) throws {
        try update { $0.fallbacks = fallbacks }
    }

    func updateFileSearch(_ fileSearch: FileSearchConfig) throws {
        try update { $0.fileSearch = fileSearch }
    }

    func updateQuicklinkSiteIcons(_ enabled: Bool) throws {
        try update { $0.quicklinkSiteIcons = enabled }
    }

    func updateLocalState(_ mutate: (inout FoundryLocalState) -> Void) throws {
        try update { mutate(&$0.localState) }
    }

    /// Re-reads config.json after a wholesale replace (backup restore) —
    /// replaces the in-memory snapshot, drops any pending write, and clears
    /// a stale read-only state from a previously unreadable file.
    func reload() throws {
        let data = try Data(contentsOf: url)
        let loaded = try FoundryConfigMigration.migrate(data)
        state.withLockUnchecked {
            $0.pendingPersist?.cancel()
            $0.pendingPersist = nil
            $0.pendingSnapshot = nil
            $0.current = loaded
            $0.loadError = nil
        }
    }

    func resetToDefaults() throws {
        let defaults = FoundryConfig()
        try write(defaults)
        flush()
    }

    private func update(_ mutate: (inout FoundryConfig) -> Void) throws {
        try state.withLockUnchecked { state in
            if let loadError = state.loadError {
                throw ConfigServiceError.readOnly(loadError)
            }

            var candidate = state.current
            mutate(&candidate)
            state.current = candidate
            state.loadError = nil
            schedulePersist(candidate, in: &state)
        }
    }

    private func write(_ candidate: FoundryConfig) throws {
        state.withLockUnchecked { state in
            state.current = candidate
            state.loadError = nil
            schedulePersist(candidate, in: &state)
        }
    }

    /// Mutations apply in memory synchronously; disk I/O is debounced so a
    /// slider drag or a burst of toggles costs one write, not one per tick.
    private func schedulePersist(_ candidate: FoundryConfig, in state: inout State) {
        state.pendingSnapshot = candidate
        state.pendingPersist?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistPending() }
        state.pendingPersist = work
        persistQueue.asyncAfter(deadline: .now() + persistDebounce, execute: work)
    }

    private func schedulePersist(_ candidate: FoundryConfig) {
        state.withLockUnchecked { schedulePersist(candidate, in: &$0) }
    }

    private func persistPending() {
        let snapshot = state.withLockUnchecked { $0.pendingSnapshot }
        guard let snapshot else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
            state.withLockUnchecked {
                if $0.pendingSnapshot == snapshot { $0.pendingSnapshot = nil }
                if $0.pendingPersist?.isCancelled == false { $0.pendingPersist = nil }
                $0.persistedWriteCount += 1
            }
            diagnostics.log("Saved config to \(url.path)")
        } catch {
            diagnostics.log("Failed to save config: \(error.localizedDescription)")
        }
    }

    /// Write any pending snapshot synchronously — termination, tests, and
    /// anywhere the next reader is a fresh process.
    func flush() {
        state.withLockUnchecked { $0.pendingPersist?.cancel(); $0.pendingPersist = nil }
        persistPending()
    }

    /// Drop a scheduled write without persisting — backup restore replaces
    /// the file wholesale, so a stale in-memory snapshot must not land after.
    func discardPending() {
        state.withLockUnchecked {
            $0.pendingPersist?.cancel()
            $0.pendingPersist = nil
            $0.pendingSnapshot = nil
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

/// One-shot import of the UserDefaults keys `FoundryLocalState` replaced.
/// Runs inside ConfigService.init — the only place Sources may touch
/// UserDefaults.standard for app state. Each key is removed as it lands so
/// the import can't run twice or resurrect deleted values.
enum UserDefaultsMigration {
    @discardableResult
    static func apply(to state: inout FoundryLocalState, defaults: UserDefaults) -> Bool {
        var migrated = false
        func move<Value>(_ key: String, _ read: (UserDefaults, String) -> Value?, assign: (inout FoundryLocalState, Value) -> Void) {
            guard let value = read(defaults, key) else { return }
            assign(&state, value)
            defaults.removeObject(forKey: key)
            migrated = true
        }
        move("foundry.mainBrowser", { $0.string(forKey: $1) }) { $0.mainBrowser = $1 }
        move("preferredCurrencyQuote", { $0.string(forKey: $1) }) { $0.preferredCurrencyQuote = $1 }
        move("foundry.launchAtLoginConsent", { $0.object(forKey: $1) as? Bool }) { $0.launchAtLoginConsent = $1 }
        move("colorPicker.recents", { $0.stringArray(forKey: $1) }) { $0.colorPickerRecents = $1 }
        move("mediaDownloadFolder", { $0.string(forKey: $1) }) { $0.mediaDownloadFolder = $1 }
        move("snippets.lastExportDirectory", { $0.string(forKey: $1) }) { $0.snippetsLastExportDirectory = $1 }
        move("conversion.firstSuccessCelebrated", { $0.object(forKey: $1) as? Bool }) { $0.conversionFirstSuccessCelebrated = $1 }
        move("foundry.firefox.connector.promptShown", { $0.object(forKey: $1) as? Bool }) { $0.firefoxConnectorPromptShown = $1 }
        move(OnboardingState.completedVersionKey, { $0.string(forKey: $1) }) { $0.onboardingCompletedVersion = $1 }
        move(OnboardingState.stepKey, { $0.object(forKey: $1) as? Int }) { $0.onboardingStep = $1 }
        move("emoji.recents", { $0.stringArray(forKey: $1) }) { $0.emojiRecents = $1 }
        move("emoji.columns", { $0.object(forKey: $1) as? Int }) { $0.emojiColumns = $1 }
        move("emoji.skinTone", { $0.string(forKey: $1) }) { $0.emojiSkinTone = $1 }
        move("foundry.scripts.directories", { $0.stringArray(forKey: $1) }) { $0.scriptDirectories = $1 }
        move("foundry.scripts.trusted", { $0.stringArray(forKey: $1) }) { $0.trustedScriptDirectories = $1 }
        move("foundry.calculator.history", { $0.array(forKey: $1) as? [[String]] }) { $0.calculatorHistory = $1 }
        return migrated
    }
}

enum FoundryConfigMigration {
    static func migrate(_ data: Data) throws -> FoundryConfig {
        try JSONDecoder().decode(FoundryConfig.self, from: data)
    }

    static func sourceVersion(in data: Data) -> Int {
        let raw = BestEffort.attempt("read config schema version") {
            try JSONSerialization.jsonObject(with: data)
        }
        guard let object = raw as? [String: Any],
              let version = object["schemaVersion"] as? Int else {
            return 1
        }
        return version
    }
}
