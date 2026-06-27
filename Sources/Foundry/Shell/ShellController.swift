import AppKit
import SwiftUI

@MainActor
final class ShellController {
    private let registry: CommandRegistry
    private let actionRunner: ActionRunner
    private let config: ConfigService
    private let diagnostics: DiagnosticsService
    private let hotkeyController: HotkeyController
    private let panelController: PanelController
    private let panelState: CommandPanelState

    init(registry: CommandRegistry, actionRunner: ActionRunner, config: ConfigService, diagnostics: DiagnosticsService) {
        self.registry = registry
        self.actionRunner = actionRunner
        self.config = config
        self.diagnostics = diagnostics
        self.hotkeyController = HotkeyController()
        self.panelState = CommandPanelState(registry: registry, actionRunner: actionRunner, diagnostics: diagnostics, config: config)
        self.panelController = PanelController(state: panelState, diagnostics: diagnostics)
    }

    func start() {
        diagnostics.log("Foundry shell starting")
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

        showPanel()
    }

    func stop() {
        hotkeyController.unregister()
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

    private func showPanel() {
        panelState.resetForOpen()
        panelController.show()
        NSApp.activate(ignoringOtherApps: true)
    }
}
