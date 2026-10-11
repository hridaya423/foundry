import AppKit
import ServiceManagement
import FoundryDomain
import FoundryServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shellController: ShellController?
    private var terminationPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        let diagnostics = DiagnosticsService()
        let launchSpan = diagnostics.startSpan("app.launch.ready")
        let config = ConfigService(diagnostics: diagnostics)
        LocalStateStore.shared.bind(to: config)
        let snippetStore = FileSnippetStore()
        let usageRanking = UsageRankingStore(diagnostics: diagnostics)
        let mediaDownloadManager = MediaDownloadManager()
        let directPasteService = DirectPasteService()
        let actionRunner = ActionRunner(
            diagnostics: diagnostics,
            snippetStore: snippetStore,
            mediaDownloadManager: mediaDownloadManager,
            resetRanking: { commandID in
                usageRanking.resetRanking(for: commandID)
            },
            confirmAction: { action, source in
                Self.confirm(action: action, source: source)
            },
            directPasteService: directPasteService
        )

        let registry = CommandRegistry.defaultRegistry(
            config: config,
            diagnostics: diagnostics,
            snippetStore: snippetStore,
            usageRanking: usageRanking
        )
        let shellController = ShellController(
            registry: registry,
            actionRunner: actionRunner,
            config: config,
            diagnostics: diagnostics,
            snippetStore: snippetStore,
            mediaDownloadManager: mediaDownloadManager
        )

        self.shellController = shellController
        DownloadNotice.showIfNeeded()
        shellController.start()
        diagnostics.endSpan(launchSpan)

        if let convertPaths = Self.convertArguments() {
            shellController.openFileConverter(paths: convertPaths)
        }

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.configureLoginItem(config: config, diagnostics: diagnostics)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        shellController?.showPanel()
        return false
    }

    /// Finder "Open With…" and dropping files onto the Dock icon route here —
    /// the app declares `public.data`/`public.folder` document types so any
    /// file can be sent straight into the converter.
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        application(sender, openFiles: [filename])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        shellController?.openFileConverter(paths: filenames)
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationPending == false else { return .terminateLater }
        terminationPending = true
        Task { @MainActor [weak self] in
            await self?.shellController?.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        shellController?.stop()
        KeepAwakeController.stop()
    }

    /// `--convert <path> [<path>…]` — scriptable entry into the converter
    /// (`open -a Foundry --args --convert ~/Desktop/photo.heic`).
    private static func convertArguments() -> [String]? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--convert"), index + 1 < args.count else { return nil }
        let paths = args[(index + 1)...].prefix { $0.hasPrefix("--") == false }
        return paths.isEmpty ? nil : Array(paths)
    }

    private static func confirm(action: CommandActionDescriptor, source: CommandInvocationSource) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(action.title)?"
        if source == .external {
            alert.informativeText = "Requested by an external integration."
        }
        alert.addButton(withTitle: action.title)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func configureLoginItem(config: ConfigService, diagnostics: DiagnosticsService) {
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.bundleIdentifier == "com.hridya.foundry" else {
            diagnostics.log("Skipping login-item setup outside a packaged app")
            return
        }
        let loginItem = SMAppService.mainApp
        guard config.current.localState.launchAtLoginConsent,
              loginItem.status != .enabled else { return }
        do {
            try loginItem.register()
            diagnostics.log("Re-registered Foundry as a login item")
        } catch {
            diagnostics.log("Could not restore Foundry login item: \(error.localizedDescription)")
        }
    }
}
