import XCTest
@testable import Foundry
import FoundryDomain
import FoundryServices

@MainActor
final class CommandPanelStateTests: XCTestCase {
    func testHomePreservesShelfAndReturnsFromFeatureModes() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(
            diagnostics: diagnostics,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-panel-home-\(UUID().uuidString).json")
        )
        let registry = CommandRegistry(
            providers: [],
            usageRanking: UsageRankingStore(diagnostics: diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        let state = CommandPanelState(
            registry: registry,
            actionRunner: ActionRunner(diagnostics: diagnostics),
            diagnostics: diagnostics,
            config: config
        )
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("home-file.txt")
        state.fileShelf.add(urls: [fileURL])

        state.openSettings()
        state.showHome()

        if case .search = state.mode {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected Home to use search mode")
        }
        XCTAssertTrue(state.query.isEmpty)
        XCTAssertEqual(state.fileShelf.files.map(\.url), [fileURL])
        state.shutdown()
    }

    func testEscapeReturnsFromAFeatureMode() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(
            diagnostics: diagnostics,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-panel-escape-\(UUID().uuidString).json")
        )
        let registry = CommandRegistry(
            providers: [],
            usageRanking: UsageRankingStore(diagnostics: diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        let state = CommandPanelState(
            registry: registry,
            actionRunner: ActionRunner(diagnostics: diagnostics),
            diagnostics: diagnostics,
            config: config
        )

        state.openSettings()

        XCTAssertTrue(state.handleEscape())
        if case .search = state.mode {
            XCTAssertTrue(true)
        } else {
            XCTFail("Escape should return to Home from Settings")
        }
        state.shutdown()
    }

    func testDroppedFilesStayOnHomeAndReportTheBatch() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(
            diagnostics: diagnostics,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-panel-drop-\(UUID().uuidString).json")
        )
        let registry = CommandRegistry(
            providers: [],
            usageRanking: UsageRankingStore(diagnostics: diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        let state = CommandPanelState(
            registry: registry,
            actionRunner: ActionRunner(diagnostics: diagnostics),
            diagnostics: diagnostics,
            config: config
        )
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("dropped.txt")

        state.handleDroppedFiles([fileURL, fileURL])

        if case .search = state.mode {
            XCTAssertTrue(true)
        } else {
            XCTFail("Dropping on Home should not navigate away")
        }
        XCTAssertEqual(state.fileShelf.files.count, 1)
        XCTAssertEqual(state.actionFeedback?.message, "Added 1 file to File Shelf · 1 already waiting")
        state.shutdown()
    }

    func testMediaURLBecomesSelectedWhenImmediateResultsAlsoMatch() async throws {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(
            diagnostics: diagnostics,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-panel-media-selection-\(UUID().uuidString).json")
        )
        let registry = CommandRegistry(
            providers: [URLCollisionProvider(), MediaDownloadProvider()],
            usageRanking: UsageRankingStore(diagnostics: diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        let state = CommandPanelState(
            registry: registry,
            actionRunner: ActionRunner(diagnostics: diagnostics),
            diagnostics: diagnostics,
            config: config
        )

        state.query = "http://127.0.0.1:8765/video.mp4"
        for _ in 0..<40 where state.selectedResult?.route != .mediaDownload {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(state.selectedResult?.route, .mediaDownload)
        state.shutdown()
    }

    func testClosingPanelDetachesFromABackgroundDownloadWithoutCancellingIt() async throws {
        let media = DelayedMediaDownloadService()
        let diagnostics = DiagnosticsService()
        let config = ConfigService(
            diagnostics: diagnostics,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-panel-state-\(UUID().uuidString).json")
        )
        let registry = CommandRegistry(
            providers: [],
            usageRanking: UsageRankingStore(diagnostics: diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        let state = CommandPanelState(
            registry: registry,
            actionRunner: ActionRunner(diagnostics: diagnostics, mediaDownloadService: media),
            diagnostics: diagnostics,
            config: config
        )
        state.results = [CommandResult(
            id: "test.background-download",
            title: "Download",
            subtitle: nil,
            icon: CommandIcon(fallback: "D"),
            primaryAction: CommandAction(
                id: "test.background-download.perform",
                title: "Download",
                kind: .downloadMedia(url: "https://example.com/file.mp4")
            ),
            secondaryActions: []
        )]
        state.selectedResultID = "test.background-download"

        let execution = Task { await state.executeSelectedResult() }
        try await Task.sleep(for: .milliseconds(20))
        state.panelWillClose()

        let shouldDismiss = await execution.value
        let completed = await media.didComplete()

        XCTAssertFalse(shouldDismiss)
        XCTAssertTrue(completed)
        state.shutdown()
    }

    func testClipboardMonitoringSurvivesPanelCloseAndModeChanges() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let pasteboardClient = TestClipboardPasteboard()
        let clipboard = ClipboardHistoryState(pasteboard: pasteboardClient, persistence: nil, configuration: config.current.clipboard)
        let state = makeState(diagnostics: diagnostics, config: config, clipboard: clipboard)

        clipboard.start()
        state.openSettings()
        state.panelWillClose()

        XCTAssertTrue(clipboard.isMonitoring)
        state.shutdown()
        XCTAssertFalse(clipboard.isMonitoring)
    }

    func testShellCompositionStartsClipboardOnceAndReloadsArchive() {
        let diagnostics = DiagnosticsService()
        let archiveURL = temporaryURL()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let pasteboard = TestClipboardPasteboard()
        let persistence = ClipboardHistoryPersistence(url: archiveURL)
        let clipboard = ClipboardHistoryState(pasteboard: pasteboard, persistence: persistence, configuration: config.current.clipboard)
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        let actionRunner = ActionRunner(diagnostics: diagnostics)
        let shell = ShellController(registry: registry, actionRunner: actionRunner, config: config, diagnostics: diagnostics, clipboardHistory: clipboard)

        shell.start()
        shell.start()
        XCTAssertTrue(clipboard.isMonitoring)
        shell.stop()
        XCTAssertFalse(clipboard.isMonitoring)

        let item = ClipboardHistoryItem(payload: .text("saved"))
        try? persistence.save([item])
        let freshClipboard = ClipboardHistoryState(pasteboard: TestClipboardPasteboard(), persistence: persistence, configuration: config.current.clipboard)
        XCTAssertEqual(freshClipboard.items, [item])
    }

    func testClipboardSettingsReconfigureTheSharedState() throws {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let clipboard = ClipboardHistoryState(pasteboard: TestClipboardPasteboard(), persistence: nil, configuration: config.current.clipboard)
        let state = makeState(diagnostics: diagnostics, config: config, clipboard: clipboard)

        state.setClipboardPaused(true)
        state.setClipboardRetention(maxItems: 12, maxBytes: 2 * 1024 * 1024)
        state.setClipboardExcludedBundleIdentifiers("com.example, com.example, com.other")

        XCTAssertTrue(clipboard.isPaused)
        XCTAssertEqual(config.current.clipboard.maxItems, 12)
        XCTAssertEqual(config.current.clipboard.maxBytes, 2 * 1024 * 1024)
        XCTAssertEqual(config.current.clipboard.excludedBundleIdentifiers, ["com.example", "com.other"])
        state.shutdown()
    }

    func testDirectPasteStagesSelectedItemAndLeavesFailureActionable() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CommandPanelStateTests.directPaste"))
        let target = DirectPasteTestTarget(processIdentifier: 42)
        let directPaste = DirectPasteService(pasteboard: pasteboard, ownProcessIdentifier: 7) { target }
        let actionRunner = ActionRunner(diagnostics: diagnostics, directPasteService: directPaste)
        let pasteboardClient = TestClipboardPasteboard()
        let clipboard = ClipboardHistoryState(pasteboard: pasteboardClient, persistence: nil, configuration: config.current.clipboard)
        let state = makeState(diagnostics: diagnostics, config: config, clipboard: clipboard, actionRunner: actionRunner)

        clipboard.select(id: clipboard.items.first?.id ?? "missing")
        XCTAssertFalse(state.directPasteSelectedClipboardItem())
        XCTAssertTrue(state.diagnosticsSummary.contains("Could not stage paste"))

        let item = ClipboardHistoryItem(payload: .text("hello"))
        pasteboardClient.snapshotValue = PasteboardSnapshot(types: [.string], payload: item.payload, sourceBundleIdentifier: "com.example")
        pasteboardClient.changeCountValue += 1
        clipboard.captureIfChangedForTesting()
        clipboard.select(id: item.id)
        directPaste.captureTarget()

        XCTAssertTrue(state.directPasteSelectedClipboardItem())
        XCTAssertTrue(directPaste.hasPendingPaste)
        state.shutdown()
    }

    private func makeState(diagnostics: DiagnosticsService, config: ConfigService, clipboard: ClipboardHistoryState, actionRunner: ActionRunner? = nil) -> CommandPanelState {
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        return CommandPanelState(registry: registry, actionRunner: actionRunner ?? ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics, config: config, clipboardHistory: clipboard)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("foundry-panel-\(UUID().uuidString).json")
    }

    func testSearchLoadingStaysActiveUntilTheLatestSearchCompletes() async throws {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(
            diagnostics: diagnostics,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-panel-loading-\(UUID().uuidString).json")
        )
        let registry = CommandRegistry(
            providers: [SlowSearchProvider()],
            usageRanking: UsageRankingStore(diagnostics: diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        let state = CommandPanelState(
            registry: registry,
            actionRunner: ActionRunner(diagnostics: diagnostics),
            diagnostics: diagnostics,
            config: config
        )

        state.query = "slow"
        try await Task.sleep(for: .milliseconds(15))
        XCTAssertTrue(state.isSearchLoading)

        for _ in 0..<30 where state.isSearchLoading {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(state.isSearchLoading)
        state.shutdown()
    }

    private actor DelayedMediaDownloadService: MediaDownloading {
        nonisolated let downloadFolder = URL(fileURLWithPath: "/tmp")
        private var completed = false

        func download(
            urlString: String,
            status: (@MainActor @Sendable (String) -> Void)?
        ) async throws -> String {
            try await Task.sleep(for: .milliseconds(100))
            completed = true
            return "Downloaded file.mp4"
        }

        func didComplete() -> Bool {
            completed
        }
    }
}

private final class TestClipboardPasteboard: PasteboardClient, @unchecked Sendable {
    var changeCountValue = 0
    var snapshotValue: PasteboardSnapshot?
    var changeCount: Int { changeCountValue }
    func snapshot() -> PasteboardSnapshot? { snapshotValue }
    func write(_ payload: ClipboardPayload) {}
}

private final class DirectPasteTestTarget: NSObject, DirectPasteTarget {
    let processIdentifier: pid_t
    init(processIdentifier: pid_t) { self.processIdentifier = processIdentifier }
    func activate(options: NSApplication.ActivationOptions) -> Bool { true }
}

private struct URLCollisionProvider: CommandProvider {
    let id = "test.url-collision"
    var searchPolicy: CommandProviderSearchPolicy { CommandProviderSearchPolicy(tier: .immediate) }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        guard request.query.contains("127") else { return [] }
        return [CommandResult(
            id: "test.kill-port",
            title: "Kill Port 127",
            subtitle: "Unrelated immediate result",
            icon: CommandIcon(fallback: "P"),
            primaryAction: CommandAction(id: "test.kill-port.perform", title: "Run", kind: .log("collision")),
            secondaryActions: []
        )]
    }
}

private struct SlowSearchProvider: CommandProvider {
    let id = "test.slow-search"

    func search(_ request: CommandSearchRequest) async throws -> [CommandResult] {
        try await Task.sleep(for: .milliseconds(80))
        return []
    }
}
