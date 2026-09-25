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

        state.mode = .translator
        state.showHome()

        XCTAssertEqual(state.mode, .search, "Expected Home to use search mode")
        XCTAssertTrue(state.query.isEmpty)
        XCTAssertEqual(state.fileShelf.files.map(\.url), [fileURL])
        state.shutdown()
    }

    func testUnavailableCommandHotkeyTellsTheUser() async {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-panel-missing-\(UUID().uuidString).json"))
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState(registry: registry, actionRunner: ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics, config: config)

        await state.executeCommand(commandID: "missing.command")

        XCTAssertEqual(state.actionFeedback, .failure("That command is no longer available"))
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

        state.mode = .translator

        XCTAssertTrue(state.handleEscape())
        XCTAssertEqual(state.mode, .search, "Escape should return to Home from a feature mode")
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

        XCTAssertEqual(state.mode, .search, "Dropping on Home should not navigate away")
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
        state.mode = .translator
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
        XCTAssertNotNil(clipboard.error)

        let item = ClipboardHistoryItem(payload: .text("hello"))
        pasteboardClient.snapshotValue = PasteboardSnapshot(types: [.string], payload: item.payload, sourceBundleIdentifier: "com.example")
        pasteboardClient.changeCountValue += 1
        clipboard.captureIfChanged()
        clipboard.select(id: item.id)
        directPaste.captureTarget()

        XCTAssertTrue(state.directPasteSelectedClipboardItem())
        XCTAssertTrue(directPaste.hasPendingPaste)
        state.shutdown()
    }

    func testReopenRestoresContextWithinPopToRootTimeout() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState(registry: registry, actionRunner: ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        var clock = Date(timeIntervalSince1970: 1000)
        state.now = { clock }

        state.resetForOpen()
        let result = CommandResult(
            id: "test.result",
            title: "Test",
            subtitle: nil,
            icon: CommandIcon(fallback: "T"),
            primaryAction: CommandAction(id: "test.open", title: "Open", kind: .openSettings),
            secondaryActions: []
        )
        state.query = "tes"
        state.results = [result]
        state.selectedResultID = result.id
        state.mode = .translator
        state.panelWillClose()

        clock += 30
        state.resetForOpen()

        XCTAssertEqual(state.mode, .translator)
        XCTAssertEqual(state.query, "tes")
        XCTAssertEqual(state.results.map(\.id), [result.id])
        XCTAssertEqual(state.selectedResultID, result.id)
        state.shutdown()
    }

    func testReopenResetsAfterPopToRootTimeout() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState(registry: registry, actionRunner: ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        var clock = Date(timeIntervalSince1970: 1000)
        state.now = { clock }

        state.resetForOpen()
        state.query = "tes"
        state.results = [CommandResult(id: "test.result", title: "Test", subtitle: nil, icon: CommandIcon(fallback: "T"), primaryAction: CommandAction(id: "test.open", title: "Open", kind: .openSettings), secondaryActions: [])]
        state.mode = .translator
        state.panelWillClose()

        clock += 120
        state.resetForOpen()

        XCTAssertEqual(state.mode, .search)
        XCTAssertTrue(state.query.isEmpty)
        XCTAssertTrue(state.results.isEmpty)
        XCTAssertNil(state.selectedResultID)
        state.shutdown()
    }

    func testCompactCollapsedOnlyInSearchModeWithEmptyQuery() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState(registry: registry, actionRunner: ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics, config: config)

        XCTAssertFalse(state.compactCollapsed)
        state.setWindowMode(.compact)
        XCTAssertTrue(state.compactCollapsed)

        state.query = "saf"
        XCTAssertFalse(state.compactCollapsed)

        state.query = ""
        state.isShowingActions = true
        XCTAssertFalse(state.compactCollapsed)

        state.isShowingActions = false
        state.mode = .translator
        XCTAssertFalse(state.compactCollapsed)
        state.shutdown()
    }

    func testHomeSuggestionColdStartRules() {
        let running: Set<String> = ["com.apple.Safari"]

        XCTAssertTrue(HomeSuggestionRules.isSuggestible(resultID: "app.com.apple.Safari", runningBundleIDs: running, hasUsage: false))
        XCTAssertTrue(HomeSuggestionRules.isSuggestible(resultID: "app.com.apple.Terminal", runningBundleIDs: [], hasUsage: true))
        XCTAssertFalse(HomeSuggestionRules.isSuggestible(resultID: "app.com.apple.Terminal", runningBundleIDs: running, hasUsage: false))
        XCTAssertFalse(HomeSuggestionRules.isSuggestible(resultID: "app.com.apple.BluetoothFileExchange", runningBundleIDs: ["com.apple.BluetoothFileExchange"], hasUsage: true))
        XCTAssertFalse(HomeSuggestionRules.isSuggestible(resultID: "foundry.clipboard", runningBundleIDs: running, hasUsage: true))
    }

    func testActionFilterIsIndependentOfQueryAndEscapeRestoresTheList() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState(registry: registry, actionRunner: ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        let result = CommandResult(
            id: "test.file",
            title: "Report",
            subtitle: nil,
            icon: CommandIcon(fallback: "F"),
            primaryAction: CommandAction(id: "open", title: "Open", kind: .log("open")),
            secondaryActions: [
                CommandAction(id: "copy-file", title: "Copy File", kind: .copyFile(path: "/tmp/report")),
                CommandAction(id: "copy", title: "Copy Path", kind: .copyToClipboard("/tmp/report"))
            ]
        )
        state.results = [result]
        state.selectedResultID = result.id

        state.toggleActions()
        state.actionFilter = "copy pa"
        XCTAssertEqual(state.visibleActions.map(\.id), ["copy"])
        XCTAssertEqual(state.selectedActionID, "copy")
        XCTAssertEqual(state.query, "")

        state.actionFilter = "zzz"
        XCTAssertTrue(state.visibleActions.isEmpty)
        XCTAssertNil(state.selectedActionID)

        XCTAssertTrue(state.handleEscape())
        XCTAssertTrue(state.isShowingActions, "first escape clears the filter")
        XCTAssertEqual(state.visibleActions.count, state.selectedActions.count)
        XCTAssertTrue(state.handleEscape())
        XCTAssertFalse(state.isShowingActions)
        XCTAssertEqual(state.results.map(\.id), [result.id], "escape keeps the result list")
        XCTAssertEqual(state.selectedResultID, result.id)
        state.shutdown()
    }

    func testActionShortcutsAreAssignedOnceAndFireWithoutOpeningActions() async throws {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState(registry: registry, actionRunner: ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        let result = CommandResult(
            id: "test.shortcuts",
            title: "Report",
            subtitle: nil,
            icon: CommandIcon(fallback: "F"),
            primaryAction: CommandAction(id: "open", title: "Open", kind: .log("open")),
            secondaryActions: [
                CommandAction(id: "copy", title: "Copy", kind: .copyToClipboard("a")),
                CommandAction(id: "copy2", title: "Copy Path", kind: .copyToClipboard("b")),
                CommandAction(id: "delete", title: "Delete Snippet", kind: .deleteSnippet(id: "x"))
            ]
        )
        state.results = [result]
        state.selectedResultID = result.id

        let shortcuts = state.actionShortcuts
        XCTAssertNil(shortcuts["open"])
        XCTAssertEqual(shortcuts["copy"], .secondary)
        XCTAssertEqual(shortcuts["copy2"]?.display, "⇧⌘C")
        XCTAssertEqual(shortcuts["delete"]?.display, "⌃X")
        XCTAssertEqual(shortcuts["favorite.toggle.\(result.id)"]?.display, "⌘D")
        XCTAssertEqual(Set(shortcuts.values).count, shortcuts.count, "no chord is bound twice")

        XCTAssertFalse(state.performActionShortcut(ActionShortcut(key: "j", modifiers: [.command])) {})
        XCTAssertTrue(state.performActionShortcut(ActionShortcut(key: "d", modifiers: [.command])) {})
        XCTAssertFalse(state.isShowingActions)
        for _ in 0..<100 where state.commandPreferences[result.id]?.favoriteRank == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(state.commandPreferences[result.id]?.favoriteRank)
        state.shutdown()
    }

    func testDeveloperToolsNumberChordsSwitchTools() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState(registry: registry, actionRunner: ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        state.mode = .developerTools
        XCTAssertTrue(state.performModeShortcut(ActionShortcut(key: "3", modifiers: [.command])) {})
        XCTAssertEqual(state.developerTools.selectedTool, DeveloperToolsState.Tool.allCases[2])
        XCTAssertFalse(state.performModeShortcut(ActionShortcut(key: "9", modifiers: [.command])) {})
        state.shutdown()
    }

    func testCommandYRequestsQuickLookForFileResultsOnly() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState(registry: registry, actionRunner: ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        var lookedAt: [URL] = []
        state.onQuickLook = { lookedAt.append($0) }
        state.results = [
            CommandResult(id: "file./tmp/report.pdf", title: "report.pdf", subtitle: nil, icon: CommandIcon(fallback: "F"), primaryAction: CommandAction(id: "open", title: "Open", kind: .log("open")), secondaryActions: []),
            CommandResult(id: "app.safari", title: "Safari", subtitle: nil, icon: CommandIcon(fallback: "S"), primaryAction: CommandAction(id: "open", title: "Open", kind: .log("open")), secondaryActions: []),
        ]
        state.selectedResultID = "app.safari"
        XCTAssertFalse(state.performModeShortcut(ActionShortcut(key: "y", modifiers: [.command])) {})
        XCTAssertTrue(lookedAt.isEmpty)
        state.selectedResultID = "file./tmp/report.pdf"
        XCTAssertTrue(state.performModeShortcut(ActionShortcut(key: "y", modifiers: [.command])) {})
        XCTAssertEqual(lookedAt, [URL(fileURLWithPath: "/tmp/report.pdf")])
        state.shutdown()
    }

    func testFavoriteActionTogglesAndResolvesFavoriteResults() async throws {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let registry = CommandRegistry(
            providers: [FavoriteStubProvider()],
            usageRanking: UsageRankingStore(diagnostics: diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        let state = CommandPanelState(registry: registry, actionRunner: ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        let result = CommandResult(
            id: "test.favorite",
            title: "Favorite Me",
            subtitle: nil,
            icon: CommandIcon(fallback: "F"),
            primaryAction: CommandAction(id: "test.favorite.open", title: "Open", kind: .log("fav")),
            secondaryActions: []
        )
        state.results = [result]
        state.selectedResultID = result.id

        let addAction = state.selectedActions.first { action in
            if case .toggleFavorite = action.kind { return true }
            return false
        }
        XCTAssertEqual(addAction?.title, "Add to Favorites")

        state.toggleFavorite(commandID: result.id)
        XCTAssertTrue(state.commandPreferences[result.id]?.favoriteRank != nil)
        XCTAssertEqual(state.selectedActions.first { $0.id == addAction?.id }?.title, "Remove from Favorites")

        for _ in 0..<100 where state.favoriteResults.isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(state.favoriteResults.map(\.id), [result.id])

        state.toggleFavorite(commandID: result.id)
        for _ in 0..<100 where state.favoriteResults.isEmpty == false {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(state.favoriteResults.isEmpty)
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

final class TestClipboardPasteboard: PasteboardClient, @unchecked Sendable {
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

private struct FavoriteStubProvider: CommandProvider {
    let id = "test.favorite-stub"

    func search(_ request: CommandSearchRequest) async throws -> [CommandResult] { [] }

    func defaultResults() async throws -> [CommandResult] {
        [CommandResult(
            id: "test.favorite",
            title: "Favorite Me",
            subtitle: nil,
            icon: CommandIcon(fallback: "F"),
            primaryAction: CommandAction(id: "test.favorite.open", title: "Open", kind: .log("fav")),
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
