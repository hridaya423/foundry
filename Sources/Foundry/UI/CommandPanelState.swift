import AppKit
import Foundation
import ServiceManagement
import SwiftUI
import FoundryDomain
import FoundryServices
import Observation

@MainActor
@Observable
final class CommandPanelState {
    enum Mode {
        case search
        case quickAI
        case emojiPicker
        case fileShelf
        case clipboardHistory
        case snippets
        case fileConversion
        case camera
        case translator
        case developerTools
        case agents
        case mediaDownloads
        case settings
    }

    var query = "" {
        didSet { refreshResults() }
    }
    var results: [CommandResult] = []
    var selectedResultID: String?
    private(set) var selectionScrollToken = UUID()
    var isShowingActions = false {
        didSet {
            if isShowingActions { prepareOpenWithActions() }
            else { openWithTask?.cancel(); openWithActions = [] }
        }
    }
    var actionFilter = "" {
        didSet { if isShowingActions { selectedActionID = visibleActions.first?.id } }
    }
    private var openWithActions: [CommandAction] = []
    private var openWithTask: Task<Void, Never>?
    var selectedActionID: String?
    var mode: Mode = .search {
        didSet {
            guard mode != oldValue else { return }
            let span = diagnostics.startSpan("mode.switch")
            DispatchQueue.main.async { [diagnostics] in
                diagnostics.endSpan(span)
            }
        }
    }
    var focusToken = UUID()
    var presentationToken = UUID()
    private(set) var isSearchLoading = false
    private(set) var isHomeLoading = false
    var hoverHighlightsArmed = true
    private(set) var actionFeedback: ActionFeedback? = nil
    var isAgentShelfVisible: Bool
    var hotkey: FoundryHotkey
    var hotkeyError: String? = nil
    private(set) var launcherHotkeyFailed = false
    var showMenuBarIcon: Bool
    var popToRootAfterSeconds: Double
    var windowMode: WindowMode
    private(set) var launchAtLoginError: String?
    private(set) var mainBrowser: BrowserSource?
    var themeIntensity: Double
    var searchSensitivity: SearchSensitivity
    var settingsPersistenceError: String?
    private(set) var snippetExpansion: SnippetExpansionConfig
    private(set) var snippetExpansionError: String?
    var commandSettingsQuery = "" {
        didSet { rebuildCommandRows() }
    }
    private(set) var commandDescriptors: [CommandDescriptor] = []
    private(set) var commandPreferences: [String: CommandPreference]
    private(set) var commandRows: [CommandSettingsRowModel] = []
    private(set) var visibleCommandRows: [CommandSettingsRowModel] = []
    private(set) var commandCatalogFailures: [String] = []
    private(set) var isCommandCatalogLoading = false
    private(set) var isCommandCatalogReady = false
    private(set) var configLoadError: String?
    var expandedCommandID: String?
    var onHotkeyChanged: ((FoundryHotkey) throws -> Void)?
    var onCommandPreferencesChanged: (() -> Void)?
    var onMenuBarIconVisibilityChanged: ((Bool) -> Void)?
    var onCompactCollapseChanged: ((Bool) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuickLook: ((URL) -> Void)?
    var onTransientNotice: ((ActionFeedback) -> Void)?
    var pendingSettingsCommandID: String?
    var onOpenWelcomeGuide: (() -> Void)?
    var onSnippetExpansionChanged: (() -> Void)?
    var onRequestSnippetAccessibility: (() -> Void)?
    var onOpenSnippetPrivacySettings: (() -> Void)?
    var onResultExecuted: (() -> Void)?
    var now: () -> Date = Date.init
    private var lastClosedAt: Date?

    @ObservationIgnored lazy var emojiPicker = EmojiPickerState()
    let fileShelf = FileShelfState()
    let agents = AgentMonitorState()
    let clipboardHistory: ClipboardHistoryState
    let snippets: SnippetState
    @ObservationIgnored lazy var fileConversion = FileConversionState()
    @ObservationIgnored lazy var camera = CameraPreviewState()
    @ObservationIgnored lazy var translator = TranslatorState()
    @ObservationIgnored lazy var developerTools = DeveloperToolsState()
    let widgetBoard: WidgetBoardState
    let aiSettings: AISettingsState
    let quickAI: QuickAIState
    let mediaDownloads: MediaDownloadManager
    let installedBrowsers: [BrowserSource]
    private let configService: ConfigService

    private let registry: CommandRegistry
    private let searchCoordinator: CommandSearchCoordinator
    private let actionRunner: ActionRunner
    private let diagnostics: DiagnosticsService
    private var activeActionCancellationID: UUID?
    private var actionGeneration = 0
    private(set) var isActionInProgress = false
    private var feedbackTask: Task<Void, Never>?
    private var commandCatalogTask: Task<Void, Never>?
    private var isPanelOpen = false
    private var homeRefreshID = UUID()

    private(set) var favoriteResults: [CommandResult] = []
    private(set) var runningAppBundleIDs: Set<String> = []

    var selectedResult: CommandResult? {
        results.first { $0.id == selectedResultID }
    }

    var selectedActions: [CommandAction] {
        guard let selectedResult else { return [] }
        let isFavorite = commandPreferences[selectedResult.id]?.favoriteRank != nil
        return orderedActions(for: selectedResult)
            + openWithActions
            + [CommandAction(
                id: "favorite.toggle.\(selectedResult.id)",
                title: isFavorite ? "Remove from Favorites" : "Add to Favorites",
                kind: .toggleFavorite(commandID: selectedResult.id)
            ), CommandAction(
                id: "ranking.reset.\(selectedResult.id)",
                title: "Reset Ranking",
                kind: .resetRanking(commandID: selectedResult.id)
            ), CommandAction(
                id: "settings.configure.\(selectedResult.id)",
                title: "Configure Command",
                kind: .openCommandSettings(commandID: selectedResult.id)
            )]
    }

    var selectedAction: CommandAction? {
        selectedActions.first { $0.id == selectedActionID }
    }

    private func prepareOpenWithActions() {
        guard let result = selectedResult, result.id.hasPrefix("file.") else { return }
        let path = String(result.id.dropFirst("file.".count))
        let resultID = result.id
        openWithTask = Task { [weak self] in
            let url = URL(fileURLWithPath: path)
            let (apps, defaultApp) = await Task.detached { () -> ([URL], URL?) in
                let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
                return (apps, NSWorkspace.shared.urlForApplication(toOpen: url))
            }.value
            guard Task.isCancelled == false else { return }
            let selfBundleID = Bundle.main.bundleIdentifier
            var actions: [CommandAction] = []
            for appURL in apps.prefix(12) {
                let bundle = Bundle(url: appURL)
                if bundle?.bundleIdentifier == selfBundleID { continue }
                let name = bundle?.localizedInfoDictionary?["CFBundleName"] as? String
                    ?? bundle?.infoDictionary?["CFBundleName"] as? String
                    ?? appURL.deletingPathExtension().lastPathComponent
                let isDefault = appURL == defaultApp
                actions.append(CommandAction(
                    id: "openwith.\(resultID).\(bundle?.bundleIdentifier ?? appURL.path)",
                    title: "Open with \(name)\(isDefault ? " — Default" : "")",
                    kind: .openFileWithApp(path: path, appPath: appURL.path)
                ))
            }
            guard let self, Task.isCancelled == false else { return }
            self.openWithActions = actions
        }
    }

    var visibleActions: [CommandAction] {
        let tokens = actionFilter.lowercased().split(separator: " ")
        guard tokens.isEmpty == false else { return selectedActions }
        return selectedActions.filter { action in
            let title = action.title.lowercased()
            return tokens.allSatisfy { title.contains($0) }
        }
    }

    var actionShortcuts: [String: ActionShortcut] {
        ActionShortcut.assign(to: selectedActions)
    }

    init(
        registry: CommandRegistry,
        actionRunner: ActionRunner,
        diagnostics: DiagnosticsService,
        config: ConfigService,
        snippetStore: any SnippetStore = FileSnippetStore(),
        mediaDownloadManager: MediaDownloadManager = MediaDownloadManager(),
        clipboardHistory: ClipboardHistoryState? = nil
    ) {
        self.registry = registry
        self.searchCoordinator = CommandSearchCoordinator(registry: registry, diagnostics: diagnostics)
        self.actionRunner = actionRunner
        self.diagnostics = diagnostics
        self.configService = config
        self.clipboardHistory = clipboardHistory ?? ClipboardHistoryState(configuration: config.current.clipboard)
        self.snippets = SnippetState(store: snippetStore)
        self.isAgentShelfVisible = config.current.showAgentShelf
        self.showMenuBarIcon = config.current.showMenuBarIcon
        self.popToRootAfterSeconds = config.current.popToRootAfterSeconds
        self.windowMode = config.current.windowMode
        self.hotkey = config.current.hotkey
        self.mainBrowser = UserDefaults.standard.string(forKey: "foundry.mainBrowser").flatMap(BrowserSource.init(rawValue:))
        self.installedBrowsers = BrowserSource.allCases.filter(\.isInstalled)
        self.themeIntensity = config.current.themeIntensity
        self.searchSensitivity = config.current.searchSensitivity
        self.settingsPersistenceError = nil
        self.snippetExpansion = config.current.snippetExpansion
        self.snippetExpansionError = nil
        self.commandPreferences = config.current.commandPreferences
        self.commandCatalogFailures = []
        self.configLoadError = config.loadErrorMessage
        self.widgetBoard = WidgetBoardState(configService: config, diagnostics: diagnostics)
        self.aiSettings = AISettingsState(config: config, diagnostics: diagnostics)
        self.quickAI = QuickAIState(aiProvider: AIProvider(config: config, diagnostics: diagnostics))
        self.mediaDownloads = mediaDownloadManager
        self.widgetBoard.persistenceErrorHandler = { [weak self] error in
            self?.showSettingsPersistenceError(error)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.ensureAgentsSocket()
        }
    }

    private var agentsSocketStarted = false

    private func ensureAgentsSocket() {
        guard agentsSocketStarted == false else { return }
        agentsSocketStarted = true
        agents.startSocket()
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

    @discardableResult
    private func applySetting<Value>(_ keyPath: ReferenceWritableKeyPath<CommandPanelState, Value>, _ value: Value, save: (Value) throws -> Void) -> Bool {
        let previous = self[keyPath: keyPath]
        self[keyPath: keyPath] = value
        do {
            try save(value)
            settingsPersistenceError = nil
            return true
        } catch {
            self[keyPath: keyPath] = previous
            showSettingsPersistenceError(error)
            return false
        }
    }

    func setMenuBarIconVisible(_ visible: Bool) {
        if applySetting(\.showMenuBarIcon, visible, save: configService.updateMenuBarIconVisibility) {
            onMenuBarIconVisibilityChanged?(visible)
        }
    }

    func setLauncherHotkeyFailed(_ failed: Bool) {
        launcherHotkeyFailed = failed
    }

    var launchAtLoginAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier == "com.hridya.foundry"
    }

    var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard launchAtLoginAvailable else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            UserDefaults.standard.set(enabled, forKey: "foundry.launchAtLoginConsent")
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Could not update launch at login: \(error.localizedDescription)"
            diagnostics.log("Launch at login update failed: \(error.localizedDescription)")
        }
    }

    func setMainBrowser(_ browser: BrowserSource) {
        mainBrowser = browser
        UserDefaults.standard.set(browser.rawValue, forKey: "foundry.mainBrowser")
        if browser == .firefox {
            FirefoxConnectorInstaller(diagnostics: diagnostics).requestFirefoxConnector()
        }
    }

    func setThemeIntensity(_ intensity: Double) {
        applySetting(\.themeIntensity, intensity, save: configService.updateThemeIntensity)
    }

    func setPopToRootAfter(_ seconds: Double) {
        applySetting(\.popToRootAfterSeconds, seconds, save: configService.updatePopToRootAfter)
    }

    func setWindowMode(_ mode: WindowMode) {
        applySetting(\.windowMode, mode, save: configService.updateWindowMode)
    }

    var compactCollapsed: Bool {
        windowMode == .compact
            && mode == .search
            && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isShowingActions == false
    }

    private func showSettingsPersistenceError(_ error: Error) {
        settingsPersistenceError = "Preferences could not be saved. Your previous settings were kept."
        diagnostics.log("Settings persistence failed: \(error.localizedDescription)")
    }

    func resetForOpen() {
        let span = diagnostics.startSpan("panel.resetForOpen")
        defer { diagnostics.endSpan(span) }
        detachActiveAction()
        isPanelOpen = true
        ensureAgentsSocket()
        let shouldRestore = lastClosedAt.map { now().timeIntervalSince($0) < popToRootAfterSeconds } ?? false
        isSearchLoading = false
        clipboardHistory.captureIfChanged()
        widgetBoard.start()
        if isAgentShelfVisible {
            agents.start()
        } else {
            agents.stopPolling()
        }
        if shouldRestore {
            isShowingActions = false
            selectedActionID = nil
            if query.isEmpty == false {
                query = ""
                results = []
                selectedResultID = nil
            }
            return
        }
        mode = .search
        resetTransientFeatures()
        clipboardHistory.reset()
        snippets.reset()
        query = ""
        quickAI.resetTransientState()
        results = []
        selectedResultID = nil
        isShowingActions = false
        selectedActionID = nil
    }

    func panelWillClose() {
        detachActiveAction()
        isPanelOpen = false
        lastClosedAt = now()
        homeRefreshID = UUID()
        isSearchLoading = false
        isHomeLoading = false
        searchCoordinator.cancel()
        widgetBoard.stop()
        resetTransientFeatures()
        clipboardHistory.reset()
        snippets.reset()
        agents.stopPolling()
        ClipboardImagePreview.releaseCachedImages()
        AIFormattedText.releaseCachedMarkdown()
    }

    private func resetTransientFeatures() {
        emojiPicker.reset()
        pendingSnippetArguments = nil
        fileConversion.reset()
        camera.stop()
        translator.reset()
        developerTools.reset()
    }

    func shutdown() {
        isPanelOpen = false
        searchCoordinator.cancel()
        commandCatalogTask?.cancel()
        commandCatalogTask = nil
        quickAI.shutdown()
        aiSettings.shutdown()
        cancelActiveAction()
        clipboardHistory.stop()
        agents.stop()
        fileShelf.shutdown()
    }

    func prepareForTermination() async {
        await clipboardHistory.shutdown()
        shutdown()
    }

    func openSettings() {
        if isPanelOpen == false { onOpenSettings?() }
        beginFeatureMode(.settings)
    }

    func openWelcomeGuide() {
        onOpenWelcomeGuide?()
    }

    var commandCatalogCount: Int {
        commandRows.count
    }

    func prepareCommandCatalog(forceRefresh: Bool = false) {
        guard isCommandCatalogLoading == false, forceRefresh || isCommandCatalogReady == false else { return }
        isCommandCatalogLoading = true
        if forceRefresh {
            isCommandCatalogReady = false
        }
        let registry = registry
        let diagnostics = diagnostics
        let span = diagnostics.startSpan("commands.catalog.prepare")
        commandCatalogTask = Task { [weak self] in
            let snapshot = await registry.commandCatalog(forceRefresh: forceRefresh)
            diagnostics.endSpan(span)
            guard let self, Task.isCancelled == false else { return }
            self.commandDescriptors = snapshot.descriptors
            self.commandCatalogFailures = snapshot.providerFailures
            self.isCommandCatalogLoading = false
            self.isCommandCatalogReady = true
            self.rebuildCommandRows()
            self.commandCatalogTask = nil
        }
    }

    func retryCommandCatalog() {
        commandCatalogTask?.cancel()
        commandCatalogTask = nil
        isCommandCatalogLoading = false
        prepareCommandCatalog(forceRefresh: true)
    }

    func resetConfiguration() {
        do {
            try configService.resetToDefaults()
            configLoadError = nil
            NSApp.terminate(nil)
        } catch {
            settingsPersistenceError = "Could not reset Foundry settings. Your existing configuration was kept."
            diagnostics.log("Settings reset failed: \(error.localizedDescription)")
        }
    }

    func exportBackup(to url: URL) {
        do {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
            try FoundryBackup.make(scriptDirectories: ScriptDirectoryStore.shared.directories, appVersion: version).encoded().write(to: url, options: .atomic)
        } catch {
            settingsPersistenceError = "Could not save the backup: \(error.localizedDescription)"
            diagnostics.log("Backup export failed: \(error.localizedDescription)")
        }
    }

    func loadBackup(from url: URL) -> FoundryBackup? {
        do {
            return try FoundryBackup.decode(Data(contentsOf: url))
        } catch {
            settingsPersistenceError = (error as? LocalizedError)?.errorDescription ?? "Could not read the backup."
            return nil
        }
    }

    func restoreBackup(_ backup: FoundryBackup) {
        do {
            try backup.restore()
            NSApp.terminate(nil)
        } catch {
            settingsPersistenceError = "Could not import the backup. Your previous files are kept as .pre-import copies."
            diagnostics.log("Backup import failed: \(error.localizedDescription)")
        }
    }

    func toggleCommandExpansion(_ commandID: String) {
        expandedCommandID = expandedCommandID == commandID ? nil : commandID
    }

    private func rebuildCommandRows() {
        let catalog = CommandSettingsCatalog.build(
            descriptors: commandDescriptors,
            preferences: commandPreferences,
            query: commandSettingsQuery
        )
        commandRows = catalog.rows
        visibleCommandRows = catalog.visibleRows
    }

    func commandPreference(for commandID: String) -> CommandPreference {
        commandPreferences[commandID]
            ?? CommandPreference(isEnabled: CommandRegistry.defaultDisabledCommandIDs.contains(commandID) == false)
    }

    func setCommandEnabled(_ isEnabled: Bool, for commandID: String) {
        var preference = commandPreference(for: commandID)
        preference.isEnabled = isEnabled
        updateCommandPreference(preference, for: commandID)
    }

    func setSearchSensitivity(_ sensitivity: SearchSensitivity) {
        if applySetting(\.searchSensitivity, sensitivity, save: configService.updateSearchSensitivity) {
            refreshResults()
        }
    }

    func setClipboardPaused(_ paused: Bool) {
        var configuration = configService.current.clipboard
        configuration.isPaused = paused
        updateClipboard(configuration)
    }

    var clipboardCaptureEnabled: Bool {
        configService.current.clipboard.isEnabled
    }

    func setClipboardEnabled(_ enabled: Bool) {
        var configuration = configService.current.clipboard
        configuration.isEnabled = enabled
        updateClipboard(configuration)
    }

    var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    func setSnippetExpansionEnabled(_ enabled: Bool) {
        var next = snippetExpansion
        next.isEnabled = enabled
        updateSnippetExpansion(next)
    }

    func setSnippetExpansionExcludedBundleIdentifiers(_ value: String) {
        var next = snippetExpansion
        next.excludedBundleIdentifiers = value.split(separator: ",").map(String.init)
        updateSnippetExpansion(next)
    }

    func requestSnippetExpansionAccessibility() { onRequestSnippetAccessibility?() }
    func openSnippetExpansionPrivacySettings() { onOpenSnippetPrivacySettings?() }

    func setSnippetExpansionError(_ message: String?) { snippetExpansionError = message }

    func setDirectPasteError(_ error: Error) {
        showActionFeedback(.failure("Couldn't paste: \(error.localizedDescription)"))
        diagnostics.log("Direct paste failed: \(error.localizedDescription)")
    }

    private func updateSnippetExpansion(_ next: SnippetExpansionConfig) {
        if applySetting(\.snippetExpansion, next.normalized, save: configService.updateSnippetExpansionConfig) {
            onSnippetExpansionChanged?()
        }
    }

    func setClipboardRetention(maxItems: Int, maxBytes: Int, maxAgeDays: Int? = nil) {
        var configuration = configService.current.clipboard
        configuration.maxItems = maxItems
        configuration.maxBytes = maxBytes
        if let maxAgeDays { configuration.maxAgeDays = maxAgeDays }
        updateClipboard(configuration)
    }

    func setClipboardExcludedBundleIdentifiers(_ value: String) {
        var configuration = configService.current.clipboard
        configuration.excludedBundleIdentifiers = value.split(separator: ",").map(String.init)
        updateClipboard(configuration)
    }

    @discardableResult
    func directPasteSelectedClipboardItem() -> Bool {
        guard let item = clipboardHistory.selectedItem else {
            clipboardHistory.report(ClipboardDirectPasteError.noSelection)
            return false
        }
        do {
            try actionRunner.directPasteService.stage(item.payload)
            return true
        } catch {
            diagnostics.log("Could not stage paste: \(error.localizedDescription)")
            return false
        }
    }

    private(set) var pendingSnippetArguments: [String]?

    @discardableResult
    func directPasteSelectedSnippet(arguments: [String: String] = [:]) -> Bool {
        guard let snippet = snippets.selectedItem else { return false }
        let rendered = SnippetRenderer.render(snippet.content, arguments: arguments)
        do {
            try actionRunner.directPasteService.stage(.text(rendered.text), cursorOffset: rendered.cursorOffsetFromEnd)
            return true
        } catch {
            diagnostics.log("Could not stage snippet: \(error.localizedDescription)")
            return false
        }
    }

    private func updateClipboard(_ configuration: ClipboardConfig) {
        let previous = configService.current.clipboard
        do {
            try configService.updateClipboardConfig(configuration)
            clipboardHistory.updateConfiguration(configService.current.clipboard)
            settingsPersistenceError = nil
        } catch {
            clipboardHistory.updateConfiguration(previous)
            showSettingsPersistenceError(error)
        }
    }

    func setCommandFavorite(_ isFavorite: Bool, for commandID: String) {
        var preference = commandPreference(for: commandID)
        preference.favoriteRank = isFavorite ? nextFavoriteRank() : nil
        updateCommandPreference(preference, for: commandID)
    }

    @discardableResult
    func toggleFavorite(commandID: String) -> Bool {
        let nowFavorite = commandPreferences[commandID]?.favoriteRank == nil
        setCommandFavorite(nowFavorite, for: commandID)
        return nowFavorite
    }

    func isSuggestibleApp(_ result: CommandResult) -> Bool {
        HomeSuggestionRules.isSuggestible(
            resultID: result.id,
            runningBundleIDs: runningAppBundleIDs,
            hasUsage: registry.hasUsage(for: result.id)
        )
    }

    func hasUsage(for resultID: String) -> Bool {
        registry.hasUsage(for: resultID)
    }

    private func refreshFavorites() {
        let favoriteIDs = commandPreferences
            .filter { $0.value.favoriteRank != nil }
            .sorted { ($0.value.favoriteRank ?? 0) < ($1.value.favoriteRank ?? 0) }
            .map(\.key)
        guard favoriteIDs.isEmpty == false else {
            favoriteResults = []
            return
        }
        let registry = registry
        Task { @MainActor [weak self] in
            var resolved: [CommandResult] = []
            for commandID in favoriteIDs.prefix(8) {
                guard let result = await registry.commandResult(for: commandID) else { continue }
                resolved.append(result)
            }
            self?.favoriteResults = resolved
        }
    }

    func setCommandAliases(_ rawAliases: String, for commandID: String) {
        var preference = commandPreference(for: commandID)
        preference.aliases = Self.normalizedCommandAliases(rawAliases)
        updateCommandPreference(preference, for: commandID)
    }

    func setCommandHotkey(_ hotkey: FoundryHotkey?, for commandID: String) {
        var preference = commandPreference(for: commandID)
        preference.globalHotkey = hotkey.map {
            CommandHotkey(keyCode: $0.keyCode, modifiers: $0.modifiers, displayName: $0.displayName)
        }
        updateCommandPreference(preference, for: commandID)
    }

    func setCommandFallbackEligible(_ isEligible: Bool, for commandID: String) {
        var preference = commandPreference(for: commandID)
        preference.fallbackEligible = isEligible
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
            onCommandPreferencesChanged?()
        } catch {
            if let previous {
                commandPreferences[commandID] = previous
            } else {
                commandPreferences.removeValue(forKey: commandID)
            }
            rebuildCommandRows()
            showSettingsPersistenceError(error)
        }
        refreshFavorites()
    }

    func openMediaDownloads() {
        beginFeatureMode(.mediaDownloads)
    }

    func cancelDownload(_ id: UUID) {
        actionRunner.cancel(id)
    }

    func retryDownload(_ item: MediaDownloadItem) {
        guard item.status != .active else { return }
        let action = CommandAction(
            id: "media.download.retry.\(UUID().uuidString)",
            title: "Retry Download",
            kind: .downloadMedia(url: item.sourceURL)
        )
        openMediaDownloads()
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await execute(action, commandID: "media.download.retry")
        }
    }

    func changeMediaDownloadFolder() {
        let action = CommandAction(
            id: "media.download.choose-folder.\(UUID().uuidString)",
            title: "Change Download Folder",
            kind: .chooseMediaDownloadFolder
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await execute(action, commandID: "media.download.choose-folder")
        }
    }

    @discardableResult
    func startMediaDownloads(from value: String) -> Int {
        let urls = MediaDownloadProvider.mediaURLs(in: value)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                var pending = urls[...]
                for _ in 0..<min(3, pending.count) {
                    let url = pending.removeFirst()
                    group.addTask { [weak self] in
                        _ = await self?.execute(Self.mediaDownloadAction(for: url), commandID: "media.download.batch")
                    }
                }
                while await group.next() != nil, pending.isEmpty == false {
                    let url = pending.removeFirst()
                    group.addTask { [weak self] in
                        _ = await self?.execute(Self.mediaDownloadAction(for: url), commandID: "media.download.batch")
                    }
                }
            }
        }
        return urls.count
    }

    private static func mediaDownloadAction(for url: URL) -> CommandAction {
        CommandAction(
            id: "media.download.batch.\(UUID().uuidString)",
            title: "Download",
            kind: .downloadMedia(url: url.absoluteString)
        )
    }

    func openAgents() {
        beginFeatureMode(.agents)
        agents.start()
    }

    func handleEscape() -> Bool {
        if isShowingActions {
            if actionFilter.isEmpty {
                isShowingActions = false
                selectedActionID = nil
            } else {
                actionFilter = ""
            }
            return true
        }
        if mode != .search {
            showHome()
            return true
        }
        return false
    }

    func showHome() {
        detachActiveAction()
        stopTransientPolling()
        searchCoordinator.cancel()
        homeRefreshID = UUID()
        mode = .search
        isSearchLoading = false
        isHomeLoading = false
        resetTransientFeatures()
        query = ""
        quickAI.resetTransientState()
        results = []
        selectedResultID = nil
        isShowingActions = false
        selectedActionID = nil
        widgetBoard.start()
        if isAgentShelfVisible {
            agents.start()
        }
    }

    private func execute(_ action: CommandAction, commandID: String) async -> CommandOutcome {
        if case let .toggleFavorite(id) = action.kind {
            let nowFavorite = toggleFavorite(commandID: id)
            return .stayOpen(message: nowFavorite ? "Added to Favorites" : "Removed from Favorites")
        }
        if case let .openCommandSettings(id) = action.kind {
            pendingSettingsCommandID = id
            open(.settings)
            return .stayOpen(message: nil)
        }
        let request = CommandExecutionRequest(commandID: commandID, action: action)
        let generation = actionGeneration
        activeActionCancellationID = request.invocation.cancellationID
        isActionInProgress = true
        var feedbackShown = false
        var successFeedback: ActionFeedback? = nil
        let outcome = await actionRunner.execute(request) { [weak self] event in
            guard let self, self.actionGeneration == generation, case let .feedback(feedback) = event else { return }
            feedbackShown = true
            if case .success = feedback { successFeedback = feedback }
            showActionFeedback(feedback)
        }
        guard actionGeneration == generation else { return .cancelled }
        isActionInProgress = false
        if activeActionCancellationID == request.invocation.cancellationID {
            activeActionCancellationID = nil
        }
        apply(outcome, feedbackShown: feedbackShown)
        if outcome.shouldDismissPanel, let successFeedback {
            onTransientNotice?(successFeedback)
        }
        return outcome
    }

    private func cancelActiveAction() {
        if let activeActionCancellationID {
            actionRunner.cancel(activeActionCancellationID)
        }
        activeActionCancellationID = nil
        isActionInProgress = false
        actionGeneration &+= 1
    }

    private func detachActiveAction() {
        activeActionCancellationID = nil
        isActionInProgress = false
        actionGeneration &+= 1
    }

    func cancelCurrentAction() {
        cancelActiveAction()
    }

    @discardableResult
    func executeSelectedResult() async -> Bool {
        guard isActionInProgress == false else { return false }
        guard let selectedResult else {
            if let request = AIProvider.request(from: query) {
                openQuickAI(initialPrompt: request.prompt)
            }
            return false
        }
        let action = isShowingActions ? selectedAction : nil
        guard isShowingActions == false || action != nil else { return false }
        let outcome = await executeResult(selectedResult, action: action)
        return outcome.shouldDismissPanel
    }

    private func apply(_ outcome: CommandOutcome, feedbackShown: Bool) {
        switch outcome {
        case let .open(route):
            open(route)
        case let .failure(message, _), let .denied(message):
            if feedbackShown == false { showActionFeedback(.failure(message)) }
        case let .stayOpen(message?):
            if feedbackShown == false { showActionFeedback(.success(message)) }
        case let .refreshResults(message):
            if let message, feedbackShown == false { showActionFeedback(.success(message)) }
            refreshResults()
        case let .fileResults(urls):
            if urls.isEmpty {
                showActionFeedback(.info("No files found"))
            } else {
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
        case let .addToFileShelf(urls):
            let result = fileShelf.add(urls: urls)
            if result.addedCount > 0 {
                showActionFeedback(.success(result.addedCount == 1 ? "Added to File Shelf" : "Added \(result.addedCount) files to File Shelf"))
            } else {
                showActionFeedback(.info("Already in the File Shelf"))
            }
        case let .followUp(actionIDs):
            let availableIDs = Set(selectedActions.map(\.id))
            if let actionID = actionIDs.first(where: { availableIDs.contains($0) }) {
                actionFilter = ""
                isShowingActions = true
                selectedActionID = actionID
            } else {
                showActionFeedback(.info("No follow-up action available"))
            }
        case .success, .cancelled, .stayOpen(nil), .copied, .pasted:
            break
        }
    }

    private func orderedActions(for result: CommandResult) -> [CommandAction] {
        let actions = [result.primaryAction] + result.secondaryActions
        guard let preferredID = configService.current.commandPreferences[result.id]?.preferredPrimaryActionID,
              let preferredIndex = actions.firstIndex(where: { $0.id == preferredID }) else {
            return actions
        }
        let preferred = actions[preferredIndex]
        return [preferred] + actions.enumerated().compactMap { index, action in
            index == preferredIndex ? nil : action
        }
    }

    private func preferredAction(for result: CommandResult) -> CommandAction {
        orderedActions(for: result).first ?? result.primaryAction
    }

    private func open(_ route: CommandRoute) {
        switch route {
        case let .quickAI(initialPrompt):
            openQuickAI(initialPrompt: initialPrompt)
        case .emojiPicker:
            openEmojiPicker()
        case .fileShelf:
            openFileShelf()
        case .clipboardHistory:
            openClipboardHistory()
        case .snippets:
            openSnippets()
        case let .fileConversion(path):
            openFileConverter(path: path)
        case .camera:
            openCamera()
        case let .translator(text, language):
            openTranslator(text: text, language: language)
        case let .developerTools(tool):
            openDeveloperTools(tool: tool)
        case .settings:
            openSettings()
        case .home:
            showHome()
        case .mediaDownloads:
            openMediaDownloads()
        case .welcomeGuide:
            openWelcomeGuide()
        case let .query(text):
            query = text
        }
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
        actionFilter = ""
        isShowingActions.toggle()
        selectedActionID = isShowingActions ? selectedActions.first?.id : nil
    }

    func performModeShortcut(_ shortcut: ActionShortcut, dismiss: @escaping @MainActor () -> Void) -> Bool {
        guard shortcut.modifiers == [.command] else { return false }
        if mode == .search, shortcut.key == "y",
           let id = selectedResult?.id, id.hasPrefix("file.") {
            onQuickLook?(URL(fileURLWithPath: String(id.dropFirst("file.".count))))
            return true
        }
        if mode == .quickAI {
            switch shortcut.key {
            case "n": openQuickAI()
            case ".": quickAI.stop()
            default: return false
            }
            return true
        }
        if mode == .developerTools {
            let tools = DeveloperToolsState.Tool.allCases
            guard let index = Int(shortcut.key), tools.indices.contains(index - 1) else { return false }
            developerTools.selectedTool = tools[index - 1]
            return true
        }
        if mode == .snippets {
            guard shortcut.key == "\r", snippets.selectedItem != nil else { return false }
            snippets.copySelected()
            showActionFeedback(.success("Copied snippet"))
            dismiss()
            return true
        }
        if mode == .translator {
            guard shortcut.key == "s" else { return false }
            translator.swapLanguages()
            return true
        }
        if mode == .emojiPicker {
            guard shortcut.key == "t" else { return false }
            emojiPicker.cycleSkinTone()
            return true
        }
        guard mode == .clipboardHistory else { return false }
        let filters = ClipboardHistoryState.KindFilter.allCases
        switch shortcut.key {
        case "\r":
            guard clipboardHistory.selectedItem != nil else { return false }
            clipboardHistory.copySelected()
            dismiss()
        case "p":
            clipboardHistory.togglePinSelected()
        case let key where Int(key).map { (1...filters.count).contains($0) } == true:
            clipboardHistory.kindFilter = filters[Int(key)! - 1]
        default:
            return false
        }
        return true
    }

    @discardableResult
    func insertTranslation() -> Bool {
        guard translator.result.isEmpty == false else { return false }
        do {
            try actionRunner.directPasteService.stage(.text(translator.result), cursorOffset: 0)
            return true
        } catch {
            diagnostics.log("Could not stage paste: \(error.localizedDescription)")
            return false
        }
    }

    func insertOrCopySelectedSnippet() -> Bool {
        guard let snippet = snippets.selectedItem else { return false }
        let names = SnippetRenderer.argumentNames(in: snippet.content)
        if names.isEmpty == false {
            pendingSnippetArguments = names
            return false
        }
        if directPasteSelectedSnippet() == false { snippets.copySelected() }
        return true
    }

    func cancelSnippetArguments() { pendingSnippetArguments = nil }

    @discardableResult
    func submitSnippetArguments(_ values: [String: String]) -> Bool {
        pendingSnippetArguments = nil
        return directPasteSelectedSnippet(arguments: values)
    }

    func pasteOrCopySelectedClipboardItem() {
        if directPasteSelectedClipboardItem() == false { clipboardHistory.copySelected() }
    }

    func performActionShortcut(_ shortcut: ActionShortcut, dismiss: @escaping @MainActor () -> Void) -> Bool {
        guard mode == .search, isActionInProgress == false, let result = selectedResult,
              let actionID = actionShortcuts.first(where: { $0.value == shortcut })?.key,
              let action = selectedActions.first(where: { $0.id == actionID }) else { return false }
        Task { @MainActor in
            if await executeResult(result, action: action).shouldDismissPanel { dismiss() }
        }
        return true
    }

    func pasteFromClipboard() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string), text.isEmpty == false else { return false }
        switch mode {
        case .search:
            query += text
        case .emojiPicker:
            emojiPicker.query += text
        case .clipboardHistory:
            clipboardHistory.query += text
        case .snippets:
            snippets.query += text
        case .translator:
            translator.sourceText += text
        case .camera, .fileConversion, .fileShelf, .mediaDownloads, .developerTools, .quickAI, .agents, .settings:
            return false
        }
        return true
    }

    func handleDroppedFiles(_ urls: [URL]) {
        let result = fileShelf.add(urls: urls)
        guard result.didReceiveFiles else {
            showActionFeedback(.failure("Couldn't add those files"))
            return
        }

        if result.addedCount > 0 {
            let noun = result.addedCount == 1 ? "file" : "files"
            let duplicateSuffix = result.duplicateCount > 0 ? " · \(result.duplicateCount) already waiting" : ""
            let rejectedSuffix = result.rejectedCount > 0 ? " · \(result.rejectedCount) unsupported" : ""
            showActionFeedback(.success("Added \(result.addedCount) \(noun) to File Shelf\(duplicateSuffix)\(rejectedSuffix)"))
        } else if result.duplicateCount > 0 {
            let noun = result.duplicateCount == 1 ? "file is" : "files are"
            showActionFeedback(.info("Those \(noun) already on File Shelf"))
        } else {
            showActionFeedback(.failure("Couldn't add those files"))
        }

        if mode == .search {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                refreshHomeResults()
            }
        } else if mode != .fileShelf, result.addedCount > 0 {
            openFileShelf()
        }
    }

    func moveSelectionDown() {
        moveSelection(offset: 1)
    }

    func moveSelectionUp() {
        moveSelection(offset: -1)
    }

    private func moveSelection(offset: Int) {
        switch mode {
        case .emojiPicker: offset > 0 ? emojiPicker.moveDown() : emojiPicker.moveUp(); return
        case .fileShelf: fileShelf.moveSelection(offset: offset); return
        case .snippets: snippets.moveSelection(offset: offset); return
        case .clipboardHistory: clipboardHistory.moveSelection(offset: offset); return
        case .fileConversion, .camera, .translator, .settings: return
        case .search, .mediaDownloads, .developerTools, .quickAI, .agents: break
        }

        if isShowingActions {
            let actions = visibleActions
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
        searchCoordinator.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        isShowingActions = false
        selectedActionID = nil
        guard trimmed.isEmpty == false else {
            isSearchLoading = false
            results = []
            selectedResultID = nil
            refreshHomeResults()
            return
        }

        isHomeLoading = false
        isSearchLoading = true

        if AIProvider.request(from: trimmed) != nil {
            isSearchLoading = false
            results = []
            selectedResultID = nil
            return
        }

        searchCoordinator.search(
            query: trimmed,
            onImmediate: { [weak self] immediateResults in
                guard let self else { return }
                self.selectedResultID = nil
                self.applySearchResults(immediateResults, preserving: nil)
            },
            onComplete: { [weak self] completeResults in
                guard let self else { return }
                self.isSearchLoading = false
                self.applySearchResults(completeResults, preserving: self.selectedResultID)
            }
        )
    }

    private func applySearchResults(_ rankedResults: [CommandResult], preserving preferredID: String?) {
        let nextResults = ResultSection.ordered(rankedResults)
        results = nextResults
        if MediaDownloadProvider.mediaURLs(in: query).isEmpty == false,
           let mediaResult = nextResults.first(where: { $0.route == .mediaDownload }) {
            selectedResultID = mediaResult.id
        } else if let preferredID, nextResults.contains(where: { $0.id == preferredID }) {
            selectedResultID = preferredID
        } else if selectedResultID == nil || nextResults.contains(where: { $0.id == selectedResultID }) == false {
            selectedResultID = nextResults.first?.id
        }
        selectionScrollToken = UUID()
    }

    private func refreshHomeResults() {
        let refreshID = UUID()
        homeRefreshID = refreshID
        isHomeLoading = true
        searchCoordinator.loadHome { [weak self] loadedResults in
            guard let self,
                  self.homeRefreshID == refreshID,
                  self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            var homeResults = loadedResults
            if self.fileShelf.files.isEmpty == false {
                homeResults.removeAll { $0.id == "foundry.file-shelf" }
            }
            self.runningAppBundleIDs = Self.regularRunningAppBundleIDs()
            self.results = homeResults
            self.selectedResultID = homeResults.first?.id
            self.selectionScrollToken = UUID()
            self.isHomeLoading = false
            self.refreshFavorites()
        }
    }

    private static func regularRunningAppBundleIDs() -> Set<String> {
        RunningAppsSnapshot.bundleIDs(regularOnly: true)
    }

    private func stopTransientPolling() {
        widgetBoard.stop()
        agents.stopPolling()
    }

    private func beginFeatureMode(_ nextMode: Mode) {
        stopTransientPolling()
        homeRefreshID = UUID()
        isSearchLoading = false
        isHomeLoading = false
        mode = nextMode
        isShowingActions = false
        selectedActionID = nil
        searchCoordinator.cancel()
        results = []
        selectedResultID = nil
    }

    private func openEmojiPicker() {
        beginFeatureMode(.emojiPicker)
        emojiPicker.reset()
    }

    func openFileShelf() {
        beginFeatureMode(.fileShelf)
        fileShelf.selectFirst()
    }

    func openClipboardHistory() {
        beginFeatureMode(.clipboardHistory)
        clipboardHistory.reset()
    }

    private func openSnippets() {
        beginFeatureMode(.snippets)
        snippets.reset()
        pendingSnippetArguments = nil
    }

    private func openFileConverter(path: String? = nil) {
        beginFeatureMode(.fileConversion)
        fileConversion.reset()
        if let path {
            fileConversion.setSource(url: URL(fileURLWithPath: path))
        } else if fileShelf.selectedFiles.isEmpty == false {
            fileConversion.setSources(urls: fileShelf.selectedFiles.map(\.url))
        }
    }

    private func openCamera() {
        beginFeatureMode(.camera)
        camera.start()
    }

    private func openTranslator(text: String? = nil, language: String? = nil) {
        beginFeatureMode(.translator)
        translator.reset()
        if let text { translator.sourceText = text }
        if let language { translator.targetLanguage = language.capitalized }
    }

    private func openDeveloperTools(tool: String? = nil) {
        beginFeatureMode(.developerTools)
        developerTools.reset()
        if let tool, let selectedTool = DeveloperToolsState.Tool(commandID: tool) {
            developerTools.selectedTool = selectedTool
        }
    }

    func openQuickAI(initialPrompt: String = "") {
        beginFeatureMode(.quickAI)
        quickAI.startNewThread(initialPrompt: initialPrompt, selectedAIProfileID: aiSettings.defaultAIProfileID)
    }

    @discardableResult
    func executeResult(_ result: CommandResult, action override: CommandAction? = nil) async -> CommandOutcome {
        guard isActionInProgress == false else { return .cancelled }
        let action = override ?? preferredAction(for: result)
        if case .downloadMedia = action.kind {
            openMediaDownloads()
        } else if case .downloadMediaBatch = action.kind {
            openMediaDownloads()
        }
        diagnostics.log("Executing action \(action.id) for result \(result.id)")
        registry.recordExecution(resultID: result.id, query: query)
        onResultExecuted?()
        let outcome = await execute(action, commandID: result.id)
        if case .copied = outcome, result.route == .calculator {
            let expression = result.subtitle?.components(separatedBy: " · ").first ?? ""
            CalculatorHistoryStore.shared.record(expression: expression, result: result.title)
        }
        return outcome
    }

    func executeCommand(commandID: String) async {
        guard let result = await registry.commandResult(for: commandID) else {
            diagnostics.log("Command hotkey target is unavailable: \(commandID)")
            showActionFeedback(.failure("That command is no longer available"))
            return
        }
        results = [result]
        selectedResultID = result.id
        isShowingActions = false
        selectedActionID = nil
        await executeResult(result)
    }

}

private enum ClipboardDirectPasteError: LocalizedError {
    case noSelection
    var errorDescription: String? { "Select an item to paste." }
}
