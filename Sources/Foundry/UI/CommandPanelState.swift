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
    }

    var presentationToken = UUID()
    private(set) var actionFeedback: ActionFeedback? = nil
    /// The one seam to the surrounding shell — `ShellController` fills it in.
    weak var shell: (any ShellPort)?
    var pendingSettingsDeepLink: SettingsDeepLink?
    var now: () -> Date = Date.init
    var lastClosedAt: Date?

    @ObservationIgnored lazy var emojiPicker = EmojiPickerState(localState: localState)
    let fileShelf = FileShelfState()
    let agents = AgentMonitorState()
    let clipboardHistory: ClipboardHistoryState
    let snippets: SnippetState
    let localState: LocalStateStore
    @ObservationIgnored lazy var fileConversion: FileConversionState = {
        let state = FileConversionState(localState: localState)
        state.onFirstSuccess = { [weak self] in
            self?.confettiBurstID &+= 1
            self?.performHaptic(.alignment)
        }
        state.onConversionCompleted = { [weak self] in
            self?.performHaptic(.levelChange)
        }
        state.onQuickLookOutput = { [weak self] url in
            self?.actionRunner.panel.onQuickLook?(url)
        }
        state.onShareOutput = { url in
            shareFile(at: url)
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
    /// `var` so `$state.settings.X` bindings resolve in the settings UI;
    /// the store itself is never reassigned.
    var settings: SettingsStore
    let router: PanelRouter
    /// `var` so `$state.session.X` bindings resolve in the search UI;
    /// the session itself is never reassigned.
    var session: PanelSession
    let configService: ConfigService

    let registry: CommandRegistry
    let searchCoordinator: CommandSearchCoordinator
    let actionRunner: ActionRunner
    let diagnostics: DiagnosticsService
    private var activeActionCancellationID: UUID?
    private var actionGeneration = 0
    private(set) var isActionInProgress = false
    var feedbackTask: Task<Void, Never>?
    var isPanelOpen = false

    /// Files dropped on the panel surface pending the user's choice of action.
    var pendingDropURLs: [URL]?
    var pendingPrompt: PendingPrompt?
    var pendingSnippetArguments: [String]?
    private(set) var confettiBurstID = 0

    init(
        registry: CommandRegistry,
        actionRunner: ActionRunner,
        diagnostics: DiagnosticsService,
        config: ConfigService,
        snippetStore: any SnippetStore = FileSnippetStore(),
        mediaDownloadManager: MediaDownloadManager = MediaDownloadManager(),
        clipboardHistory: ClipboardHistoryState? = nil,
        localState: LocalStateStore = .shared
    ) {
        self.registry = registry
        self.searchCoordinator = CommandSearchCoordinator(registry: registry, diagnostics: diagnostics)
        self.actionRunner = actionRunner
        self.diagnostics = diagnostics
        self.configService = config
        self.localState = localState
        self.clipboardHistory = clipboardHistory ?? ClipboardHistoryState(configuration: config.current.clipboard)
        self.snippets = SnippetState(store: snippetStore, localState: localState)
        self.installedBrowsers = BrowserSource.allCases.filter(\.isInstalled)
        self.settings = SettingsStore(configService: config, diagnostics: diagnostics, registry: registry)
        self.router = PanelRouter(diagnostics: diagnostics)
        self.session = PanelSession(registry: registry, searchCoordinator: searchCoordinator, configService: config, diagnostics: diagnostics)
        self.widgetBoard = WidgetBoardState(configService: config, diagnostics: diagnostics)
        self.aiSettings = AISettingsState(config: config, diagnostics: diagnostics)
        self.quickAI = QuickAIState(aiProvider: AIProvider(config: config, diagnostics: diagnostics))
        self.mediaDownloads = mediaDownloadManager
        settings.panel = self
        router.panel = self
        session.panel = self
        settings.apply(config: config.current)
        actionRunner.panel.toggleFavorite = { [weak self] id in
            self?.settings.toggleFavorite(commandID: id) ?? false
        }
        actionRunner.panel.presentSettings = { [weak self] link in
            self?.pendingSettingsDeepLink = link
            self?.open(.settings)
        }
        actionRunner.panel.presentMediaDownloads = { [weak self] in
            self?.router.openMediaDownloads()
        }
        actionRunner.panel.celebrate = { [weak self] in
            self?.confettiBurstID &+= 1
            self?.performHaptic(.alignment)
        }
        actionRunner.panel.requestPrompt = { [weak self] spec in
            await self?.requestPrompt(spec) ?? .cancelled
        }
        self.widgetBoard.persistenceErrorHandler = { [weak self] error in
            self?.settings.showSettingsPersistenceError(error)
        }
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

    var clipboardCaptureEnabled: Bool {
        configService.current.clipboard.isEnabled
    }

    var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    // Input surface the views and tests use — the router owns the stack;
    // these four aliases keep the panel's public shape narrow.
    var mode: Mode {
        get { router.mode }
        set { router.mode = newValue }
    }

    func handleEscape() -> Bool { router.handleEscape() }

    func showHome() { router.showHome() }

    func open(_ route: CommandRoute) { router.open(route) }

    func execute(_ action: CommandAction, commandID: String) async -> CommandOutcome {
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
            shell?.showTransientNotice(successFeedback)
        }
        return outcome
    }

    func cancelActiveAction() {
        if let activeActionCancellationID {
            actionRunner.cancel(activeActionCancellationID)
        }
        activeActionCancellationID = nil
        isActionInProgress = false
        actionGeneration &+= 1
    }

    func detachActiveAction() {
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
        guard let selectedResult = session.selectedResult else {
            if let request = AIProvider.request(from: session.query) {
                router.openQuickAI(initialPrompt: request.prompt)
            }
            return false
        }
        let action = session.isShowingActions ? session.selectedAction : nil
        guard session.isShowingActions == false || action != nil else { return false }
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
            session.refreshResults()
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
            let availableIDs = Set(session.selectedActions.map(\.id))
            if let actionID = actionIDs.first(where: { availableIDs.contains($0) }) {
                session.actionFilter = ""
                session.isShowingActions = true
                session.selectedActionID = actionID
            } else {
                showActionFeedback(.info("No follow-up action available"))
            }
        case .success, .cancelled, .stayOpen(nil), .copied, .pasted:
            break
        }
    }

    @discardableResult
    func executeResult(_ result: CommandResult, action override: CommandAction? = nil) async -> CommandOutcome {
        guard isActionInProgress == false else { return .cancelled }
        let action = override ?? session.preferredAction(for: result)
        diagnostics.log("Executing action \(action.id) for result \(result.id)")
        registry.recordExecution(resultID: result.id, query: session.query)
        shell?.resultExecuted()
        let outcome = await execute(action, commandID: result.id)
        if case .copied = outcome, let expression = result.payload.calculationExpression {
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
        session.results = [result]
        session.selectedResultID = result.id
        session.isShowingActions = false
        session.selectedActionID = nil
        await executeResult(result)
    }

}
