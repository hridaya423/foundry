import AppKit
import ServiceManagement
import FoundryDomain
import FoundryServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shellController: ShellController?
    private var terminationPending = false
    private let launchAtLoginPromptKey = "foundry.launchAtLoginPromptShown"
    private let launchAtLoginConsentKey = "foundry.launchAtLoginConsent"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let diagnostics = DiagnosticsService()
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
        NotificationCenter.default.addObserver(forName: .foundryRequestSnippetAccessibility, object: nil, queue: .main) { [weak shellController] _ in
            Task { @MainActor in shellController?.requestSnippetAccessibility() }
        }
        NotificationCenter.default.addObserver(forName: .foundryOpenSnippetPrivacy, object: nil, queue: .main) { [weak shellController] _ in
            Task { @MainActor in shellController?.openSnippetPrivacySettings() }
        }
        NotificationCenter.default.addObserver(forName: .foundrySnippetExpansionChanged, object: nil, queue: .main) { [weak shellController] _ in
            Task { @MainActor in shellController?.reconfigureSnippetExpansion() }
        }
        shellController.start()

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.configureLoginItem(diagnostics: diagnostics)
            FirefoxConnectorInstaller(diagnostics: diagnostics).configureMainBrowser()
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
        if loginItem.status == .enabled {
            UserDefaults.standard.set(true, forKey: launchAtLoginPromptKey)
            UserDefaults.standard.set(true, forKey: launchAtLoginConsentKey)
            return
        }

        if UserDefaults.standard.object(forKey: launchAtLoginConsentKey) == nil,
           UserDefaults.standard.bool(forKey: launchAtLoginPromptKey) {
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
