import AppKit
import SwiftUI
import FoundryDomain
import FoundryServices

@MainActor
final class ShellController {
    private let registry: CommandRegistry
    private let config: ConfigService
    private let diagnostics: DiagnosticsService
    private let activation: any AppActivation
    private let hotkeyController: HotkeyController
    private let panelController: PanelController
    private let panelState: CommandPanelState
    private let statusItemController: StatusItemController
    private let onboardingState: OnboardingState
    private let onboardingController: OnboardingWindowController
    private let clipboardHistory: ClipboardHistoryState
    private let snippetExpansion: SnippetExpansionService
    private var hasStarted = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var settingsWindow: SettingsWindowController?

    init(
        registry: CommandRegistry,
        actionRunner: ActionRunner,
        config: ConfigService,
        diagnostics: DiagnosticsService,
        snippetStore: any SnippetStore = FileSnippetStore(),
        mediaDownloadManager: MediaDownloadManager = MediaDownloadManager(),
        clipboardHistory: ClipboardHistoryState? = nil,
        activation: (any AppActivation)? = nil
    ) {
        self.registry = registry
        self.config = config
        self.diagnostics = diagnostics
        self.activation = activation ?? NSAppActivation()
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
        let panelController = PanelController(
            state: panelState,
            diagnostics: diagnostics,
            directPasteService: actionRunner.directPasteService,
            activation: self.activation
        )
        self.panelController = panelController
        actionRunner.panel.onQuickLook = { [weak panelController] url in
            panelController?.previewFile(url)
        }
        let permissionHealth = PermissionHealthState()
        let onboardingState = OnboardingState(panel: panelState, permissions: permissionHealth)
        onboardingState.onStepChanged = { [diagnostics] step in
            diagnostics.log("onboarding.\(step)")
        }
        onboardingState.onDidTryPanel = { [weak panelState] in
            panelState?.performHaptic(.levelChange)
        }
        let onboardingController = OnboardingWindowController(state: onboardingState)
        self.onboardingController = onboardingController
        let statusItemController = StatusItemController(state: panelState)
        self.statusItemController = statusItemController
        self.onboardingState = onboardingState
        self.panelState.shell = self
        panelController.otherWindowsVisible = { [weak self, weak onboardingController] in
            onboardingController?.isVisible == true || self?.settingsWindow?.window?.isVisible == true
        }
        panelState.snippets.onSaved = { [weak self] in self?.configureSnippetExpansion() }
        statusItemController.onTogglePanel = { [weak self] in
            self?.togglePanel()
        }
        statusItemController.onOpenPanel = { [weak self] in
            self?.showPanel()
        }
        self.snippetExpansion.onStatusChanged = { [weak panelState] message in
            Task { @MainActor in panelState?.settings.setSnippetExpansionError(message) }
        }
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
        // Capture once at launch; the repeating poll is armed by
        // CommandPanelState while the panel is open and stopped on close.
        clipboardHistory.captureIfChanged()
        configureSnippetExpansion()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
            queue: .main) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.snippetExpansion.handleApplicationActivation(bundleIdentifier: application?.bundleIdentifier)
            }
        })
        snippetExpansion.handleApplicationActivation(bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        workspaceObservers.append(workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.snippetExpansion.recoverFromWake()
            }
        })
        hotkeyController.onPressed = { [weak self] in
            MainActor.assumeIsolated {
                self?.diagnostics.log("hotkey.received")
                self?.togglePanel()
            }
        }

        statusItemController.setVisible(panelState.settings.showMenuBarIcon)
        let showsOnboarding = OnboardingState.shouldShowAutomatically(configExistedAtLaunch: config.existedAtLaunch)

        do {
            try hotkeyController.register(hotkey: config.current.hotkey)
            diagnostics.log("Registered global hotkey: \(config.current.hotkey.displayName)")
        } catch {
            diagnostics.log("Failed to register hotkey: \(error.localizedDescription)")
            panelState.settings.setLauncherHotkeyFailed(true)
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
        config.flush()
        stop()
    }

    private func configureSnippetExpansion() {
        let settings = config.current.snippetExpansion
        let ownBundleIdentifier = [Bundle.main.bundleIdentifier].compactMap { $0 }
        snippetExpansion.configure(isEnabled: settings.isEnabled, excludedBundleIdentifiers: settings.excludedBundleIdentifiers + ownBundleIdentifier,
            delimiters: settings.delimiters, hapticsEnabled: config.current.hapticsEnabled)
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
        activation.activate()
        panelState.resetForOpen()
        panelController.show()
        DispatchQueue.main.async { [diagnostics] in
            diagnostics.endSpan(span)
        }
    }

    /// Finder "Open With", dock drops, and `--convert <path>` all land here:
    /// the panel opens straight into the converter with the files loaded.
    func openFileConverter(paths: [String]) {
        showPanel()
        panelState.router.openFileConverter(paths: paths)
    }
    private func runCommandHotkey(commandID: String) async {
        guard let result = await registry.commandResult(for: commandID) else {
            showPanel()
            await panelState.executeCommand(commandID: commandID)
            return
        }

        guard result.primaryAction.behavior.hidesPanelForHotkey else {
            showPanel()
            await panelState.executeResult(result)
            return
        }

        let outcome = await panelState.executeResult(result)
        if outcome.isSuccessful {
            panelController.hide(reason: .executed)
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
            let failed = try hotkeyController.registerCommandHotkeys(hotkeys) { [weak self] commandID in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.runCommandHotkey(commandID: commandID)
                }
            }
            panelState.settings.setUnavailableCommandHotkeys(failed)
            diagnostics.log("Registered \(hotkeys.count - failed.count) of \(hotkeys.count) command hotkeys")
        } catch {
            panelState.settings.setUnavailableCommandHotkeys(Array(hotkeys.keys))
            diagnostics.log("Failed to register command hotkeys: \(error.localizedDescription)")
        }
    }
}

extension ShellController: ShellPort {
    func hotkeyChanged(_ hotkey: FoundryHotkey) throws {
        try hotkeyController.register(hotkey: hotkey)
        diagnostics.log("Registered global hotkey: \(hotkey.displayName)")
        panelState.settings.setLauncherHotkeyFailed(false)
    }

    func commandPreferencesChanged() {
        registerCommandHotkeys()
    }

    func menuBarIconVisibilityChanged(_ visible: Bool) {
        statusItemController.setVisible(visible)
    }

    func compactCollapseChanged(_ collapsed: Bool) {
        panelController.setCompactCollapsed(collapsed)
    }

    func ensurePanelVisible() {
        guard panelController.isVisible == false else { return }
        activation.activate()
        panelController.show()
    }

    func openSettings() {
        let settingsWindow = self.settingsWindow ?? SettingsWindowController(state: panelState)
        self.settingsWindow = settingsWindow
        settingsWindow.show()
    }

    func quickLook(_ url: URL) {
        panelController.toggleQuickLook(url)
    }

    func quickLookFollowSelection() {
        panelController.quickLookFollowSelection()
    }

    var isQuickLookShowing: Bool {
        panelController.isQuickLookShowing
    }

    func closeQuickLook() {
        panelController.closeQuickLook()
    }

    func showTransientNotice(_ feedback: ActionFeedback) {
        panelController.showTransientNotice(feedback)
    }

    func openWelcomeGuide() {
        if panelController.isVisible { panelController.hide() }
        onboardingState.restart()
        onboardingController.show()
    }

    func snippetExpansionChanged() {
        configureSnippetExpansion()
    }

    func requestSnippetAccessibility() {
        snippetExpansion.requestAccessibilityAccess()
    }

    func requestPermission(_ kind: PermissionKind) {
        onboardingState.permissions.request(kind)
    }

    func openSnippetPrivacySettings() {
        snippetExpansion.openAccessibilitySettings()
    }

    func resultExecuted() {
        onboardingState.completeTryIt()
    }
}
