import AppKit
import SwiftUI
import FoundryServices

@MainActor
final class ShellController {
    private let registry: CommandRegistry
    private let config: ConfigService
    private let diagnostics: DiagnosticsService
    private let hotkeyController: HotkeyController
    private let panelController: PanelController
    private let panelState: CommandPanelState
    private let statusItemController: StatusItemController
    private let onboardingController: OnboardingWindowController
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
        let permissionHealth = PermissionHealthState()
        let onboardingState = OnboardingState(panel: panelState, permissions: permissionHealth)
        let onboardingController = OnboardingWindowController(state: onboardingState)
        self.onboardingController = onboardingController
        let statusItemController = StatusItemController(state: panelState)
        self.statusItemController = statusItemController
        statusItemController.onTogglePanel = { [weak self] in
            self?.togglePanel()
        }
        statusItemController.onOpenPanel = { [weak self] in
            self?.showPanel()
        }
        self.panelState.onMenuBarIconVisibilityChanged = { [weak statusItemController] visible in
            statusItemController?.setVisible(visible)
        }
        self.snippetExpansion.onStatusChanged = { [weak panelState] message in
            Task { @MainActor in panelState?.setSnippetExpansionError(message) }
        }
        self.panelState.onHotkeyChanged = { [weak self] hotkey in
            guard let self else { return }
            try self.hotkeyController.register(hotkey: hotkey)
            self.diagnostics.log("Registered global hotkey: \(hotkey.displayName)")
            self.panelState.setLauncherHotkeyFailed(false)
        }
        self.panelState.onCommandPreferencesChanged = { [weak self] in
            self?.registerCommandHotkeys()
        }
        self.panelState.onCompactCollapseChanged = { [weak panelController] collapsed in
            panelController?.setCompactCollapsed(collapsed)
        }
        self.panelState.onOpenSettings = { [weak self] in
            self?.showPanel()
        }
        self.panelState.onOpenWelcomeGuide = { [weak panelController, weak onboardingController, weak onboardingState] in
            if panelController?.isVisible == true { panelController?.hide() }
            onboardingState?.restart()
            onboardingController?.show()
        }
        self.panelState.onSnippetExpansionChanged = { [weak self] in self?.configureSnippetExpansion() }
        self.panelState.onRequestSnippetAccessibility = { [weak self] in self?.snippetExpansion.requestAccessibilityAccess() }
        self.panelState.onOpenSnippetPrivacySettings = { [weak self] in self?.snippetExpansion.openAccessibilitySettings() }
        statusItemController.onWelcomeGuide = { [weak onboardingController, weak onboardingState] in
            onboardingState?.restart()
            onboardingController?.show()
        }
        onboardingState.onFinish = { [weak self, weak onboardingController, weak onboardingState] in
            onboardingController?.close()
            if onboardingState?.step == .done { self?.showPanel() }
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
            MainActor.assumeIsolated {
                self?.diagnostics.log("hotkey.received")
                self?.togglePanel()
            }
        }

        statusItemController.setVisible(panelState.showMenuBarIcon)
        let showsOnboarding = OnboardingState.shouldShowAutomatically(configExistedAtLaunch: config.existedAtLaunch)

        do {
            try hotkeyController.register(hotkey: config.current.hotkey)
            diagnostics.log("Registered global hotkey: \(config.current.hotkey.displayName)")
        } catch {
            diagnostics.log("Failed to register hotkey: \(error.localizedDescription)")
            panelState.setLauncherHotkeyFailed(true)
            if showsOnboarding == false { showPanel() }
        }
        registerCommandHotkeys()
        panelController.prewarm()

        if showsOnboarding {
            onboardingController.show()
        }
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
        let span = diagnostics.startSpan("panel.hotkeyToFront")
        NSApp.activate(ignoringOtherApps: true)
        panelState.resetForOpen()
        panelController.show()
        DispatchQueue.main.async { [diagnostics] in
            diagnostics.endSpan(span)
        }
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
