import AppKit
import SwiftUI
import FoundryServices

@MainActor
final class ShellController {
    private let registry: CommandRegistry
    private let actionRunner: ActionRunner
    private let config: ConfigService
    private let diagnostics: DiagnosticsService
    private let hotkeyController: HotkeyController
    private let panelController: PanelController
    private let panelState: CommandPanelState
    private let clipboardHistory: ClipboardHistoryState
    private let snippetExpansion: SnippetExpansionService
    private var hasStarted = false
    private var workspaceObservers: [NSObjectProtocol] = []

    init(
        registry: CommandRegistry,
        actionRunner: ActionRunner,
        config: ConfigService,
        diagnostics: DiagnosticsService,
        snippetStore: any SnippetStore = FileSnippetStore(),
        mediaDownloadManager: MediaDownloadManager = MediaDownloadManager(),
        clipboardHistory: ClipboardHistoryState? = nil
    ) {
        self.registry = registry
        self.actionRunner = actionRunner
        self.config = config
        self.diagnostics = diagnostics
        self.hotkeyController = HotkeyController()
        let sharedClipboardHistory = clipboardHistory ?? ClipboardHistoryState(configuration: config.current.clipboard)
        self.clipboardHistory = sharedClipboardHistory
        self.snippetExpansion = SnippetExpansionService(snippetStore: snippetStore, directPaste: actionRunner.directPasteService)
        self.panelState = CommandPanelState(
            registry: registry,
            actionRunner: actionRunner,
            diagnostics: diagnostics,
            config: config,
            snippetStore: snippetStore,
            mediaDownloadManager: mediaDownloadManager,
            clipboardHistory: sharedClipboardHistory
        )
        self.panelController = PanelController(state: panelState, diagnostics: diagnostics, directPasteService: actionRunner.directPasteService)
        self.snippetExpansion.onStatusChanged = { [weak panelState] message in
            Task { @MainActor in panelState?.setSnippetExpansionError(message) }
        }
        self.panelState.onHotkeyChanged = { [weak self] hotkey in
            guard let self else { return }
            try self.hotkeyController.register(hotkey: hotkey)
            self.diagnostics.log("Registered global hotkey: \(hotkey.displayName)")
        }
        self.panelState.onCommandPreferencesChanged = { [weak self] in
            self?.registerCommandHotkeys()
        }
    }

    func start() {
        guard hasStarted == false else { return }
        hasStarted = true
        diagnostics.log("Foundry shell starting")
        clipboardHistory.start()
        configureSnippetExpansion()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.snippetExpansion.handleApplicationActivation(bundleIdentifier: application?.bundleIdentifier)
        })
        snippetExpansion.handleApplicationActivation(bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.snippetExpansion.recoverFromWake()
        })
        hotkeyController.onPressed = { [weak self] in
            Task { @MainActor in
                self?.togglePanel()
            }
        }

        do {
            try hotkeyController.register(hotkey: config.current.hotkey)
            diagnostics.log("Registered global hotkey: \(config.current.hotkey.displayName)")
        } catch {
            diagnostics.log("Failed to register hotkey: \(error.localizedDescription)")
        }
        registerCommandHotkeys()

    }

    func stop() {
        guard hasStarted else { return }
        hasStarted = false
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspaceCenter.removeObserver)
        workspaceObservers.removeAll()
        snippetExpansion.stop()
        panelState.shutdown()
        hotkeyController.unregister()
    }

    func prepareForTermination() async {
        await panelState.prepareForTermination()
        stop()
    }

    private func configureSnippetExpansion() {
        let settings = config.current.snippetExpansion
        snippetExpansion.configure(isEnabled: settings.isEnabled, excludedBundleIdentifiers: settings.excludedBundleIdentifiers)
    }

    func reconfigureSnippetExpansion() { configureSnippetExpansion() }
    func requestSnippetAccessibility() { snippetExpansion.requestAccessibilityAccess() }
    func openSnippetPrivacySettings() { snippetExpansion.openAccessibilitySettings() }

    private func togglePanel() {
        let span = diagnostics.startSpan("shell.toggle")
        if panelController.isVisible {
            panelController.hide()
        } else {
            showPanel()
        }
        diagnostics.endSpan(span)
    }

    func showPanel() {
        panelState.resetForOpen()
        panelController.show()
        NSApp.activate(ignoringOtherApps: true)
    }
    private func runCommandHotkey(commandID: String) async {
        guard let result = await registry.commandResult(for: commandID) else {
            showPanel()
            await panelState.executeCommand(commandID: commandID)
            return
        }

        guard result.primaryAction.kind.shouldHidePanelForHotkey else {
            showPanel()
            await panelState.executeResult(result)
            return
        }

        let outcome = await panelState.executeResult(result)
        if outcome.isSuccessful {
            panelController.hide()
        } else {
            showPanel()
        }
    }

    private func registerCommandHotkeys() {
        let hotkeys: [String: FoundryHotkey] = Dictionary(uniqueKeysWithValues: config.current.commandPreferences.compactMap { commandID, preference in
            guard preference.isEnabled, let hotkey = preference.globalHotkey else { return nil }
            return (
                commandID,
                FoundryHotkey(
                    keyCode: hotkey.keyCode,
                    modifiers: hotkey.modifiers,
                    displayName: hotkey.displayName
                )
            )
        })

        do {
            try hotkeyController.registerCommandHotkeys(hotkeys) { [weak self] commandID in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.runCommandHotkey(commandID: commandID)
                }
            }
            diagnostics.log("Registered \(hotkeys.count) command hotkey\(hotkeys.count == 1 ? "" : "s")")
        } catch {
            diagnostics.log("Failed to register command hotkeys: \(error.localizedDescription)")
        }
    }
}
