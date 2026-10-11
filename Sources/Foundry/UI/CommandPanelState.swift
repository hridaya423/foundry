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
    var results: [CommandResult] = [] {
        didSet {
            // Warm the icon cache for the visible head of the list so rows
            // render the real icon on their first frame, not a placeholder.
            let head = results.prefix(12)
            CommandIconRepository.shared.prewarm(
                paths: head.compactMap(\.icon.filePath),
                remoteURLs: head.compactMap(\.icon.remoteIconURL)
            )
        }
    }
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
    var openWithTask: Task<Void, Never>?
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
    var isSearchLoading = false
    /// Immediate-phase head results, so the complete phase can merge under
    /// them instead of reordering rows the user may already be reading.
    private var immediatePrefixIDs: [String] = []
    private var immediateAppliedAt: ContinuousClock.Instant?
    private var selectionAfterImmediate: String?
    var isHomeLoading = false
    var hoverHighlightsArmed = true
    private(set) var actionFeedback: ActionFeedback? = nil
    var isAgentShelfVisible: Bool
    var hotkey: FoundryHotkey
    var hotkeyError: String? = nil
    var launcherHotkeyFailed = false
    var showMenuBarIcon: Bool
    var hapticsEnabled: Bool
    var popToRootAfterSeconds: Double
    var windowMode: WindowMode
    var launchAtLoginError: String?
    var mainBrowser: BrowserSource?
    var themeIntensity: Double
    var searchSensitivity: SearchSensitivity
    var settingsPersistenceError: String?
    var snippetExpansion: SnippetExpansionConfig
    var snippetExpansionError: String?
    var commandSettingsQuery = "" {
        didSet { rebuildCommandRows() }
    }
    var commandDescriptors: [CommandDescriptor] = []
    var commandPreferences: [String: CommandPreference]
    var commandRows: [CommandSettingsRowModel] = []
    var visibleCommandRows: [CommandSettingsRowModel] = []
    var commandCatalogFailures: [String] = []
    var isCommandCatalogLoading = false
    var isCommandCatalogReady = false
    var configLoadError: String?
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
    @ObservationIgnored lazy var fileConversion: FileConversionState = {
        let state = FileConversionState()
        state.onFirstSuccess = { [weak self] in
            self?.confettiBurstID &+= 1
            self?.performHaptic(.alignment)
        }
        state.onConversionCompleted = { [weak self] in
            self?.performHaptic(.levelChange)
        }
        state.onQuickLookOutput = { [weak self] url in
            self?.actionRunner.onQuickLook?(url)
        }
        state.onShareOutput = { [weak self] url in
            self?.actionRunner.shareFile(at: url)
        }
        return state
    }()
    @ObservationIgnored lazy var camera = CameraPreviewState()
    @ObservationIgnored lazy var translator = TranslatorState()
    @ObservationIgnored lazy var developerTools = DeveloperToolsState()
    let widgetBoard: WidgetBoardState
    let aiSettings: AISettingsState
    let quickAI: QuickAIState
    let mediaDownloads: MediaDownloadManager
    let installedBrowsers: [BrowserSource]
    let configService: ConfigService

    let registry: CommandRegistry
    let searchCoordinator: CommandSearchCoordinator
    let actionRunner: ActionRunner
    let diagnostics: DiagnosticsService
    private var activeActionCancellationID: UUID?
    private var actionGeneration = 0
    private(set) var isActionInProgress = false
    var feedbackTask: Task<Void, Never>?
    private var commandCatalogTask: Task<Void, Never>?
    var isPanelOpen = false
    var homeRefreshID = UUID()
    private var searchKeySpan: DiagnosticsService.Span?

    var favoriteResults: [CommandResult] = []
    private(set) var runningAppBundleIDs: Set<String> = []

    var selectedResult: CommandResult? {
        navigableResults.first { $0.id == selectedResultID } ?? results.first { $0.id == selectedResultID }
    }

    /// The flat list the view renders in search mode, in render order.
    /// Arrow-key navigation must walk this — never raw `results`, or rows the
    /// view filtered out (non-suggestible apps, hidden window layouts,
    /// suppressed file-shelf entry) steal the selection invisibly.
    var navigableResults: [CommandResult] {
        guard mode == .search else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let sections = homeSections
            return sections.suggestions + sections.commands
        }
        var list = searchListResults
        if let selectedResultID, Self.isPromotedCalculatorID(selectedResultID) {
            list += Self.calculatorFallbackResults
        }
        return list
    }

    /// `results` minus rows the view does not paint when a calculator answer
    /// is promoted to its card, or when the shelf holds files.
    var searchListResults: [CommandResult] {
        var list = results
        if let selectedID = selectedResultID, Self.isPromotedCalculatorID(selectedID) {
            list = list.filter { $0.id != selectedID && $0.id.hasPrefix("calculator.convert.") == false }
        }
        if mode == .search, fileShelf.files.isEmpty == false, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            list = list.filter { $0.id != "foundry.file-shelf" }
        }
        return list
    }

    struct HomeSections {
        var suggestions: [CommandResult] = []
        var commands: [CommandResult] = []
    }

    var homeSections: HomeSections {
        var sections = HomeSections()
        for result in searchListResults {
            if case .openApp = result.primaryAction.kind {
                if isSuggestibleApp(result), sections.suggestions.count < 5 {
                    sections.suggestions.append(result)
                }
            } else if isPrimaryWindowLayoutResult(result) == false, sections.commands.count < 5 {
                sections.commands.append(result)
            }
            if sections.suggestions.count >= 5, sections.commands.count >= 5 { break }
        }
        return sections
    }

    private func isPrimaryWindowLayoutResult(_ result: CommandResult) -> Bool {
        guard case let .tileWindow(placement) = result.primaryAction.kind else { return false }
        return [FoundryDomain.WindowPlacement.leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize, .restore].contains(placement)
    }

    /// `calculator.*` rows promote to the answer card; the `calculator.fallback.*`
    /// rows offered under it are ordinary list rows, not promotions.
    static func isPromotedCalculatorID(_ id: String) -> Bool {
        id.hasPrefix("calculator.") && id.hasPrefix("calculator.fallback.") == false
    }

    /// Static rows offered under a promoted calculator answer. Real
    /// CommandResults so arrow keys reach them like anything else.
    static let calculatorFallbackResults: [CommandResult] = [
        CommandResult(
            id: "calculator.fallback.clipboard",
            title: "Clipboard History",
            subtitle: "Search copied text, files, and images",
            icon: CommandIcon(fallback: "CB", systemName: "doc.on.clipboard"),
            primaryAction: CommandAction(id: "calculator.fallback.clipboard.open", title: "Open", kind: .openClipboardHistory),
            secondaryActions: []
        ),
        CommandResult(
            id: "calculator.fallback.fileshelf",
            title: "File Shelf",
            subtitle: "Hold files for quick actions",
            icon: CommandIcon(fallback: "FS", systemName: "tray.full"),
            primaryAction: CommandAction(id: "calculator.fallback.fileshelf.open", title: "Open", kind: .openFileShelf),
            secondaryActions: []
        ),
        CommandResult(
            id: "calculator.fallback.settings",
            title: "Open Foundry Settings",
            subtitle: "Customize Home, commands, and Foundry preferences",
            icon: CommandIcon(fallback: "ST", systemName: "slider.horizontal.3"),
            primaryAction: CommandAction(id: "calculator.fallback.settings.open", title: "Open", kind: .openSettings),
            secondaryActions: []
        ),
    ]

    /// Favorites/Reset Ranking/Configure only make sense on durable commands
    /// and apps — not on ephemeral rows like files, clipboard items,
    /// calculator answers, or one-shot Ask-AI prompts.
    private func supportsMetaActions(_ result: CommandResult) -> Bool {
        ["file.", "clipboard.", "calculator.", "foundry.quick."].contains { result.id.hasPrefix($0) } == false
    }

    var selectedActions: [CommandAction] {
        guard let selectedResult else { return [] }
        let isFavorite = commandPreferences[selectedResult.id]?.favoriteRank != nil
        let metaActions = supportsMetaActions(selectedResult)
            ? [CommandAction(
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
            : [CommandAction]()
        return orderedActions(for: selectedResult)
            + openWithActions
            + metaActions
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
        self.hapticsEnabled = config.current.hapticsEnabled
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

    func showActionFeedback(_ feedback: ActionFeedback) {
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


    var launchAtLoginAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier == "com.hridya.foundry"
    }

    var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }


    var compactCollapsed: Bool {
        windowMode == .compact
            && mode == .search
            && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isShowingActions == false
    }


    func resetForOpen() {
        let span = diagnostics.startSpan("panel.resetForOpen")
        defer { diagnostics.endSpan(span) }
        detachActiveAction()
        isPanelOpen = true
        ensureAgentsSocket()
        let shouldRestore = lastClosedAt.map { now().timeIntervalSince($0) < popToRootAfterSeconds } ?? false
        isSearchLoading = false
        clipboardHistory.start()
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
        selectedResultID = nil
        isShowingActions = false
        selectedActionID = nil
        // Explicit: `query = ""` only re-triggers refreshResults when it
        // actually changes, so without this an open→close→reopen cycle
        // stranded Home on an empty "Loading" state.
        refreshHomeResults()
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
        clipboardHistory.stop()
        clipboardHistory.reset()
        snippets.reset()
        agents.stopPolling()
        ClipboardImagePreview.releaseCachedImages()
        AIFormattedText.releaseCachedMarkdown()
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


    var clipboardCaptureEnabled: Bool {
        configService.current.clipboard.isEnabled
    }


    var accessibilityTrusted: Bool { AXIsProcessTrusted() }


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

    /// Clipboard image item → Vision OCR → staged text file → Quick Look.
    func extractTextFromClipboardItem(id: String) {
        guard let payload = clipboardHistory.resolvedPayload(for: id),
              case let .image(data) = payload else { return }
        Task {
            do {
                if try await actionRunner.extractTextPreview(fromImageData: data) == false {
                    clipboardHistory.report(ClipboardVisionError.noTextFound)
                }
            } catch {
                diagnostics.log("Clipboard OCR failed: \(error.localizedDescription)")
                clipboardHistory.report(ClipboardVisionError.failed)
            }
        }
    }

    /// Clipboard image item → barcode/QR decode → staged text → Quick Look.
    func decodeBarcodeFromClipboardItem(id: String) {
        guard let payload = clipboardHistory.resolvedPayload(for: id),
              case let .image(data) = payload else { return }
        Task {
            do {
                if try await actionRunner.decodeBarcodePreview(fromImageData: data) == false {
                    clipboardHistory.report(ClipboardVisionError.noBarcodeFound)
                }
            } catch {
                diagnostics.log("Clipboard barcode decode failed: \(error.localizedDescription)")
                clipboardHistory.report(ClipboardVisionError.failed)
            }
        }
    }

    /// File Shelf image → OCR → staged text → Quick Look.
    func extractTextFromShelfFile(_ url: URL) {
        Task {
            do { _ = try await actionRunner.extractTextPreview(at: url) }
            catch { diagnostics.log("Shelf OCR failed: \(error.localizedDescription)") }
        }
    }

    /// File Shelf image → barcode/QR decode → staged text → Quick Look.
    func decodeBarcodeFromShelfFile(_ url: URL) {
        Task {
            do { _ = try await actionRunner.decodeBarcodePreview(at: url) }
            catch { diagnostics.log("Shelf barcode decode failed: \(error.localizedDescription)") }
        }
    }

    var pendingSnippetArguments: [String]?
    private(set) var confettiBurstID = 0

    @discardableResult
    func directPasteSelectedSnippet(arguments: [String: String] = [:]) -> Bool {
        guard let snippet = snippets.selectedItem else { return false }
        let rendered = SnippetRenderer.render(snippet.content, arguments: arguments)
        do {
            try actionRunner.directPasteService.stage(.text(rendered.text), cursorOffset: rendered.cursorOffsetFromEnd)
            snippets.markUsed(id: snippet.id)
            return true
        } catch {
            diagnostics.log("Could not stage snippet: \(error.localizedDescription)")
            return false
        }
    }


    func handleEscape() -> Bool {
        if pendingDropURLs != nil {
            pendingDropURLs = nil
            return true
        }
        if isShowingActions {
            if actionFilter.isEmpty {
                isShowingActions = false
                selectedActionID = nil
            } else {
                actionFilter = ""
            }
            return true
        }
        if mode == .search {
            // Raycast semantics: Esc clears the query first, then a second
            // Esc dismisses the panel.
            guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return false
            }
            query = ""
            return true
        }
        showHome()
        return true
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
        selectedResultID = nil
        isShowingActions = false
        selectedActionID = nil
        refreshHomeResults()
        widgetBoard.start()
        if isAgentShelfVisible {
            agents.start()
        }
    }

    func execute(_ action: CommandAction, commandID: String) async -> CommandOutcome {
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

    /// What ↵ will actually do to the selection — the footer's label must
    /// come from here, not from a typed-in string that can drift.
    var preferredActionTitle: String {
        guard let selectedResult else { return "Open" }
        return preferredAction(for: selectedResult).title
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

    /// Files dropped on the panel surface pending the user's choice of action.
    var pendingDropURLs: [URL]?

    enum DropChoice: CaseIterable {
        case shelf, convert, extractText, compress

        var title: String {
            switch self {
            case .shelf: return "Add to File Shelf"
            case .convert: return "Convert…"
            case .extractText: return "Extract Text"
            case .compress: return "Compress to ZIP"
            }
        }

        var systemIcon: String {
            switch self {
            case .shelf: return "tray.and.arrow.down"
            case .convert: return "arrow.triangle.2.circlepath"
            case .extractText: return "text.viewfinder"
            case .compress: return "archivebox"
            }
        }
    }

    /// Drop choices for the pending files — Extract Text only when every file
    /// is an image the OCR engine can read.
    var dropChoices: [DropChoice] {
        guard let urls = pendingDropURLs, urls.isEmpty == false else { return [] }
        var choices: [DropChoice] = [.shelf, .convert]
        let allImages = urls.allSatisfy {
            ConversionGraph.visionReadExts.contains(ConversionGraph.normalizedExtension(of: $0))
        }
        if allImages { choices.append(.extractText) }
        choices.append(.compress)
        return choices
    }

    func performHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    func resolveDrop(_ choice: DropChoice) {
        guard let urls = pendingDropURLs else { return }
        pendingDropURLs = nil
        performHaptic(.levelChange)
        switch choice {
        case .shelf:
            shelfFiles(urls)
        case .convert:
            openFileConverter(paths: urls.map(\.path))
        case .extractText:
            for url in urls {
                Task { @MainActor [weak self] in
                    _ = await self?.execute(CommandAction(
                        id: "drop.ocr.\(UUID().uuidString)",
                        title: DropChoice.extractText.title,
                        kind: .extractTextFromImage(path: url.path)
                    ), commandID: "foundry.files")
                }
            }
        case .compress:
            for url in urls {
                Task { @MainActor [weak self] in
                    _ = await self?.execute(CommandAction(
                        id: "drop.compress.\(UUID().uuidString)",
                        title: DropChoice.compress.title,
                        kind: .compressFile(path: url.path)
                    ), commandID: "foundry.files")
                }
            }
        }
    }

    func cancelDrop() { pendingDropURLs = nil }

    func handleDroppedFiles(_ urls: [URL]) {
        if mode == .fileConversion {
            guard urls.isEmpty == false else { return }
            fileConversion.addSources(urls: urls)
            return
        }
        guard urls.isEmpty == false else { return }
        pendingDropURLs = urls
    }

    private func shelfFiles(_ urls: [URL]) {
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

        let list = navigableResults
        guard list.isEmpty == false else { return }
        let currentIndex = selectedResultID.flatMap { id in list.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), list.count - 1)
        selectedResultID = list[nextIndex].id
        selectionScrollToken = UUID()
    }

    func refreshResults() {
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
        if let span = searchKeySpan { diagnostics.discardSpan(span) }
        searchKeySpan = diagnostics.startSpan("search.keyToResults")

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
                self.immediatePrefixIDs = Array(immediateResults.map(\.id).prefix(8))
                self.immediateAppliedAt = ContinuousClock.now
                self.selectionAfterImmediate = self.selectedResultID
            },
            onComplete: { [weak self] completeResults in
                guard let self else { return }
                self.isSearchLoading = false
                // Reordering the head after the user has seen (or touched) it
                // reads as rows jumping. Reorder only while the completion
                // lands inside the glance window and the selection is
                // untouched; otherwise the immediate head stays put and the
                // deferred results merge below it.
                let glanceWindowOpen = self.immediateAppliedAt.map {
                    ContinuousClock.now - $0 < .milliseconds(120)
                } ?? true
                let selectionUntouched = self.selectedResultID == self.selectionAfterImmediate
                let stablePrefix = (glanceWindowOpen && selectionUntouched) ? [] : self.immediatePrefixIDs
                self.applySearchResults(completeResults, preserving: self.selectedResultID, stablePrefixIDs: stablePrefix)
            }
        )
    }

    private func applySearchResults(_ rankedResults: [CommandResult], preserving preferredID: String?, stablePrefixIDs: [String] = []) {
        if let span = searchKeySpan {
            diagnostics.endSpan(span)
            searchKeySpan = nil
            diagnostics.mark("results.committed")
        }
        var nextResults = rankedResults
        if stablePrefixIDs.isEmpty == false {
            let head = stablePrefixIDs.compactMap { id in rankedResults.first { $0.id == id } }
            let headIDs = Set(head.map(\.id))
            nextResults = head + rankedResults.filter { headIDs.contains($0.id) == false }
        }
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

    func refreshHomeResults() {
        // Paint the previous snapshot synchronously — opening to an empty or
        // spinner frame is a miss the user can see. The async load then
        // reconciles; it only replaces the list while we're still at home.
        if let snapshot = searchCoordinator.cachedHome() {
            applyHomeResults(snapshot)
            isHomeLoading = false
        } else {
            isHomeLoading = true
        }
        let refreshID = UUID()
        homeRefreshID = refreshID
        searchCoordinator.loadHome { [weak self] loadedResults in
            guard let self,
                  self.homeRefreshID == refreshID,
                  self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            self.applyHomeResults(loadedResults)
        }
    }

    private func applyHomeResults(_ loadedResults: [CommandResult]) {
        var homeResults = loadedResults
        if self.fileShelf.files.isEmpty == false {
            homeResults.removeAll { $0.id == "foundry.file-shelf" }
        }
        self.runningAppBundleIDs = Self.regularRunningAppBundleIDs()
        self.results = homeResults
        self.diagnostics.mark("results.committed")
        self.selectedResultID = homeResults.first?.id
        self.selectionScrollToken = UUID()
        self.isHomeLoading = false
        self.refreshFavorites()
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
        if case .celebrate = action.kind, case .stayOpen = outcome {
            confettiBurstID &+= 1
            performHaptic(.alignment)
        }
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

private enum ClipboardVisionError: LocalizedError {
    case noTextFound, noBarcodeFound, failed
    var errorDescription: String? {
        switch self {
        case .noTextFound: "No text found in that image."
        case .noBarcodeFound: "No barcode found in that image."
        case .failed: "Could not analyze that image."
        }
    }
}
