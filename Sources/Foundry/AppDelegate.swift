import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shellController: ShellController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics)
        let indexingStatus = IndexingStatusStore()
        let fileSearchProvider = FileSearchProvider(diagnostics: diagnostics, indexingStatus: indexingStatus)
        let actionRunner = ActionRunner(diagnostics: diagnostics) {
            fileSearchProvider.rebuildIndex()
        }
        let registry = CommandRegistry.defaultRegistry(
            config: config,
            diagnostics: diagnostics,
            fileSearchProvider: fileSearchProvider,
            indexingStatus: indexingStatus
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
}
