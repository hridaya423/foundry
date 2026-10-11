import AppKit
import Foundation
import FoundryDomain
import FoundryServices

/// Generic action executor: confirmation policy, cancellation tracking,
/// and event plumbing. Feature behaviour lives in `ResultAction`
/// implementations next to the feature that owns it.
@MainActor
final class ActionRunner {
    private let diagnostics: DiagnosticsService
    private let snippetStore: any SnippetStore
    private let mediaDownloadService: any MediaDownloading
    private let mediaDownloadManager: MediaDownloadManager
    private let resetRanking: (String) -> Void
    private let confirmAction: (CommandActionDescriptor, CommandInvocationSource) -> Bool
    private let windowManager: any WindowManaging
    private let openURL: (URL) -> Bool
    private let openApplication: (URL, NSWorkspace.OpenConfiguration, @escaping @Sendable (NSRunningApplication?, Error?) -> Void) -> Void
    private let snippetContext: () -> SnippetRenderContext
    private let pasteboard: NSPasteboard
    let directPasteService: DirectPasteService
    private let scriptDirectories: ScriptDirectoryStore
    private let localState: LocalStateStore
    private let confirmScriptDirectory: @MainActor (String) -> Bool
    private let offerQRSave: @MainActor (NSImage, String) -> Void
    private let scriptTimeout: TimeInterval
    private let scriptOutputLimit: Int
    private var activeExecutionTasks: [UUID: Task<CommandOutcome, Never>] = [:]

    /// Ports back into the panel — wired by `CommandPanelState` at startup.
    var panel = PanelPorts()

    init(
        diagnostics: DiagnosticsService,
        snippetStore: any SnippetStore = FileSnippetStore(),
        mediaDownloadService: any MediaDownloading = MediaDownloadService(),
        mediaDownloadManager: MediaDownloadManager = MediaDownloadManager(),
        resetRanking: @escaping (String) -> Void = { _ in },
        confirmAction: @escaping (CommandActionDescriptor, CommandInvocationSource) -> Bool = { _, _ in true },
        windowManager: any WindowManaging = NativeWindowManager(),
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        openApplication: @escaping (URL, NSWorkspace.OpenConfiguration, @escaping @Sendable (NSRunningApplication?, Error?) -> Void) -> Void = { url,
            configuration, completion in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: completion)
        },
        directPasteService: DirectPasteService = .shared,
        pasteboard: NSPasteboard = .general,
        snippetContext: @escaping () -> SnippetRenderContext = { .current() },
        scriptDirectories: ScriptDirectoryStore = .shared,
        localState: LocalStateStore = .shared,
        confirmScriptDirectory: @escaping @MainActor (String) -> Bool = RunScriptAction.promptToTrustScriptDirectory,
        offerQRSave: @escaping @MainActor (NSImage, String) -> Void = GenerateQRCodeAction.presentSaveOffer,
        scriptTimeout: TimeInterval = 30,
        scriptOutputLimit: Int = 256 * 1024
    ) {
        self.scriptDirectories = scriptDirectories
        self.localState = localState
        self.confirmScriptDirectory = confirmScriptDirectory
        self.offerQRSave = offerQRSave
        self.scriptTimeout = scriptTimeout
        self.scriptOutputLimit = scriptOutputLimit
        self.diagnostics = diagnostics
        self.snippetStore = snippetStore
        self.mediaDownloadService = mediaDownloadService
        self.mediaDownloadManager = mediaDownloadManager
        self.resetRanking = resetRanking
        self.confirmAction = confirmAction
        self.windowManager = windowManager
        self.openURL = openURL
        self.openApplication = openApplication
        self.snippetContext = snippetContext
        self.pasteboard = pasteboard
        self.directPasteService = directPasteService
    }

    func execute(
        _ request: CommandExecutionRequest,
        emit: @escaping @MainActor @Sendable (CommandExecutionEvent) -> Void
    ) async -> CommandOutcome {
        let invocationID = request.invocation.cancellationID
        guard activeExecutionTasks[invocationID] == nil else {
            return .failure(message: "An action with this cancellation ID is already running", retryable: true)
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return CommandOutcome.cancelled }
            return await self.perform(request, emit: emit)
        }
        activeExecutionTasks[invocationID] = task
        let outcome = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        activeExecutionTasks.removeValue(forKey: invocationID)
        return outcome
    }

    private func perform(
        _ request: CommandExecutionRequest,
        emit: @escaping @MainActor @Sendable (CommandExecutionEvent) -> Void
    ) async -> CommandOutcome {
        if request.action.descriptor.confirmation != .never,
           confirmAction(request.action.descriptor, request.invocation.source) == false {
            emit(.feedback(.info("Action cancelled")))
            return .denied(message: "Action cancelled")
        }

        let ctx = ActionContext(
            diagnostics: diagnostics,
            pasteboard: pasteboard,
            snippetStore: snippetStore,
            snippetContext: snippetContext,
            mediaDownloadService: mediaDownloadService,
            mediaDownloadManager: mediaDownloadManager,
            windowManager: windowManager,
            directPasteService: directPasteService,
            scriptDirectories: scriptDirectories,
            localState: localState,
            openURL: openURL,
            openApplication: openApplication,
            confirmScriptDirectory: confirmScriptDirectory,
            offerQRSave: offerQRSave,
            resetRanking: resetRanking,
            scriptTimeout: scriptTimeout,
            scriptOutputLimit: scriptOutputLimit,
            invocation: request.invocation,
            emit: emit,
            panel: panel
        )
        return await request.action.behavior.perform(ctx)
    }

    func cancel(_ cancellationID: UUID) {
        activeExecutionTasks[cancellationID]?.cancel()
    }
}
