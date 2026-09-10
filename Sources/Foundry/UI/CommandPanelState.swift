import AppKit
import Foundation
import SwiftUI
import FoundryDomain
import FoundryServices

@MainActor
final class CommandPanelState: ObservableObject {
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
        case settings
        case mediaDownloads
    }

    @Published var query = "" {
        didSet { refreshResults() }
    }
    @Published var results: [CommandResult] = []
    @Published var selectedResultID: String?
    @Published private(set) var selectionScrollToken = UUID()
    @Published var isShowingActions = false
    @Published var selectedActionID: String?
    @Published var diagnosticsSummary = "IDLE"
    @Published var mode: Mode = .search
    @Published var focusToken = UUID()
    @Published private(set) var isSearchLoading = false
    @Published private(set) var isHomeLoading = false
    @Published var hoverHighlightsArmed = true
    @Published private(set) var actionFeedback: ActionFeedback? = nil
    @Published var isAgentShelfVisible: Bool
    @Published var hotkey: FoundryHotkey
    @Published var hotkeyError: String? = nil
    @Published var themeIntensity: Double
    @Published var searchSensitivity: SearchSensitivity
    @Published var settingsPersistenceError: String?
    @Published private(set) var snippetExpansion: SnippetExpansionConfig
    @Published private(set) var snippetExpansionError: String?
    @Published var commandSettingsQuery = "" {
        didSet { rebuildCommandRows() }
    }
    @Published private(set) var commandDescriptors: [CommandDescriptor] = []
    @Published private(set) var commandPreferences: [String: CommandPreference]
    @Published private(set) var commandRows: [CommandSettingsRowModel] = []
    @Published private(set) var visibleCommandRows: [CommandSettingsRowModel] = []
    @Published private(set) var commandCatalogFailures: [String] = []
    @Published private(set) var isCommandCatalogLoading = false
    @Published private(set) var isCommandCatalogReady = false
    @Published private(set) var configLoadError: String?
    @Published var expandedCommandID: String?
    var onHotkeyChanged: ((FoundryHotkey) throws -> Void)?
    var onCommandPreferencesChanged: (() -> Void)?

    let emojiPicker = EmojiPickerState()
    let fileShelf = FileShelfState()
    let agents = AgentMonitorState()
    let clipboardHistory: ClipboardHistoryState
    let snippets: SnippetState
    let fileConversion = FileConversionState()
    let camera = CameraPreviewState()
    let translator = TranslatorState()
    let developerTools = DeveloperToolsState()
    let widgetBoard: WidgetBoardState
    let aiSettings: AISettingsState
    let quickAI: QuickAIState
    let mediaDownloads: MediaDownloadManager
    private let configService: ConfigService

    private let registry: CommandRegistry
    private let searchCoordinator: CommandSearchCoordinator
    private let actionRunner: ActionRunner
    private let diagnostics: DiagnosticsService
    private var activeActionCancellationID: UUID?
    private var actionGeneration = 0
    @Published private(set) var isActionInProgress = false
    private var feedbackTask: Task<Void, Never>?
    private var commandCatalogTask: Task<Void, Never>?
    private var isPanelOpen = false
    private var homeRefreshID = UUID()

    var selectedResult: CommandResult? {
        results.first { $0.id == selectedResultID }
    }

    var selectedActions: [CommandAction] {
        guard let selectedResult else { return [] }
        return orderedActions(for: selectedResult)
            + [CommandAction(
                id: "ranking.reset.\(selectedResult.id)",
                title: "Reset Ranking",
                kind: .resetRanking(commandID: selectedResult.id)
            )]
    }

    var selectedAction: CommandAction? {
        selectedActions.first { $0.id == selectedActionID }
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
        self.hotkey = config.current.hotkey
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

    func setAgentShelfVisible(_ isVisible: Bool) {
        guard isAgentShelfVisible != isVisible else { return }
        let previous = isAgentShelfVisible
        isAgentShelfVisible = isVisible
        do {
            try configService.updateAgentShelfVisibility(isVisible)
            settingsPersistenceError = nil
            if isPanelOpen {
                if isVisible {
                    agents.start()
                } else {
                    agents.stopPolling()
                }
            }
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

    private func showSettingsPersistenceError(_ error: Error) {
        settingsPersistenceError = "Preferences could not be saved. Your previous settings were kept."
        diagnostics.log("Settings persistence failed: \(error.localizedDescription)")
    }

    func resetForOpen() {
        detachActiveAction()
        isPanelOpen = true
        mode = .search
        isSearchLoading = false
        widgetBoard.start()
        if isAgentShelfVisible {
            agents.start()
        } else {
            agents.stopPolling()
        }
        emojiPicker.reset()
        clipboardHistory.reset()
        snippets.reset()
        fileConversion.reset()
        camera.stop()
        translator.reset()
        developerTools.reset()
        query = ""
        quickAI.resetTransientState()
        results = []
        selectedResultID = nil
        isShowingActions = false
        selectedActionID = nil
        refreshStatusSummary()
    }

    func panelWillClose() {
        detachActiveAction()
        isPanelOpen = false
        homeRefreshID = UUID()
        isSearchLoading = false
        isHomeLoading = false
        searchCoordinator.cancel()
        widgetBoard.stop()
        emojiPicker.reset()
        clipboardHistory.reset()
        snippets.reset()
        fileConversion.reset()
        camera.stop()
        translator.reset()
        developerTools.reset()
        agents.stopPolling()
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
        beginFeatureMode(.settings, status: "settings")
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

    func setClipboardPaused(_ paused: Bool) {
        var configuration = configService.current.clipboard
        configuration.isPaused = paused
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

    func requestSnippetExpansionAccessibility() { NotificationCenter.default.post(name: .foundryRequestSnippetAccessibility, object: nil) }
    func openSnippetExpansionPrivacySettings() { NotificationCenter.default.post(name: .foundryOpenSnippetPrivacy, object: nil) }

    func setSnippetExpansionError(_ message: String?) { snippetExpansionError = message }

    func setDirectPasteError(_ error: Error) {
        diagnosticsSummary = "Could not complete paste: \(error.localizedDescription)"
        diagnostics.log("Direct paste failed: \(error.localizedDescription)")
    }

    private func updateSnippetExpansion(_ next: SnippetExpansionConfig) {
        let previous = snippetExpansion
        snippetExpansion = next.normalized
        do {
            try configService.updateSnippetExpansionConfig(snippetExpansion)
            settingsPersistenceError = nil
            NotificationCenter.default.post(name: .foundrySnippetExpansionChanged, object: nil)
        } catch {
            snippetExpansion = previous
            showSettingsPersistenceError(error)
        }
    }

    func setClipboardRetention(maxItems: Int, maxBytes: Int) {
        var configuration = configService.current.clipboard
        configuration.maxItems = maxItems
        configuration.maxBytes = maxBytes
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
            diagnosticsSummary = "Could not stage paste: \(ClipboardDirectPasteError.noSelection.localizedDescription)"
            return false
        }
        do {
            try actionRunner.directPasteService.stage(item.payload)
            return true
        } catch {
            diagnosticsSummary = "Could not stage paste: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func directPasteSelectedSnippet() -> Bool {
        guard let snippet = snippets.selectedItem else { return false }
        let rendered = SnippetRenderer.render(snippet.content)
        do {
            try actionRunner.directPasteService.stage(.text(rendered.text), cursorOffset: rendered.cursorOffsetFromEnd, snippetID: snippet.id)
            diagnosticsSummary = "Snippet ready to insert"
            return true
        } catch {
            diagnosticsSummary = "Could not stage snippet: \(error.localizedDescription)"
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
    }

    func openHome() {
        showHome()
    }

    func openMediaDownloads() {
        beginFeatureMode(.mediaDownloads, status: "downloads")
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
        for url in urls {
            let action = CommandAction(
                id: "media.download.batch.\(UUID().uuidString)",
                title: "Download",
                kind: .downloadMedia(url: url.absoluteString)
            )
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await execute(action, commandID: "media.download.batch")
            }
        }
        return urls.count
    }

    func openAgents() {
        beginFeatureMode(.agents, status: "agents")
        agents.start()
    }

    func handleEscape() -> Bool {
        if mode != .search || isShowingActions {
            backToSearch()
            return true
        }
        return false
    }

    func backToSearch() {
        showHome()
    }

    func showHome() {
        detachActiveAction()
        stopTransientPolling()
        searchCoordinator.cancel()
        homeRefreshID = UUID()
        mode = .search
        isSearchLoading = false
        isHomeLoading = false
        emojiPicker.reset()
        camera.stop()
        fileConversion.reset()
        translator.reset()
        developerTools.reset()
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
        refreshStatusSummary()
    }

    private func execute(_ action: CommandAction, commandID: String) async -> CommandOutcome {
        let request = CommandExecutionRequest(commandID: commandID, action: action)
        let generation = actionGeneration
        activeActionCancellationID = request.invocation.cancellationID
        isActionInProgress = true
        let outcome = await actionRunner.execute(request) { [weak self] event in
            guard let self else { return }
            guard self.actionGeneration == generation else { return }
            switch event {
            case let .status(message):
                diagnosticsSummary = message
            case let .downloadProgress(progress):
                diagnosticsSummary = progress.message
            case let .feedback(feedback):
                showActionFeedback(feedback)
            }
        }
        guard actionGeneration == generation else { return .cancelled }
        isActionInProgress = false
        if activeActionCancellationID == request.invocation.cancellationID {
            activeActionCancellationID = nil
        }
        apply(outcome)
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
        diagnosticsSummary = "Cancelled"
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

    private func apply(_ outcome: CommandOutcome) {
        switch outcome {
        case let .open(route):
            open(route)
        case let .success(message):
            if let message { diagnosticsSummary = message }
            refreshStatusSummary(fallback: message ?? "")
        case let .failure(message, _):
            diagnosticsSummary = message
        case let .denied(message):
            diagnosticsSummary = message
        case .cancelled:
            refreshStatusSummary()
        case let .stayOpen(message):
            if let message { diagnosticsSummary = message }
        case let .refreshResults(message):
            if let message { diagnosticsSummary = message }
            refreshResults()
        case let .fileResults(urls):
            if urls.isEmpty {
                diagnosticsSummary = "No files returned"
            } else {
                NSWorkspace.shared.activateFileViewerSelecting(urls)
                diagnosticsSummary = "Opened \(urls.count) file\(urls.count == 1 ? "" : "s")"
            }
        case let .followUp(actionIDs):
            let availableIDs = Set(selectedActions.map(\.id))
            if let actionID = actionIDs.first(where: { availableIDs.contains($0) }) {
                isShowingActions = true
                selectedActionID = actionID
                diagnosticsSummary = "Choose a follow-up action"
            } else {
                diagnosticsSummary = "No follow-up action available"
            }
        case .copied, .pasted:
            refreshStatusSummary()
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
            openHome()
        case .mediaDownloads:
            openMediaDownloads()
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
        isShowingActions.toggle()
        selectedActionID = isShowingActions ? selectedActions.first?.id : nil
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
        case .camera, .fileConversion, .fileShelf, .settings, .mediaDownloads, .developerTools, .quickAI, .agents:
            return false
        }
        return true
    }

    func showFileShelf() {
        openFileShelf()
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
        searchCoordinator.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        isShowingActions = false
        selectedActionID = nil
        guard trimmed.isEmpty == false else {
            isSearchLoading = false
            results = []
            selectedResultID = nil
            refreshStatusSummary()
            refreshHomeResults()
            return
        }

        isHomeLoading = false
        isSearchLoading = true

        if AIProvider.request(from: trimmed) != nil {
            isSearchLoading = false
            results = []
            selectedResultID = nil
            refreshStatusSummary(fallback: "Press Tab or Return to ask AI")
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

    private func applySearchResults(_ nextResults: [CommandResult], preserving preferredID: String?) {
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
        refreshStatusSummary()
    }

    private func refreshStatusSummary(fallback: String = "") {
        guard isActionInProgress == false else { return }
        diagnosticsSummary = registry.statusSummary(resultCount: results.count, fallback: fallback)
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
            self.results = homeResults
            self.selectedResultID = homeResults.first?.id
            self.selectionScrollToken = UUID()
            self.isHomeLoading = false
            self.refreshStatusSummary()
        }
    }

    private func stopTransientPolling() {
        widgetBoard.stop()
        agents.stopPolling()
    }

    private func beginFeatureMode(_ nextMode: Mode, status: String) {
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
        diagnosticsSummary = status
    }

    private func openEmojiPicker() {
        beginFeatureMode(.emojiPicker, status: "emoji & symbols")
        emojiPicker.reset()
    }

    private func openFileShelf() {
        beginFeatureMode(.fileShelf, status: "file shelf")
        fileShelf.selectFirst()
    }

    private func openClipboardHistory() {
        beginFeatureMode(.clipboardHistory, status: "clipboard history")
        clipboardHistory.reset()
    }

    private func openSnippets() {
        beginFeatureMode(.snippets, status: "snippets")
        snippets.reset()
    }

    private func openFileConverter(path: String? = nil) {
        beginFeatureMode(.fileConversion, status: "file converter")
        fileConversion.reset()
        if let path {
            fileConversion.setSource(url: URL(fileURLWithPath: path))
        } else if fileShelf.selectedFiles.isEmpty == false {
            fileConversion.setSources(urls: fileShelf.selectedFiles.map(\.url))
        }
    }

    private func openCamera() {
        beginFeatureMode(.camera, status: "camera")
        camera.start()
    }

    private func openTranslator(text: String? = nil, language: String? = nil) {
        beginFeatureMode(.translator, status: "translator")
        translator.reset()
        if let text { translator.sourceText = text }
        if let language { translator.targetLanguage = language.capitalized }
    }

    private func openDeveloperTools(tool: String? = nil) {
        beginFeatureMode(.developerTools, status: "developer tools")
        developerTools.reset()
        if let tool, let selectedTool = DeveloperToolsState.Tool(commandID: tool) {
            developerTools.selectedTool = selectedTool
        }
    }

    func openQuickAI(initialPrompt: String = "") {
        mode = .quickAI
        searchCoordinator.cancel()
        results = []
        selectedResultID = nil
        isShowingActions = false
        selectedActionID = nil
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
        return await execute(action, commandID: result.id)
    }

    func executeCommand(commandID: String) async {
        guard let result = await registry.commandResult(for: commandID) else {
            diagnostics.log("Command hotkey target is unavailable: \(commandID)")
            diagnosticsSummary = "Command unavailable"
            return
        }
        results = [result]
        selectedResultID = result.id
        isShowingActions = false
        selectedActionID = nil
        diagnosticsSummary = result.title
        await executeResult(result)
    }

}

extension Notification.Name {
    static let foundryRequestSnippetAccessibility = Notification.Name("foundry.requestSnippetAccessibility")
    static let foundryOpenSnippetPrivacy = Notification.Name("foundry.openSnippetPrivacy")
    static let foundrySnippetExpansionChanged = Notification.Name("foundry.snippetExpansionChanged")
}

private enum ClipboardDirectPasteError: LocalizedError {
    case noSelection
    var errorDescription: String? { "Select an item to paste." }
}
