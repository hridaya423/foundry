import AppKit
import Foundation
import FoundryDomain
import FoundryServices

enum ActionStyle: Sendable {
    case normal
    case destructive
}

/// Everything an action needs that it doesn't own: shared services, the
/// execution event channel, and ports back into the panel. A class so the
/// whole context is Sendable for free and can be captured by completions.
@MainActor
final class ActionContext {
    let diagnostics: DiagnosticsService
    let pasteboard: NSPasteboard
    let snippetStore: any SnippetStore
    let snippetContext: () -> SnippetRenderContext
    let mediaDownloadService: any MediaDownloading
    let mediaDownloadManager: MediaDownloadManager
    let windowManager: any WindowManaging
    let directPasteService: DirectPasteService
    let scriptDirectories: ScriptDirectoryStore
    let localState: LocalStateStore
    let openURL: (URL) -> Bool
    let openApplication: (URL, NSWorkspace.OpenConfiguration, @escaping @Sendable (NSRunningApplication?, Error?) -> Void) -> Void
    let confirmScriptDirectory: (String) async -> Bool
    let resetRanking: (String) -> Void
    let scriptTimeout: TimeInterval
    let scriptOutputLimit: Int
    let invocation: CommandInvocation
    let emit: (CommandExecutionEvent) -> Void
    let panel: PanelPorts

    init(
        diagnostics: DiagnosticsService,
        pasteboard: NSPasteboard,
        snippetStore: any SnippetStore,
        snippetContext: @escaping () -> SnippetRenderContext,
        mediaDownloadService: any MediaDownloading,
        mediaDownloadManager: MediaDownloadManager,
        windowManager: any WindowManaging,
        directPasteService: DirectPasteService,
        scriptDirectories: ScriptDirectoryStore,
        localState: LocalStateStore,
        openURL: @escaping (URL) -> Bool,
        openApplication: @escaping (URL, NSWorkspace.OpenConfiguration, @escaping @Sendable (NSRunningApplication?, Error?) -> Void) -> Void,
        confirmScriptDirectory: @escaping @MainActor (String) async -> Bool,
        resetRanking: @escaping (String) -> Void,
        scriptTimeout: TimeInterval,
        scriptOutputLimit: Int,
        invocation: CommandInvocation,
        emit: @escaping (CommandExecutionEvent) -> Void,
        panel: PanelPorts
    ) {
        self.diagnostics = diagnostics
        self.pasteboard = pasteboard
        self.snippetStore = snippetStore
        self.snippetContext = snippetContext
        self.mediaDownloadService = mediaDownloadService
        self.mediaDownloadManager = mediaDownloadManager
        self.windowManager = windowManager
        self.directPasteService = directPasteService
        self.scriptDirectories = scriptDirectories
        self.localState = localState
        self.openURL = openURL
        self.openApplication = openApplication
        self.confirmScriptDirectory = confirmScriptDirectory
        self.resetRanking = resetRanking
        self.scriptTimeout = scriptTimeout
        self.scriptOutputLimit = scriptOutputLimit
        self.invocation = invocation
        self.emit = emit
        self.panel = panel
    }

    /// The common "outcome plus an alert" pair — emit the feedback, return
    /// the outcome.
    func finish(_ outcome: CommandOutcome, feedback: ActionFeedback? = nil) -> CommandOutcome {
        if let feedback {
            emit(.feedback(feedback))
        }
        return outcome
    }
}

/// Ports back into `CommandPanelState` for actions that touch panel state —
/// favorites, deep-linked Settings, the downloads tab, confetti.
@MainActor
struct PanelPorts: Sendable {
    var toggleFavorite: @MainActor @Sendable (String) -> Bool = { _ in false }
    var presentSettings: @MainActor @Sendable (SettingsDeepLink) -> Void = { _ in }
    var presentMediaDownloads: @MainActor @Sendable () -> Void = {}
    var celebrate: @MainActor @Sendable () -> Void = {}
    /// Presents a ConfirmBar/PanelForm prompt and suspends for the answer.
    /// Default resolves `.cancelled` — modal UI never runs under tests.
    var requestPrompt: @MainActor @Sendable (PanelPromptSpec) async -> PanelPromptResult = { _ in .cancelled }
    /// nil = no Quick Look wiring; actions fall back to opening the file.
    var onQuickLook: (@MainActor @Sendable (URL) -> Void)?
}

/// Behaviour for one result action. Implementations live next to the
/// feature that owns them — `ActionRunner` is a generic executor, not a
/// home for feature logic.
protocol ResultAction: Sendable {
    /// SF Symbol name for the actions-overlay row icon, if any.
    var icon: String? { get }
    /// Conventional shortcut assigned in the actions overlay.
    var shortcut: ActionShortcut? { get }
    /// `.destructive` styles red and can require confirmation.
    var style: ActionStyle { get }
    /// Whether the panel must dismiss before a hotkey-invoked run.
    var hidesPanelForHotkey: Bool { get }
    /// List section the action's result belongs in, when classification
    /// follows the action rather than the result payload.
    var resultSection: ResultSection? { get }
    @MainActor
    func perform(_ ctx: ActionContext) async -> CommandOutcome
}

extension ResultAction {
    var icon: String? { nil }
    var shortcut: ActionShortcut? { nil }
    var style: ActionStyle { .normal }
    var hidesPanelForHotkey: Bool { false }
    var resultSection: ResultSection? { nil }
}
