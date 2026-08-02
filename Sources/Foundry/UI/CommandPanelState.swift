import AppKit
import Foundation
import SwiftUI

@MainActor
final class CommandPanelState: ObservableObject {
    enum Mode {
        case search
        case quickAI
        case activityMonitor
        case emojiPicker
        case fileShelf
        case clipboardHistory
        case snippets
        case fileConversion
        case camera
        case translator
        case developerTools
        case agents
        case settings
        case dashboard
    }

    @Published var query = "" {
        didSet { refreshResults() }
    }
    @Published var quickAIQuery = ""
    @Published var quickAIResponse = ""
    @Published var quickAIStatus = ""
    @Published var isQuickAILoading = false
    @Published var quickAILastFailedPrompt: String?
    @Published var quickAIThreads: [AIChatThread]
    @Published var activeQuickAIThreadID: UUID?
    @Published var results: [CommandResult] = []
    @Published var selectedResultID: String?
    @Published private(set) var selectionScrollToken = UUID()
    @Published var isShowingActions = false
    @Published var selectedActionID: String?
    @Published var diagnosticsSummary = "IDLE"
    @Published var mode: Mode = .search
    @Published var focusToken = UUID()
    @Published var hoverHighlightsArmed = true
    @Published private(set) var actionFeedback: ActionFeedback? = nil
    @Published var isAgentShelfVisible: Bool
    @Published var hotkey: FoundryHotkey
    @Published var hotkeyError: String? = nil
    @Published var themeIntensity: Double
    @Published var searchSensitivity: SearchSensitivity
    @Published var isOllamaEnabled: Bool
    @Published var ollamaHost: String
    @Published var ollamaModel: String
    @Published var ollamaHostError: String?
    @Published var ollamaModelError: String?
    @Published var aiProfiles: [AIProviderProfile]
    @Published var defaultAIProfileID: UUID?
    @Published var fallbackAIProfileIDs: [UUID]
    @Published var selectedAIProfileID: UUID?
    @Published var aiCredentialInput = ""
    @Published var aiProfileStatus: String?
    @Published var aiProfileTestingID: UUID?
    @Published var aiAvailableModels: [AIModel] = []
    @Published var aiModelsLoading = false
    @Published var codexLoginState: CodexLoginState
    @Published var codexDeviceAuthorization: OpenAIDeviceAuthorization?
    @Published var acceptedCodexPrivateBackendWarning: Bool
    @Published var settingsPersistenceError: String?
    @Published var commandSettingsQuery = "" {
        didSet { rebuildCommandRows() }
    }
    @Published private(set) var commandDescriptors: [CommandDescriptor] = []
    @Published private(set) var commandPreferences: [String: CommandPreference]
    @Published private(set) var commandRows: [CommandSettingsRowModel] = []
    @Published private(set) var visibleCommandRows: [CommandSettingsRowModel] = []
    @Published private(set) var isCommandCatalogLoading = false
    @Published private(set) var isCommandCatalogReady = false
    @Published var expandedCommandID: String?
    var onHotkeyChanged: ((FoundryHotkey) throws -> Void)?

    let activityMonitor = ActivityMonitorState()
    let emojiPicker = EmojiPickerState()
    let fileShelf = FileShelfState()
    let agents = AgentMonitorState()
    let clipboardHistory = ClipboardHistoryState()
    let snippets = SnippetState()
    let fileConversion = FileConversionState()
    let camera = CameraPreviewState()
    let translator = TranslatorState()
    let developerTools = DeveloperToolsState()
    let widgetBoard: WidgetBoardState
    private let configService: ConfigService

    private let registry: CommandRegistry
    private let actionRunner: ActionRunner
    private let diagnostics: DiagnosticsService
    private let aiProvider: AIProvider
    private let aiChatStore = AIChatStore()
    private let aiCredentialStore: AICredentialStore
    private let codexOAuthService: OpenAICodexOAuthService
    private var statusTimer: Timer?
    private var searchTask: Task<Void, Never>?
    private var quickAITask: Task<Void, Never>?
    private var quickAIRequestID: UUID?
    private var searchGeneration = 0
    private var isMediaDownloadActive = false
    private var feedbackTask: Task<Void, Never>?
    private var commandCatalogTask: Task<Void, Never>?
    private var aiProfileTestTask: Task<Void, Never>?
    private var aiModelTask: Task<Void, Never>?
    private var codexOAuthTask: Task<Void, Never>?

    var selectedResult: CommandResult? {
        results.first { $0.id == selectedResultID }
    }

    var selectedActions: [CommandAction] {
        guard let selectedResult else { return [] }
        return [selectedResult.primaryAction]
            + selectedResult.secondaryActions
            + [CommandAction(
                id: "ranking.reset.\(selectedResult.id)",
                title: "Reset Ranking",
                kind: .resetRanking(commandID: selectedResult.id)
            )]
    }

    var selectedAction: CommandAction? {
        selectedActions.first { $0.id == selectedActionID }
    }

    init(registry: CommandRegistry, actionRunner: ActionRunner, diagnostics: DiagnosticsService, config: ConfigService) {
        self.registry = registry
        self.actionRunner = actionRunner
        self.diagnostics = diagnostics
        self.configService = config
        self.aiProvider = AIProvider(config: config, diagnostics: diagnostics)
        self.aiCredentialStore = KeychainAICredentialStore()
        self.codexOAuthService = .shared
        let loadedThreads = aiChatStore.load()
        self.quickAIThreads = loadedThreads
        self.activeQuickAIThreadID = loadedThreads.first?.id
        self.isAgentShelfVisible = config.current.showAgentShelf
        self.hotkey = config.current.hotkey
        self.themeIntensity = config.current.themeIntensity
        self.searchSensitivity = config.current.searchSensitivity
        self.isOllamaEnabled = config.current.ai.isOllamaEnabled
        self.ollamaHost = config.current.ai.ollamaHost
        self.ollamaModel = config.current.ai.ollamaModel
        self.ollamaHostError = nil
        self.ollamaModelError = nil
        self.aiProfiles = config.current.ai.profiles
        self.defaultAIProfileID = config.current.ai.defaultProfileID
        self.fallbackAIProfileIDs = config.current.ai.fallbackProfileIDs
        self.selectedAIProfileID = config.current.ai.defaultProfileID ?? config.current.ai.profiles.first?.id
        self.codexLoginState = .disconnected
        self.codexDeviceAuthorization = nil
        self.acceptedCodexPrivateBackendWarning = config.current.ai.acceptedCodexPrivateBackendWarning
        self.settingsPersistenceError = nil
        self.commandPreferences = config.current.commandPreferences
        self.widgetBoard = WidgetBoardState(configService: config)
        self.widgetBoard.persistenceErrorHandler = { [weak self] error in
            self?.showSettingsPersistenceError(error)
        }
        actionRunner.mediaStatusHandler = { [weak self] message in
            let normalized = message.lowercased()
            self?.isMediaDownloadActive = normalized.hasPrefix("downloaded") == false && normalized.contains("failed") == false
            self?.diagnosticsSummary = message
        }
        actionRunner.feedbackHandler = { [weak self] feedback in
            self?.showActionFeedback(feedback)
        }
        clipboardHistory.start()
        agents.start()
        self.statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusSummary()
            }
        }
    }

    private func persistAIThreads() {
        aiChatStore.save(quickAIThreads)
    }

    private func showActionFeedback(_ feedback: ActionFeedback) {
        feedbackTask?.cancel()
        actionFeedback = feedback
        feedbackTask = Task { [weak self] in
            do {
                try await Task.sleep(for: feedback.displayDuration)
            } catch {
                return
            }
            self?.actionFeedback = nil
        }
    }

    func setAgentShelfVisible(_ isVisible: Bool) {
        guard isAgentShelfVisible != isVisible else { return }
        let previous = isAgentShelfVisible
        isAgentShelfVisible = isVisible
        do {
            try configService.updateAgentShelfVisibility(isVisible)
            settingsPersistenceError = nil
        } catch {
            isAgentShelfVisible = previous
            showSettingsPersistenceError(error)
        }
    }

    func setHotkey(_ hotkey: FoundryHotkey) {
        guard self.hotkey != hotkey else { return }
        let previous = self.hotkey
        var didRegister = false
        do {
            try onHotkeyChanged?(hotkey)
            didRegister = true
            try configService.updateHotkey(hotkey)
            self.hotkey = hotkey
            hotkeyError = nil
            settingsPersistenceError = nil
        } catch {
            if didRegister {
                do {
                    try onHotkeyChanged?(previous)
                } catch {
                    diagnostics.log("Failed to restore previous hotkey: \(error.localizedDescription)")
                }
                showSettingsPersistenceError(error)
            } else {
                hotkeyError = "That shortcut is unavailable. Choose another key combination."
                diagnostics.log("Failed to register hotkey: \(error.localizedDescription)")
            }
        }
    }

    func setThemeIntensity(_ intensity: Double) {
        let previous = themeIntensity
        themeIntensity = intensity
        do {
            try configService.updateThemeIntensity(intensity)
            settingsPersistenceError = nil
        } catch {
            themeIntensity = previous
            showSettingsPersistenceError(error)
        }
    }

    func setOllamaEnabled(_ isEnabled: Bool) {
        let previous = isOllamaEnabled
        isOllamaEnabled = isEnabled
        var ai = configService.current.ai
        ai.isOllamaEnabled = isEnabled
        do {
            try configService.updateAIConfig(ai)
            settingsPersistenceError = nil
        } catch {
            isOllamaEnabled = previous
            showSettingsPersistenceError(error)
        }
    }

    func setOllamaHost(_ host: String) {
        let previous = ollamaHost
        ollamaHost = host
        guard let value = Self.validatedOllamaHost(host) else {
            ollamaHostError = "Enter an absolute http or https URL."
            return
        }
        ollamaHostError = nil
        var ai = configService.current.ai
        ai.ollamaHost = value
        do {
            try configService.updateAIConfig(ai)
            ollamaHost = value
            settingsPersistenceError = nil
        } catch {
            ollamaHost = previous
            showSettingsPersistenceError(error)
        }
    }

    func setOllamaModel(_ model: String) {
        let previous = ollamaModel
        ollamaModel = model
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else {
            ollamaModelError = "Enter an Ollama model name."
            return
        }
        ollamaModelError = nil
        var ai = configService.current.ai
        ai.ollamaModel = value
        do {
            try configService.updateAIConfig(ai)
            ollamaModel = value
            settingsPersistenceError = nil
        } catch {
            ollamaModel = previous
            showSettingsPersistenceError(error)
        }
    }

    var selectedAIProfile: AIProviderProfile? {
        guard let selectedAIProfileID else { return nil }
        return aiProfiles.first { $0.id == selectedAIProfileID }
    }

    func selectAIProfile(_ id: UUID) {
        selectedAIProfileID = id
        aiCredentialInput = ""
        aiProfileStatus = nil
        refreshAIModels()
    }

    func addAIProfile(presetID: String) {
        guard let preset = AIProviderPreset.find(presetID) else { return }
        let profile = preset.makeProfile()
        aiProfiles.append(profile)
        selectedAIProfileID = profile.id
        aiCredentialInput = ""
        aiProfileStatus = nil
        refreshAIModels()
        do {
            try configService.updateAIProfile(profile)
            settingsPersistenceError = nil
        } catch {
            aiProfiles.removeAll { $0.id == profile.id }
            showSettingsPersistenceError(error)
        }
    }

    func removeSelectedAIProfile() {
        guard let profile = selectedAIProfile, profile.kind != .appleFoundationModels else { return }
        let previousProfiles = aiProfiles
        let previousDefault = defaultAIProfileID
        let previousFallbacks = fallbackAIProfileIDs
        aiProfiles.removeAll { $0.id == profile.id }
        fallbackAIProfileIDs.removeAll { $0 == profile.id }
        if defaultAIProfileID == profile.id { defaultAIProfileID = aiProfiles.first(where: { $0.enabled })?.id }
        selectedAIProfileID = defaultAIProfileID ?? aiProfiles.first?.id
        aiCredentialInput = ""
        do {
            try configService.removeAIProfile(id: profile.id)
            try aiCredentialStore.delete(for: profile.id)
            settingsPersistenceError = nil
        } catch {
            aiProfiles = previousProfiles
            defaultAIProfileID = previousDefault
            fallbackAIProfileIDs = previousFallbacks
            selectedAIProfileID = profile.id
            showSettingsPersistenceError(error)
        }
    }

    func setAIProfileEnabled(_ enabled: Bool, id: UUID) {
        updateAIProfile(id: id) { profile in
            profile.enabled = enabled
        }
    }

    func setAIProfileName(_ name: String, id: UUID) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else { return }
        updateAIProfile(id: id) { profile in
            profile.name = value
        }
    }

    func setAIProfileEndpoint(_ endpoint: String, id: UUID) {
        guard let value = AIEndpointPolicy.normalized(endpoint) else {
            aiProfileStatus = "Enter an absolute HTTP or HTTPS endpoint without embedded credentials."
            return
        }
        updateAIProfile(id: id) { profile in
            profile.endpoint = value
        }
        if AIEndpointPolicy.requiresPlainHTTPWarning(value) {
            aiProfileStatus = "This endpoint uses unencrypted HTTP. Use it only on a network you trust."
        } else {
            aiProfileStatus = nil
        }
    }

    func setAIProfileModel(_ model: String, id: UUID) {
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else {
            aiProfileStatus = "Enter a model name."
            return
        }
        updateAIProfile(id: id) { profile in
            profile.model = value
        }
        aiProfileStatus = nil
    }

    func setDefaultAIProfile(_ id: UUID) {
        let previous = defaultAIProfileID
        defaultAIProfileID = id
        do {
            try configService.setDefaultAIProfile(id: id)
            settingsPersistenceError = nil
        } catch {
            defaultAIProfileID = previous
            showSettingsPersistenceError(error)
        }
    }

    func setAIFallback(_ enabled: Bool, id: UUID) {
        let previous = fallbackAIProfileIDs
        if enabled {
            fallbackAIProfileIDs.append(contentsOf: fallbackAIProfileIDs.contains(id) ? [] : [id])
        } else {
            fallbackAIProfileIDs.removeAll { $0 == id }
        }
        do {
            try configService.setAIFallbackProfiles(fallbackAIProfileIDs)
            settingsPersistenceError = nil
        } catch {
            fallbackAIProfileIDs = previous
            showSettingsPersistenceError(error)
        }
    }

    func setAIProfileAPIKey(_ value: String, id: UUID) {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if key.isEmpty {
                try aiCredentialStore.delete(for: id)
                aiProfileStatus = "Credential removed."
            } else {
                try aiCredentialStore.save(.apiKey(key), for: id)
                aiProfileStatus = "Credential stored in Keychain."
            }
            aiCredentialInput = ""
        } catch {
            aiProfileStatus = "Could not update the Keychain credential."
            diagnostics.log("AI credential update failed: \(error.localizedDescription)")
        }
    }

    func setCodexPrivateBackendWarningAccepted(_ accepted: Bool) {
        let previous = acceptedCodexPrivateBackendWarning
        acceptedCodexPrivateBackendWarning = accepted
        var ai = configService.current.ai
        ai.acceptedCodexPrivateBackendWarning = accepted
        do {
            try configService.updateAIConfig(ai)
            settingsPersistenceError = nil
        } catch {
            acceptedCodexPrivateBackendWarning = previous
            showSettingsPersistenceError(error)
        }
    }

    func loginCodexBrowser() {
        guard acceptedCodexPrivateBackendWarning, let profile = selectedAIProfile, profile.kind == .openAISubscription else {
            aiProfileStatus = "Review and accept the private Codex backend warning before signing in."
            return
        }
        codexOAuthTask?.cancel()
        codexDeviceAuthorization = nil
        persistCodexLoginMethod(.browser)
        codexLoginState = .waitingForBrowser
        aiProfileStatus = "Complete ChatGPT sign-in in your browser."
        codexOAuthTask = Task { [weak self] in
            do {
                _ = try await self?.codexOAuthService.browserLogin(profileID: profile.id)
                guard Task.isCancelled == false else { return }
                self?.codexLoginState = .connected
                self?.aiProfileStatus = "ChatGPT subscription connected."
                self?.updateAIProfile(id: profile.id) { $0.enabled = true }
            } catch {
                guard Task.isCancelled == false else { return }
                self?.codexLoginState = .failed(error.localizedDescription)
                self?.aiProfileStatus = error.localizedDescription
            }
        }
    }

    func requestCodexDeviceLogin() {
        guard acceptedCodexPrivateBackendWarning, selectedAIProfile?.kind == .openAISubscription else {
            aiProfileStatus = "Review and accept the private Codex backend warning before signing in."
            return
        }
        codexOAuthTask?.cancel()
        persistCodexLoginMethod(.device)
        codexLoginState = .starting
        aiProfileStatus = "Requesting a device code..."
        codexOAuthTask = Task { [weak self] in
            do {
                let authorization = try await self?.codexOAuthService.requestDeviceAuthorization()
                guard let authorization, Task.isCancelled == false else { return }
                self?.codexDeviceAuthorization = authorization
                self?.codexLoginState = .waitingForDeviceApproval
                self?.aiProfileStatus = "Open \(authorization.verificationURL) and enter \(authorization.userCode)."
            } catch {
                guard Task.isCancelled == false else { return }
                self?.codexLoginState = .failed(error.localizedDescription)
                self?.aiProfileStatus = error.localizedDescription
            }
        }
    }

    func completeCodexDeviceLogin() {
        guard let authorization = codexDeviceAuthorization, let profile = selectedAIProfile, profile.kind == .openAISubscription else { return }
        codexLoginState = .exchangingCode
        aiProfileStatus = "Waiting for ChatGPT device approval..."
        codexOAuthTask?.cancel()
        codexOAuthTask = Task { [weak self] in
            do {
                _ = try await self?.codexOAuthService.completeDeviceLogin(authorization, profileID: profile.id)
                guard Task.isCancelled == false else { return }
                self?.codexDeviceAuthorization = nil
                self?.codexLoginState = .connected
                self?.aiProfileStatus = "ChatGPT subscription connected."
                self?.updateAIProfile(id: profile.id) { $0.enabled = true }
            } catch {
                guard Task.isCancelled == false else { return }
                self?.codexLoginState = .failed(error.localizedDescription)
                self?.aiProfileStatus = error.localizedDescription
            }
        }
    }

    func cancelCodexLogin() {
        codexOAuthTask?.cancel()
        codexOAuthTask = nil
        Task { await codexOAuthService.cancelCurrentLogin() }
        codexDeviceAuthorization = nil
        codexLoginState = .cancelled
        aiProfileStatus = "ChatGPT login cancelled."
    }

    func logoutCodex() {
        guard let profile = selectedAIProfile, profile.kind == .openAISubscription else { return }
        Task { [weak self] in
            do {
                try await self?.codexOAuthService.signOut(profileID: profile.id)
                self?.codexLoginState = .disconnected
                self?.aiProfileStatus = "ChatGPT subscription disconnected."
                self?.updateAIProfile(id: profile.id) { $0.enabled = false }
            } catch {
                self?.aiProfileStatus = "Could not remove the ChatGPT credential."
            }
        }
    }

    func aiProfileHasCredential(_ profile: AIProviderProfile) -> Bool {
        if profile.authentication == .oauth {
            do {
                guard let credential = try aiCredentialStore.credential(for: profile.id), case let .oauth(value) = credential else { return false }
                return value.isUsable
            } catch { return false }
        }
        guard profile.authentication == .apiKey || profile.authentication == .optionalAPIKey else { return profile.authentication == .none }
        do {
            return try aiCredentialStore.credential(for: profile.id) != nil
        } catch {
            return false
        }
    }

    private func persistCodexLoginMethod(_ method: OpenAICodexLoginMethod) {
        var ai = configService.current.ai
        ai.codexLoginMethod = method
        try? configService.updateAIConfig(ai)
    }

    func testSelectedAIProfile() {
        guard let profile = selectedAIProfile else { return }
        aiProfileTestTask?.cancel()
        aiProfileTestingID = profile.id
        aiProfileStatus = "Testing connection..."
        aiProfileTestTask = Task { [weak self] in
            let result = await AITransportRouter.test(profile: profile)
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                guard let self else { return }
                self.aiProfileTestingID = nil
                self.aiProfileStatus = result.message
            }
        }
    }

    func refreshAIModels() {
        guard let profile = selectedAIProfile, profile.capabilities.modelDiscovery else {
            aiAvailableModels = []
            return
        }
        aiModelTask?.cancel()
        aiModelsLoading = true
        aiModelTask = Task { [weak self] in
            let models = await AITransportRouter.models(profile: profile)
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                guard let self else { return }
                self.aiAvailableModels = models
                self.aiModelsLoading = false
                if models.isEmpty == false {
                    self.aiProfileStatus = "Found \(models.count) model\(models.count == 1 ? "" : "s")."
                }
            }
        }
    }

    private func updateAIProfile(id: UUID, change: (inout AIProviderProfile) -> Void) {
        guard let index = aiProfiles.firstIndex(where: { $0.id == id }) else { return }
        let previous = aiProfiles[index]
        var profile = previous
        change(&profile)
        aiProfiles[index] = profile
        do {
            try configService.updateAIProfile(profile)
            settingsPersistenceError = nil
        } catch {
            aiProfiles[index] = previous
            showSettingsPersistenceError(error)
        }
    }

    static func validatedOllamaHost(_ host: String) -> String? {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return value
    }

    private func showSettingsPersistenceError(_ error: Error) {
        settingsPersistenceError = "Preferences could not be saved. Your previous settings were kept."
        diagnostics.log("Settings persistence failed: \(error.localizedDescription)")
    }

    func resetForOpen() {
        mode = .search
        widgetBoard.start()
        agents.start()
        activityMonitor.stop()
        emojiPicker.reset()
        clipboardHistory.reset()
        snippets.reset()
        fileConversion.reset()
        camera.stop()
        translator.reset()
        developerTools.reset()
        query = ""
        quickAIQuery = ""
        quickAIResponse = ""
        quickAIStatus = ""
        isQuickAILoading = false
        quickAILastFailedPrompt = nil
        quickAITask?.cancel()
        quickAITask = nil
        quickAIRequestID = nil
        results = []
        selectedResultID = nil
        isShowingActions = false
        selectedActionID = nil
        isMediaDownloadActive = false
        refreshStatusSummary()
    }

    func panelWillClose() {
        widgetBoard.stop()
        activityMonitor.stop()
        emojiPicker.reset()
        clipboardHistory.reset()
        snippets.reset()
        fileConversion.reset()
        camera.stop()
        translator.reset()
        developerTools.reset()
    }

    func shutdown() {
        statusTimer?.invalidate()
        statusTimer = nil
        commandCatalogTask?.cancel()
        commandCatalogTask = nil
        aiProfileTestTask?.cancel()
        aiProfileTestTask = nil
        aiModelTask?.cancel()
        aiModelTask = nil
        codexOAuthTask?.cancel()
        codexOAuthTask = nil
        Task { await codexOAuthService.cancelCurrentLogin() }
        agents.stop()
    }

    func openSettings() {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .settings
        }
        widgetBoard.start()
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        diagnosticsSummary = "settings"
    }

    var commandCatalogCount: Int {
        commandRows.count
    }

    func prepareCommandCatalog() {
        guard isCommandCatalogLoading == false, isCommandCatalogReady == false else { return }
        isCommandCatalogLoading = true
        let registry = registry
        let diagnostics = diagnostics
        let span = diagnostics.startSpan("commands.catalog.prepare")
        commandCatalogTask = Task { [weak self] in
            let snapshot = await registry.commandCatalog()
            diagnostics.endSpan(span)
            guard let self, Task.isCancelled == false else { return }
            self.commandDescriptors = snapshot.descriptors
            self.isCommandCatalogLoading = false
            self.isCommandCatalogReady = true
            self.rebuildCommandRows()
            self.commandCatalogTask = nil
        }
    }

    func toggleCommandExpansion(_ commandID: String) {
        expandedCommandID = expandedCommandID == commandID ? nil : commandID
    }

    private func rebuildCommandRows() {
        let preferences = commandPreferences
        let rows = commandDescriptors.map { descriptor in
            CommandSettingsRowModel(
                descriptor: descriptor,
                preference: preferences[descriptor.id] ?? CommandPreference()
            )
        }
        let query = commandSettingsQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let visible = rows
            .filter { query.isEmpty || $0.searchText.contains(query) }
            .sorted { lhs, rhs in
                switch (lhs.preference.favoriteRank, rhs.preference.favoriteRank) {
                case let (lhsRank?, rhsRank?):
                    if lhsRank != rhsRank { return lhsRank < rhsRank }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    break
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        commandRows = rows
        visibleCommandRows = visible
    }

    func commandPreference(for commandID: String) -> CommandPreference {
        commandPreferences[commandID] ?? CommandPreference()
    }

    func setCommandEnabled(_ isEnabled: Bool, for commandID: String) {
        var preference = commandPreference(for: commandID)
        preference.isEnabled = isEnabled
        updateCommandPreference(preference, for: commandID)
    }

    func setSearchSensitivity(_ sensitivity: SearchSensitivity) {
        let previous = searchSensitivity
        searchSensitivity = sensitivity
        do {
            try configService.updateSearchSensitivity(sensitivity)
            settingsPersistenceError = nil
            refreshResults()
        } catch {
            searchSensitivity = previous
            showSettingsPersistenceError(error)
        }
    }

    func setCommandFavorite(_ isFavorite: Bool, for commandID: String) {
        var preference = commandPreference(for: commandID)
        preference.favoriteRank = isFavorite ? nextFavoriteRank() : nil
        updateCommandPreference(preference, for: commandID)
    }

    func setCommandAliases(_ rawAliases: String, for commandID: String) {
        var preference = commandPreference(for: commandID)
        preference.aliases = Self.normalizedCommandAliases(rawAliases)
        updateCommandPreference(preference, for: commandID)
    }

    func resetCommandPreference(for commandID: String) {
        updateCommandPreference(CommandPreference(), for: commandID)
    }

    static func normalizedCommandAliases(_ value: String) -> [String] {
        var seen = Set<String>()
        var aliases: [String] = []
        for component in value.split(separator: ",") {
            let alias = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard alias.isEmpty == false else { continue }
            guard seen.insert(alias.lowercased()).inserted else { continue }
            aliases.append(String(alias))
            if aliases.count == 8 { break }
        }
        return aliases
    }

    private func nextFavoriteRank() -> Int {
        (commandPreferences.values.compactMap(\.favoriteRank).max() ?? -1) + 1
    }

    private func updateCommandPreference(_ preference: CommandPreference, for commandID: String) {
        let previous = commandPreferences[commandID]
        commandPreferences[commandID] = preference
        rebuildCommandRows()
        do {
            try configService.updateCommandPreference(preference, for: commandID)
            settingsPersistenceError = nil
        } catch {
            if let previous {
                commandPreferences[commandID] = previous
            } else {
                commandPreferences.removeValue(forKey: commandID)
            }
            rebuildCommandRows()
            showSettingsPersistenceError(error)
        }
    }

    func openDashboard() {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .dashboard
        }
        widgetBoard.start()
        agents.start()
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        diagnosticsSummary = "dashboard"
    }

    func openAgents() {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .agents
        }
        agents.start()
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        diagnosticsSummary = "agents"
    }

    func handleEscape() -> Bool {
        if mode != .search || isShowingActions {
            backToSearch()
            return true
        }
        return false
    }

    func backToSearch() {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .search
        }
        widgetBoard.stop()
        activityMonitor.stop()
        emojiPicker.reset()
        camera.stop()
        fileConversion.reset()
        translator.reset()
        developerTools.reset()
        query = ""
        quickAIQuery = ""
        quickAIResponse = ""
        quickAIStatus = ""
        isQuickAILoading = false
        quickAILastFailedPrompt = nil
        quickAITask?.cancel()
        quickAITask = nil
        quickAIRequestID = nil
        results = []
        selectedResultID = nil
        isShowingActions = false
        selectedActionID = nil
        refreshStatusSummary()
    }

    @discardableResult
    func executeSelectedResult() -> Bool {
        guard let selectedResult else {
            if let request = AIProvider.request(from: query) {
                openQuickAI(initialPrompt: request.prompt)
            }
            return false
        }
        if isShowingActions, let selectedAction {
            diagnostics.log("Executing action: \(selectedAction.id)")
            if case let .resetRanking(commandID) = selectedAction.kind {
                registry.resetRanking(for: commandID)
                showActionFeedback(.success("Ranking reset"))
                return false
            }
            registry.recordExecution(resultID: selectedResult.id, query: query)
            if case let .openQuickAI(prompt) = selectedAction.kind {
                openQuickAI(initialPrompt: prompt)
                return false
            }
            if case .downloadMedia = selectedAction.kind {
                isMediaDownloadActive = true
                diagnosticsSummary = "Starting download"
                actionRunner.perform(selectedAction)
                return false
            }
            if selectedAction.kind == .chooseMediaDownloadFolder {
                actionRunner.perform(selectedAction)
                refreshResults()
                return false
            }
            actionRunner.perform(selectedAction)
            return true
        }

        diagnostics.log("Executing result: \(selectedResult.id)")
        registry.recordExecution(resultID: selectedResult.id, query: query)
        if case let .openQuickAI(prompt) = selectedResult.primaryAction.kind {
            openQuickAI(initialPrompt: prompt)
            return false
        }
        if selectedResult.primaryAction.kind == .openActivityMonitor {
            openActivityMonitor()
            return false
        }
        if selectedResult.primaryAction.kind == .openEmojiPicker {
            openEmojiPicker()
            return false
        }
        if selectedResult.primaryAction.kind == .openFileShelf {
            openFileShelf()
            return false
        }
        if selectedResult.primaryAction.kind == .openClipboardHistory {
            openClipboardHistory()
            return false
        }
        if selectedResult.primaryAction.kind == .openSnippets {
            openSnippets()
            return false
        }
        if case let .openFileConverter(path) = selectedResult.primaryAction.kind {
            openFileConverter(path: path)
            return false
        }
        if selectedResult.primaryAction.kind == .openCamera {
            openCamera()
            return false
        }
        if case let .openTranslator(text, language) = selectedResult.primaryAction.kind {
            openTranslator(text: text, language: language)
            return false
        }
        if case let .openDeveloperTools(tool) = selectedResult.primaryAction.kind {
            openDeveloperTools(tool: tool)
            return false
        }
        if selectedResult.primaryAction.kind == .openSettings {
            openSettings()
            return false
        }
        if selectedResult.primaryAction.kind == .openDashboard {
            openDashboard()
            return false
        }
        if case .downloadMedia = selectedResult.primaryAction.kind {
            isMediaDownloadActive = true
            diagnosticsSummary = "Starting download"
            actionRunner.perform(selectedResult.primaryAction)
            return false
        }
        if selectedResult.primaryAction.kind == .chooseMediaDownloadFolder {
            actionRunner.perform(selectedResult.primaryAction)
            refreshResults()
            return false
        }
        actionRunner.perform(selectedResult.primaryAction)
        return true
    }

    func select(resultID: String) {
        selectedResultID = resultID
        if isShowingActions {
            selectedActionID = selectedActions.first?.id
        }
    }

    func select(actionID: String) {
        selectedActionID = actionID
    }

    func toggleActions() {
        guard selectedResult != nil else {
            diagnostics.log("No selected result for actions")
            return
        }
        isShowingActions.toggle()
        selectedActionID = isShowingActions ? selectedActions.first?.id : nil
    }

    func pasteFromClipboard() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string), text.isEmpty == false else { return false }
        switch mode {
        case .search:
            query += text
        case .activityMonitor:
            activityMonitor.query += text
        case .emojiPicker:
            emojiPicker.query += text
        case .clipboardHistory:
            clipboardHistory.query += text
        case .snippets:
            snippets.query += text
        case .translator:
            translator.sourceText += text
        case .camera, .fileConversion, .fileShelf, .settings, .dashboard, .developerTools, .quickAI, .agents:
            return false
        }
        return true
    }

    func showFileShelf() {
        openFileShelf()
    }

    func moveSelectionDown() {
        moveSelection(offset: 1)
    }

    func moveSelectionUp() {
        moveSelection(offset: -1)
    }

    private func moveSelection(offset: Int) {
        if mode == .activityMonitor {
            activityMonitor.moveSelection(offset: offset)
            return
        }

        if mode == .emojiPicker {
            offset > 0 ? emojiPicker.moveDown() : emojiPicker.moveUp()
            return
        }

        if mode == .fileShelf {
            fileShelf.moveSelection(offset: offset)
            return
        }

        if mode == .fileConversion {
            return
        }

        if mode == .snippets {
            snippets.moveSelection(offset: offset)
            return
        }

        if mode == .clipboardHistory {
            clipboardHistory.moveSelection(offset: offset)
            return
        }

        if mode == .camera {
            return
        }

        if mode == .translator {
            return
        }

        if isShowingActions {
            let actions = selectedActions
            guard actions.isEmpty == false else { return }
            let currentIndex = selectedActionID.flatMap { id in actions.firstIndex { $0.id == id } } ?? 0
            let nextIndex = min(max(currentIndex + offset, 0), actions.count - 1)
            selectedActionID = actions[nextIndex].id
            return
        }

        guard results.isEmpty == false else { return }
        let currentIndex = selectedResultID.flatMap { id in results.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), results.count - 1)
        selectedResultID = results[nextIndex].id
        selectionScrollToken = UUID()
    }

    private func refreshResults() {
        guard mode == .search else { return }
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        isShowingActions = false
        selectedActionID = nil
        guard trimmed.isEmpty == false else {
            results = []
            selectedResultID = nil
            refreshStatusSummary()
            refreshHomeResults()
            return
        }

        if AIProvider.request(from: trimmed) != nil {
            results = []
            selectedResultID = nil
            refreshStatusSummary(fallback: "Press Tab or Return to ask AI")
            return
        }

        searchGeneration += 1
        let generation = searchGeneration
        let registry = registry
        let diagnostics = diagnostics
        let span = diagnostics.startSpan("search.async")

        searchTask = Task { [weak self] in
            guard Task.isCancelled == false else {
                diagnostics.endSpan(span)
                return
            }

            let immediateResults = await registry.immediateResults(matching: trimmed)
            guard let self,
                  Task.isCancelled == false,
                  self.searchGeneration == generation,
                  self.query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else {
                diagnostics.endSpan(span)
                return
            }

            self.selectedResultID = nil
            self.applySearchResults(immediateResults, preserving: nil)

            let foundResults = await registry.completeResults(matching: trimmed, initialResults: immediateResults)
            guard Task.isCancelled == false,
                  self.searchGeneration == generation,
                  self.query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else {
                diagnostics.endSpan(span)
                return
            }

            self.applySearchResults(foundResults, preserving: self.selectedResultID)
            diagnostics.endSpan(span)
        }
    }

    private func applySearchResults(_ nextResults: [CommandResult], preserving preferredID: String?) {
        results = nextResults
        if let preferredID, nextResults.contains(where: { $0.id == preferredID }) {
            selectedResultID = preferredID
        } else if selectedResultID == nil || nextResults.contains(where: { $0.id == selectedResultID }) == false {
            selectedResultID = nextResults.first?.id
        }
        selectionScrollToken = UUID()
        refreshStatusSummary()
    }

    private func refreshStatusSummary(fallback: String = "") {
        guard isMediaDownloadActive == false else { return }
        diagnosticsSummary = registry.statusSummary(resultCount: results.count, fallback: fallback)
    }

    private func refreshHomeResults() {
        searchGeneration += 1
        let generation = searchGeneration
        let registry = registry
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            var homeResults = await registry.homeResults()
            guard let self,
                  Task.isCancelled == false,
                  self.searchGeneration == generation,
                  self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if self.fileShelf.files.isEmpty == false {
                homeResults.removeAll { $0.id == "foundry.file-shelf" }
            }
            self.results = homeResults
            self.selectedResultID = homeResults.first?.id
            self.selectionScrollToken = UUID()
            self.refreshStatusSummary()
        }
    }

    private func openActivityMonitor() {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .activityMonitor
        }
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        activityMonitor.reset()
        activityMonitor.start()
        diagnosticsSummary = "activity monitor"
    }

    private func openEmojiPicker() {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .emojiPicker
        }
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        emojiPicker.reset()
        diagnosticsSummary = "emoji & symbols"
    }

    private func openFileShelf() {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .fileShelf
        }
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        fileShelf.selectFirst()
        diagnosticsSummary = "file shelf"
    }

    private func openClipboardHistory() {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .clipboardHistory
        }
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        clipboardHistory.reset()
        diagnosticsSummary = "clipboard history"
    }

    private func openSnippets() {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .snippets
        }
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        snippets.reset()
        diagnosticsSummary = "snippets"
    }

    private func openFileConverter(path: String? = nil) {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .fileConversion
        }
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        fileConversion.reset()
        if let path {
            fileConversion.setSource(url: URL(fileURLWithPath: path))
        } else if let selectedFile = fileShelf.selectedFile {
            fileConversion.setSource(url: selectedFile.url)
        }
        diagnosticsSummary = "file converter"
    }

    private func openCamera() {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .camera
        }
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        camera.start()
        diagnosticsSummary = "camera"
    }

    private func openTranslator(text: String? = nil, language: String? = nil) {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .translator
        }
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        translator.reset()
        if let text { translator.sourceText = text }
        if let language { translator.targetLanguage = language.capitalized }
        diagnosticsSummary = "translator"
    }

    private func openDeveloperTools(tool: String? = nil) {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .developerTools
        }
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        developerTools.reset()
        if let tool, let selectedTool = DeveloperToolsState.Tool(commandID: tool) {
            developerTools.selectedTool = selectedTool
        }
        diagnosticsSummary = "developer tools"
    }

    func openQuickAI(initialPrompt: String = "") {
        quickAITask?.cancel()
        quickAITask = nil
        quickAIRequestID = nil
        let prompt = AIProvider.request(from: initialPrompt)?.prompt ?? initialPrompt
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .quickAI
        }
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        isShowingActions = false
        selectedActionID = nil
        quickAIQuery = prompt
        quickAIResponse = ""
        quickAIStatus = prompt.isEmpty ? "Ask anything" : "Ready"
        isQuickAILoading = false
        quickAILastFailedPrompt = nil
        let thread = AIChatThread(title: prompt.isEmpty ? "New Chat" : prompt, providerProfileID: defaultAIProfileID)
        quickAIThreads.insert(thread, at: 0)
        activeQuickAIThreadID = thread.id
        persistAIThreads()
        if prompt.isEmpty == false {
            Task { await submitQuickAI() }
        }
    }

    func submitQuickAI() async {
        let prompt = quickAIQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.isEmpty == false else {
            quickAIStatus = "Type a question first"
            return
        }
        quickAIQuery = ""
        quickAITask?.cancel()
        quickAIRequestID = nil
        guard let threadID = activeQuickAIThreadID else {
            quickAIStatus = "Start a chat first"
            return
        }
        let requestID = UUID()
        quickAIRequestID = requestID
        quickAITask = Task { [weak self] in
            await self?.performQuickAI(prompt: prompt, threadID: threadID, requestID: requestID)
        }
        await quickAITask?.value
    }

    func retryQuickAI() {
        guard let prompt = quickAILastFailedPrompt, isQuickAILoading == false else { return }
        quickAILastFailedPrompt = nil
        quickAITask?.cancel()
        guard let threadID = activeQuickAIThreadID else { return }
        let requestID = UUID()
        quickAIRequestID = requestID
        quickAITask = Task { [weak self] in
            await self?.performQuickAI(prompt: prompt, persistUserMessage: false, threadID: threadID, requestID: requestID)
        }
    }

    private func performQuickAI(prompt: String, persistUserMessage: Bool = true, threadID: UUID, requestID: UUID) async {
        guard isCurrentQuickAIRequest(requestID, threadID: threadID) else { return }
        isQuickAILoading = true
        quickAIStatus = "Thinking"
        quickAIResponse = ""
        var didFail = false
        var response = ""
        let priorMessages = quickAIThreads.first(where: { $0.id == threadID })
            .map { Array($0.messages.filter { $0.role == .user || $0.role == .assistant }.suffix(10)) } ?? []
        let conversationContext = AIConversationContext.build(from: priorMessages)
        let profileID = quickAIThreads.first(where: { $0.id == threadID })?.providerProfileID
        if persistUserMessage, let index = quickAIThreads.firstIndex(where: { $0.id == threadID }) {
            quickAIThreads[index].messages.append(AIChatMessage(role: .user, content: prompt))
            quickAIThreads[index].updatedAt = .now
            if quickAIThreads[index].title == "New Chat" {
                quickAIThreads[index].title = prompt.prefix(48).description
            }
            persistAIThreads()
        }

        for await event in aiProvider.stream(prompt: prompt, context: conversationContext, profileID: profileID, sessionID: threadID.uuidString) {
            guard Task.isCancelled == false else {
                guard isCurrentQuickAIRequest(requestID, threadID: threadID) else { return }
                isQuickAILoading = false
                quickAIStatus = "Cancelled"
                quickAILastFailedPrompt = prompt
                return
            }
            guard isCurrentQuickAIRequest(requestID, threadID: threadID) else { return }
            switch event {
            case let .status(status):
                quickAIStatus = status
            case let .textDelta(delta):
                response += delta
                quickAIResponse = response
            case let .toolCallStarted(name):
                quickAIStatus = "Using \(name.replacingOccurrences(of: "_", with: " "))"
                recordToolStarted(name, threadID: threadID)
            case let .toolResult(name, result):
                quickAIStatus = "Finished \(name.replacingOccurrences(of: "_", with: " "))"
                recordToolFinished(name, result: result, threadID: threadID)
            case .completed:
                quickAIStatus = "Done"
            case let .failed(message):
                didFail = true
                quickAILastFailedPrompt = prompt
                quickAIStatus = message
                response = message
                quickAIResponse = message
            }
        }

        guard Task.isCancelled == false else {
            guard isCurrentQuickAIRequest(requestID, threadID: threadID) else { return }
            isQuickAILoading = false
            quickAIStatus = "Cancelled"
            quickAILastFailedPrompt = prompt
            return
        }
        guard isCurrentQuickAIRequest(requestID, threadID: threadID) else { return }
        quickAIStatus = didFail ? "Failed" : response.isEmpty ? "No response" : "Done"
        isQuickAILoading = false
        if let index = quickAIThreads.firstIndex(where: { $0.id == threadID }) {
            if response.isEmpty == false, didFail == false {
                quickAIThreads[index].messages.append(AIChatMessage(role: .assistant, content: response))
            }
            quickAIThreads[index].updatedAt = .now
            persistAIThreads()
        }
    }

    private func recordToolStarted(_ name: String, threadID: UUID) {
        guard let index = quickAIThreads.firstIndex(where: { $0.id == threadID }) else { return }
        quickAIThreads[index].messages.append(AIChatMessage(role: .tool, content: "running:\(name)"))
        quickAIThreads[index].updatedAt = .now
        persistAIThreads()
    }

    private func recordToolFinished(_ name: String, result: String, threadID: UUID) {
        guard let threadIndex = quickAIThreads.firstIndex(where: { $0.id == threadID }),
              let messageIndex = quickAIThreads[threadIndex].messages.lastIndex(where: { $0.role == .tool && $0.content == "running:\(name)" }) else { return }
        quickAIThreads[threadIndex].messages[messageIndex].content = "complete:\(name)\n\(String(result.prefix(1800)))"
        quickAIThreads[threadIndex].updatedAt = .now
        persistAIThreads()
    }

    func selectQuickAIThread(_ thread: AIChatThread) {
        quickAITask?.cancel()
        quickAITask = nil
        quickAIRequestID = nil
        activeQuickAIThreadID = thread.id
        quickAIQuery = ""
        quickAIResponse = thread.messages.last(where: { $0.role == .assistant })?.content ?? ""
        quickAIStatus = thread.messages.isEmpty ? "Ask anything" : "Loaded"
        quickAILastFailedPrompt = nil
        mode = .quickAI
    }

    private func isCurrentQuickAIRequest(_ requestID: UUID, threadID: UUID) -> Bool {
        requestID == quickAIRequestID && threadID == activeQuickAIThreadID
    }

}
