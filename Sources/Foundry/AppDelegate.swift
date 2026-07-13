import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shellController: ShellController?
    private let launchAtLoginPromptKey = "foundry.launchAtLoginPromptShown"
    private let launchAtLoginConsentKey = "foundry.launchAtLoginConsent"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics)
        let actionRunner = ActionRunner(diagnostics: diagnostics)

        configureLoginItem(diagnostics: diagnostics)
        FirefoxConnectorInstaller(diagnostics: diagnostics).configureMainBrowser()

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
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.bundleIdentifier == "com.hridya.foundry" else {
            diagnostics.log("Skipping login-item setup outside a packaged app")
            return
        }
        let loginItem = SMAppService.mainApp
        if loginItem.status == .enabled {
            UserDefaults.standard.set(true, forKey: launchAtLoginPromptKey)
            UserDefaults.standard.set(true, forKey: launchAtLoginConsentKey)
            return
        }

        if UserDefaults.standard.object(forKey: launchAtLoginConsentKey) == nil,
           UserDefaults.standard.bool(forKey: launchAtLoginPromptKey) {
            // Migrate the old prompt-only state so failed or stale registrations
            // get one clean consent flow with the packaged app.
            UserDefaults.standard.set(false, forKey: launchAtLoginPromptKey)
        }

        if UserDefaults.standard.bool(forKey: launchAtLoginConsentKey) {
            do {
                try loginItem.register()
                diagnostics.log("Re-registered Foundry as a login item")
            } catch {
                diagnostics.log("Could not restore Foundry login item: \(error.localizedDescription)")
            }
            return
        }

        guard UserDefaults.standard.bool(forKey: launchAtLoginPromptKey) == false else { return }

        let alert = NSAlert()
        alert.messageText = "Launch Foundry at login?"
        alert.informativeText = "Foundry can start automatically when you sign in, so its launcher and shortcuts are ready immediately. You can change this later in System Settings."
        alert.addButton(withTitle: "Launch at Login")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        UserDefaults.standard.set(true, forKey: launchAtLoginPromptKey)

        do {
            try loginItem.register()
            UserDefaults.standard.set(true, forKey: launchAtLoginConsentKey)
            diagnostics.log("Registered Foundry as a login item")
        } catch {
            UserDefaults.standard.set(false, forKey: launchAtLoginPromptKey)
            diagnostics.log("Could not register Foundry as a login item: \(error.localizedDescription)")
        }
    }
}
