import AppKit
import Foundation
import FoundryDomain
import FoundryServices
import XCTest
@testable import Foundry

struct EmptyAgentCollector: AgentMonitorCollecting {
    func collect() -> [AgentSessionCard] { [] }
}

struct InertWindowManager: WindowManaging {
    func apply(_ placement: WindowPlacement) async -> WindowOperationResult { .needsAccessibilityPermission }
}

enum TestScratch {
    static func directory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func pasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("foundry.tests.\(UUID().uuidString)"))
    }
}

extension XCTestCase {
    func isolatedDefaultsSuite(_ label: String) -> String {
        let directory = TestScratch.directory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent(label).path
    }
}

extension AgentMonitorState {
    static func isolated(collector: any AgentMonitorCollecting = EmptyAgentCollector()) -> AgentMonitorState {
        let directory = TestScratch.directory()
        return AgentMonitorState(
            integrationInstaller: AgentIntegrationInstaller(homeDirectory: directory, executableURL: URL(fileURLWithPath: "/Foundry")),
            collector: collector,
            socketURL: directory.appendingPathComponent("agents.sock")
        )
    }
}

extension DirectPasteService {
    static func isolated(
        pasteboard: NSPasteboard = TestScratch.pasteboard(),
        ownProcessIdentifier: pid_t = 7,
        targetProvider: @escaping () -> (any DirectPasteTarget)? = { nil },
        accessibilityTrusted: @escaping () -> Bool = { false },
        record: @escaping (DirectPasteEvent) -> Void = { _ in },
        sendPaste: @escaping () -> Bool = { true },
        sendLeft: @escaping () -> Bool = { true }
    ) -> DirectPasteService {
        DirectPasteService(pasteboard: pasteboard, ownProcessIdentifier: ownProcessIdentifier, targetProvider: targetProvider,
            accessibilityTrusted: accessibilityTrusted, record: record, sendPaste: sendPaste, sendLeft: sendLeft)
    }
}

extension ActionRunner {
    static func isolated(
        diagnostics: DiagnosticsService,
        snippetStore: any SnippetStore = FileSnippetStore(url: TestScratch.directory().appendingPathComponent("snippets.json")),
        mediaDownloadService: any MediaDownloading = MediaDownloadService(),
        mediaDownloadManager: MediaDownloadManager = MediaDownloadManager(),
        resetRanking: @escaping (String) -> Void = { _ in },
        trashItem: @escaping (URL) throws -> Void = { _ in throw CocoaError(.fileWriteNoPermission) },
        confirmAction: (@MainActor (CommandActionDescriptor, CommandInvocationSource) async -> Bool)? = nil,
        windowManager: any WindowManaging = InertWindowManager(),
        openURL: @escaping (URL) -> Bool = { _ in true },
        openApplication: @escaping (URL, NSWorkspace.OpenConfiguration, @escaping @Sendable (NSRunningApplication?, Error?) -> Void) -> Void = { _,
            _, completion in
            completion(nil, nil)
        },
        directPasteService: DirectPasteService = .isolated(),
        pasteboard: NSPasteboard = TestScratch.pasteboard(),
        snippetContext: @escaping () -> SnippetRenderContext = { SnippetRenderContext(now: Date(), locale: .current, calendar: .current, clipboard: "") },
        scriptDirectories: ScriptDirectoryStore = ScriptDirectoryStore(localState: LocalStateStore()),
        localState: LocalStateStore = LocalStateStore(),
        confirmScriptDirectory: (@MainActor (String) async -> Bool)? = nil,
        scriptTimeout: TimeInterval = 30,
        scriptOutputLimit: Int = 256 * 1024
    ) -> ActionRunner {
        ActionRunner(diagnostics: diagnostics, snippetStore: snippetStore, mediaDownloadService: mediaDownloadService,
            mediaDownloadManager: mediaDownloadManager, resetRanking: resetRanking, trashItem: trashItem, confirmAction: confirmAction,
            windowManager: windowManager, openURL: openURL, openApplication: openApplication, directPasteService: directPasteService,
            pasteboard: pasteboard, snippetContext: snippetContext, scriptDirectories: scriptDirectories, localState: localState,
            confirmScriptDirectory: confirmScriptDirectory, scriptTimeout: scriptTimeout, scriptOutputLimit: scriptOutputLimit)
    }
}

extension CommandPanelState {
    static func isolated(
        registry: CommandRegistry,
        actionRunner: ActionRunner,
        diagnostics: DiagnosticsService,
        config: ConfigService,
        snippetStore: (any SnippetStore)? = nil,
        mediaDownloadManager: MediaDownloadManager = MediaDownloadManager(),
        clipboardHistory: ClipboardHistoryState? = nil,
        localState: LocalStateStore = LocalStateStore(),
        latestRelease: @escaping @Sendable () async -> Data? = { nil },
        installedVersion: String? = nil
    ) -> CommandPanelState {
        CommandPanelState(
            registry: registry,
            actionRunner: actionRunner,
            diagnostics: diagnostics,
            config: config,
            snippetStore: snippetStore,
            mediaDownloadManager: mediaDownloadManager,
            clipboardHistory: clipboardHistory ?? ClipboardHistoryState(
                pasteboard: TestClipboardPasteboard(), persistence: nil, configuration: config.current.clipboard),
            localState: localState,
            agents: .isolated(),
            latestRelease: latestRelease,
            installedVersion: installedVersion
        )
    }
}

extension XCTestCase {
    func requireWindowTestsEnabled() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FOUNDRY_WINDOW_TESTS"] == "1",
            "Opens real windows, registers global hotkeys or binds the live agent socket. Set FOUNDRY_WINDOW_TESTS=1 on a machine where Foundry is not running."
        )
    }
}
