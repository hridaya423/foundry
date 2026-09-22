import AppKit
import ServiceManagement
import FoundryDomain
import FoundryServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shellController: ShellController?
    private var terminationPending = false
    private let launchAtLoginConsentKey = "foundry.launchAtLoginConsent"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        let diagnostics = DiagnosticsService()
        let launchSpan = diagnostics.startSpan("app.launch.ready")
        let config = ConfigService(diagnostics: diagnostics)
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
        shellController.start()
        diagnostics.endSpan(launchSpan)

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.configureLoginItem(diagnostics: diagnostics)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        shellController?.showPanel()
        return false
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

    private static func confirm(action: CommandActionDescriptor, source: CommandInvocationSource) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Confirm \(action.title)"
        alert.informativeText = source == .external
            ? "An external integration requested this destructive action. Continue?"
            : "This action can change or terminate system state. Continue?"
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func configureLoginItem(diagnostics: DiagnosticsService) {
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.bundleIdentifier == "com.hridya.foundry" else {
            diagnostics.log("Skipping login-item setup outside a packaged app")
            return
        }
        let loginItem = SMAppService.mainApp
        guard UserDefaults.standard.bool(forKey: launchAtLoginConsentKey),
              loginItem.status != .enabled else { return }
        do {
            try loginItem.register()
            diagnostics.log("Re-registered Foundry as a login item")
        } catch {
            diagnostics.log("Could not restore Foundry login item: \(error.localizedDescription)")
        }
    }
}
