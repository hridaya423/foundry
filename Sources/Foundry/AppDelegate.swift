import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shellController: ShellController?
    private let launchAtLoginPromptKey = "foundry.launchAtLoginPromptShown"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics)
        let actionRunner = ActionRunner(diagnostics: diagnostics)

        configureLoginItem(diagnostics: diagnostics)

        let registry = CommandRegistry.defaultRegistry(
            config: config,
            diagnostics: diagnostics
        )
        let shellController = ShellController(
            registry: registry,
            actionRunner: actionRunner,
            config: config,
            diagnostics: diagnostics
        )

        self.shellController = shellController
        shellController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shellController?.stop()
    }

    private func configureLoginItem(diagnostics: DiagnosticsService) {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            diagnostics.log("Skipping login-item setup outside a packaged app")
            return
        }
        let loginItem = SMAppService.mainApp
        if loginItem.status == .enabled {
            UserDefaults.standard.set(true, forKey: launchAtLoginPromptKey)
            return
        }
        guard UserDefaults.standard.bool(forKey: launchAtLoginPromptKey) == false else { return }

        let alert = NSAlert()
        alert.messageText = "Launch Foundry at login?"
        alert.informativeText = "Foundry can start automatically when you sign in, so its launcher and shortcuts are ready immediately. You can change this later in System Settings."
        alert.addButton(withTitle: "Launch at Login")
        alert.addButton(withTitle: "Not Now")
        UserDefaults.standard.set(true, forKey: launchAtLoginPromptKey)

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try loginItem.register()
            diagnostics.log("Registered Foundry as a login item")
        } catch {
            diagnostics.log("Could not register Foundry as a login item: \(error.localizedDescription)")
        }
    }
}
