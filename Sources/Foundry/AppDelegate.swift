import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shellController: ShellController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics)
        let actionRunner = ActionRunner(diagnostics: diagnostics)
        let registry = CommandRegistry.defaultRegistry(config: config, diagnostics: diagnostics)
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
}
