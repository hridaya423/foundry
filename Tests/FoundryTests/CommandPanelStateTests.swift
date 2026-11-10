import os
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
            usageRanking: UsageRankingStore.scratch(diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        let state = CommandPanelState.isolated(
            registry: registry,
            actionRunner: ActionRunner.isolated(diagnostics: diagnostics),
            diagnostics: diagnostics,
            config: config
        )
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("home-file.txt")
        state.fileShelf.add(urls: [fileURL])

        state.mode = .translator
        state.showHome()

        XCTAssertEqual(state.mode, .search, "Expected Home to use search mode")
        XCTAssertTrue(state.session.query.isEmpty)
        XCTAssertEqual(state.fileShelf.files.map(\.url), [fileURL])
        state.shutdown()
    }

    func testUnavailableCommandHotkeyTellsTheUser() async {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-panel-missing-\(UUID().uuidString).json"))
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics, config: config)

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
            usageRanking: UsageRankingStore.scratch(diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        let state = CommandPanelState.isolated(
            registry: registry,
            actionRunner: ActionRunner.isolated(diagnostics: diagnostics),
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
            usageRanking: UsageRankingStore.scratch(diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        let state = CommandPanelState.isolated(
            registry: registry,
            actionRunner: ActionRunner.isolated(diagnostics: diagnostics),
            diagnostics: diagnostics,
            config: config
        )
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("dropped.txt")

        state.handleDroppedFiles([fileURL, fileURL])

        XCTAssertEqual(state.mode, .search, "Dropping on Home should not navigate away")
        XCTAssertEqual(state.pendingDropURLs, [fileURL, fileURL], "Drops present the action chooser first")
        XCTAssertEqual(state.dropChoices, [.shelf, .convert, .compress])

        state.resolveDrop(.shelf)

        XCTAssertNil(state.pendingDropURLs)
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
            usageRanking: UsageRankingStore.scratch(diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        let state = CommandPanelState.isolated(
            registry: registry,
            actionRunner: ActionRunner.isolated(diagnostics: diagnostics),
            diagnostics: diagnostics,
            config: config
        )

        state.session.query = "http://127.0.0.1:8765/video.mp4"
        for _ in 0..<40 where state.session.selectedResult?.route != .mediaDownload {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(state.session.selectedResult?.route, .mediaDownload)
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
            usageRanking: UsageRankingStore.scratch(diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        let state = CommandPanelState.isolated(
            registry: registry,
            actionRunner: ActionRunner.isolated(diagnostics: diagnostics, mediaDownloadService: media),
            diagnostics: diagnostics,
            config: config
        )
        state.session.results = [CommandResult(
            id: "test.background-download",
            title: "Download",
            subtitle: nil,
            icon: CommandIcon(fallback: "D"),
            payload: .command,
            primaryAction: CommandAction(
                id: "test.background-download.perform",
                title: "Download",
                behavior: DownloadMediaAction(url: "https://example.com/file.mp4")
            ),
            secondaryActions: []
        )]
        state.session.selectedResultID = "test.background-download"

        let execution = Task { await state.executeSelectedResult() }
        try await Task.sleep(for: .milliseconds(20))
        state.panelWillClose()

        let shouldDismiss = await execution.value
        let completed = await media.didComplete()

        XCTAssertFalse(shouldDismiss)
        XCTAssertTrue(completed)
        state.shutdown()
    }

    /// The clipboard poll only runs while the panel is open — a wake every
    /// 0.7 s forever was the launcher's biggest idle CPU cost.
    func testClipboardMonitoringStopsWhenThePanelCloses() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let pasteboardClient = TestClipboardPasteboard()
        let clipboard = ClipboardHistoryState(pasteboard: pasteboardClient, persistence: nil, configuration: config.current.clipboard)
        let state = makeState(diagnostics: diagnostics, config: config, clipboard: clipboard)

        XCTAssertFalse(clipboard.isMonitoring)
        state.resetForOpen()
        XCTAssertTrue(clipboard.isMonitoring)
        state.mode = .translator
        state.panelWillClose()

        XCTAssertFalse(clipboard.isMonitoring)
        state.shutdown()
        XCTAssertFalse(clipboard.isMonitoring)
    }

    /// Launch does a one-shot capture, not a running poll — the timer arms
    /// only when the panel opens.
    func testShellCompositionCapturesClipboardOnceAtLaunchAndReloadsArchive() throws {
        try requireWindowTestsEnabled()
        let diagnostics = DiagnosticsService()
        let archiveURL = temporaryURL()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let pasteboard = TestClipboardPasteboard()
        let persistence = ClipboardHistoryPersistence(url: archiveURL)
        let clipboard = ClipboardHistoryState(pasteboard: pasteboard, persistence: persistence, configuration: config.current.clipboard)
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        let actionRunner = ActionRunner.isolated(diagnostics: diagnostics)
        let shell = ShellController(registry: registry, actionRunner: actionRunner, config: config, diagnostics: diagnostics, clipboardHistory: clipboard)
        pasteboard.snapshotValue = PasteboardSnapshot(types: [.string], payload: .text("captured at launch"), sourceBundleIdentifier: "com.example")
        pasteboard.changeCountValue += 1

        shell.start()
        shell.start()
        XCTAssertFalse(clipboard.isMonitoring)
        XCTAssertEqual(clipboard.items.map(\.payload), [.text("captured at launch")])
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

        state.settings.setClipboardPaused(true)
        state.settings.setClipboardRetention(maxItems: 12, maxBytes: 2 * 1024 * 1024)
        state.settings.setClipboardExcludedBundleIdentifiers("com.example, com.example, com.other")

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
        let directPaste = DirectPasteService.isolated(pasteboard: pasteboard, ownProcessIdentifier: 7, targetProvider: { target },
            accessibilityTrusted: { true })
        let actionRunner = ActionRunner.isolated(diagnostics: diagnostics, directPasteService: directPaste)
        let pasteboardClient = TestClipboardPasteboard()
        let clipboard = ClipboardHistoryState(pasteboard: pasteboardClient, persistence: nil, configuration: config.current.clipboard)
        let state = makeState(diagnostics: diagnostics, config: config, clipboard: clipboard, actionRunner: actionRunner)

        clipboard.select(id: clipboard.items.first?.id ?? "missing")
        XCTAssertFalse(state.directPasteSelectedClipboardItem())
        XCTAssertEqual(state.actionFeedback, .failure("Select an item to paste."))
        XCTAssertNil(clipboard.error)

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

    func testPasteWithNoTargetAppCopiesAndSaysSo() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CommandPanelStateTests.noTarget"))
        let directPaste = DirectPasteService.isolated(pasteboard: pasteboard, ownProcessIdentifier: 7, targetProvider: { nil }, accessibilityTrusted: { true })
        let actionRunner = ActionRunner.isolated(diagnostics: diagnostics, directPasteService: directPaste)
        let pasteboardClient = TestClipboardPasteboard()
        let clipboard = ClipboardHistoryState(pasteboard: pasteboardClient, persistence: nil, configuration: config.current.clipboard)
        let state = makeState(diagnostics: diagnostics, config: config, clipboard: clipboard, actionRunner: actionRunner)
        let item = ClipboardHistoryItem(payload: .text("hello"))
        pasteboardClient.snapshotValue = PasteboardSnapshot(types: [.string], payload: item.payload, sourceBundleIdentifier: "com.example")
        pasteboardClient.changeCountValue += 1
        clipboard.captureIfChanged()
        clipboard.select(id: item.id)

        XCTAssertFalse(state.directPasteSelectedClipboardItem())
        XCTAssertEqual(state.actionFeedback, .info("Copied. Press ⌘V where you want it."))
        XCTAssertEqual(pasteboardClient.writtenPayloads, [.text("hello")])
        state.shutdown()
    }

    func testReturnStagesDirectPasteFromClipboardMode() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CommandPanelStateTests.optionReturn"))
        let target = DirectPasteTestTarget(processIdentifier: 42)
        let directPaste = DirectPasteService.isolated(pasteboard: pasteboard, ownProcessIdentifier: 7, targetProvider: { target }, accessibilityTrusted: { true })
        let actionRunner = ActionRunner.isolated(diagnostics: diagnostics, directPasteService: directPaste)
        let pasteboardClient = TestClipboardPasteboard()
        let clipboard = ClipboardHistoryState(pasteboard: pasteboardClient, persistence: nil, configuration: config.current.clipboard)
        let state = makeState(diagnostics: diagnostics, config: config, clipboard: clipboard, actionRunner: actionRunner)

        let item = ClipboardHistoryItem(payload: .text("hello"))
        pasteboardClient.snapshotValue = PasteboardSnapshot(types: [.string], payload: item.payload, sourceBundleIdentifier: "com.example")
        pasteboardClient.changeCountValue += 1
        clipboard.captureIfChanged()
        clipboard.select(id: item.id)
        directPaste.captureTarget()

        state.mode = .clipboardHistory
        state.directPasteSelectedClipboardItem()
        XCTAssertTrue(directPaste.hasPendingPaste)
        state.shutdown()
    }

    func testPasteWithoutAccessibilityAsksInThePanelAndKeepsTheItemCopied() async {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CommandPanelStateTests.noAccessibility"))
        let directPaste = DirectPasteService.isolated(pasteboard: pasteboard, ownProcessIdentifier: 7,
            targetProvider: { DirectPasteTestTarget(processIdentifier: 42) }, accessibilityTrusted: { false })
        let actionRunner = ActionRunner.isolated(diagnostics: diagnostics, directPasteService: directPaste)
        let pasteboardClient = TestClipboardPasteboard()
        let clipboard = ClipboardHistoryState(pasteboard: pasteboardClient, persistence: nil, configuration: config.current.clipboard)
        let state = makeState(diagnostics: diagnostics, config: config, clipboard: clipboard, actionRunner: actionRunner)
        let shell = RecordingShellPort()
        state.shell = shell

        let item = ClipboardHistoryItem(payload: .text("hello"))
        pasteboardClient.snapshotValue = PasteboardSnapshot(types: [.string], payload: item.payload, sourceBundleIdentifier: "com.example")
        pasteboardClient.changeCountValue += 1
        clipboard.captureIfChanged()
        clipboard.select(id: item.id)
        directPaste.captureTarget()

        XCTAssertFalse(state.directPasteSelectedClipboardItem(), "the panel stays open to ask")
        XCTAssertFalse(directPaste.hasPendingPaste)
        XCTAssertEqual(pasteboardClient.writtenPayloads.last, .text("hello"))
        for _ in 0..<50 where state.pendingPrompt == nil { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(state.pendingPrompt.map { String(localized: $0.spec.confirmLabel) }, "Allow")
        state.pendingPrompt?.resume(PanelPromptResult(confirmed: true))
        for _ in 0..<50 where shell.requestedPermissions.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(shell.requestedPermissions, [.accessibility])
        state.shutdown()
    }

    func testCommandReturnCopiesClipboardSelectionWithoutPendingPaste() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("CommandPanelStateTests.plainReturn"))
        let directPaste = DirectPasteService.isolated(pasteboard: pasteboard, ownProcessIdentifier: 7) { DirectPasteTestTarget(processIdentifier: 42) }
        let actionRunner = ActionRunner.isolated(diagnostics: diagnostics, directPasteService: directPaste)
        let pasteboardClient = TestClipboardPasteboard()
        let clipboard = ClipboardHistoryState(pasteboard: pasteboardClient, persistence: nil, configuration: config.current.clipboard)
        let state = makeState(diagnostics: diagnostics, config: config, clipboard: clipboard, actionRunner: actionRunner)

        let item = ClipboardHistoryItem(payload: .text("hello"))
        pasteboardClient.snapshotValue = PasteboardSnapshot(types: [.string], payload: item.payload, sourceBundleIdentifier: "com.example")
        pasteboardClient.changeCountValue += 1
        clipboard.captureIfChanged()
        clipboard.select(id: item.id)

        state.mode = .clipboardHistory
        XCTAssertTrue(state.performModeShortcut(ActionShortcut(key: "\r", modifiers: [.command])) {})
        XCTAssertFalse(directPaste.hasPendingPaste)
        XCTAssertEqual(pasteboardClient.writtenPayloads.last, .text("hello"))
        state.shutdown()
    }

    func testReopenRestoresContextWithinPopToRootTimeout() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        var clock = Date(timeIntervalSince1970: 1000)
        state.now = { clock }

        state.resetForOpen()
        let result = CommandResult(
            id: "test.result",
            title: "Test",
            subtitle: nil,
            icon: CommandIcon(fallback: "T"),
            payload: .command,
            primaryAction: CommandAction(id: "test.open", title: "Open", behavior: OpenSettingsAction()),
            secondaryActions: []
        )
        state.session.query = "tes"
        state.session.results = [result]
        state.session.selectedResultID = result.id
        state.mode = .translator
        state.panelWillClose()

        clock += 30
        state.resetForOpen()

        XCTAssertEqual(state.mode, .translator)
        XCTAssertEqual(state.session.query, "tes")
        XCTAssertEqual(state.session.results.map(\.id), ["test.result"])
        XCTAssertEqual(state.session.selectedResultID, "test.result")
        state.shutdown()
    }

    func testTranslatorChordsWaitForAResultAndSwapWithOrWithoutShift() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let state = makeState(diagnostics: diagnostics, config: config, clipboard: ClipboardHistoryState(pasteboard: TestClipboardPasteboard(), persistence: nil))
        state.router.openTranslator(language: "french")
        XCTAssertFalse(state.performModeShortcut(ActionShortcut(key: "c", modifiers: [.shift, .command])) {})
        XCTAssertFalse(state.performModeShortcut(ActionShortcut(key: "\r", modifiers: [.command])) {})
        let before = state.translator.targetLanguage
        XCTAssertTrue(state.performModeShortcut(ActionShortcut(key: "s", modifiers: [.command])) {})
        XCTAssertNotEqual(state.translator.targetLanguage, before)
        state.shutdown()
    }

    func testWhatsNewShowsOnceForUpgradersOnly() throws {
        let diagnostics = DiagnosticsService()
        let fresh = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let freshState = makeState(diagnostics: diagnostics, config: fresh, clipboard: ClipboardHistoryState(pasteboard: TestClipboardPasteboard(), persistence: nil))
        XCTAssertFalse(freshState.showsWhatsNew)
        XCTAssertEqual(fresh.current.localState.whatsNewSeenVersion, WhatsNew.version, "fresh installs never see it later")
        freshState.shutdown()

        let url = temporaryURL()
        try JSONEncoder().encode(FoundryConfig()).write(to: url)
        let upgraded = ConfigService(diagnostics: diagnostics, url: url)
        let state = makeState(diagnostics: diagnostics, config: upgraded, clipboard: ClipboardHistoryState(pasteboard: TestClipboardPasteboard(), persistence: nil))
        XCTAssertTrue(state.showsWhatsNew)
        state.dismissWhatsNew()
        XCTAssertFalse(state.showsWhatsNew)
        upgraded.flush()
        state.shutdown()
        let reopened = makeState(diagnostics: diagnostics, config: ConfigService(diagnostics: diagnostics, url: url),
            clipboard: ClipboardHistoryState(pasteboard: TestClipboardPasteboard(), persistence: nil))
        XCTAssertFalse(reopened.showsWhatsNew)
        reopened.shutdown()
    }

    func testReopenResetsAfterPopToRootTimeout() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        var clock = Date(timeIntervalSince1970: 1000)
        state.now = { clock }

        state.resetForOpen()
        state.session.query = "tes"
        state.session.results = [CommandResult(id: "test.result", title: "Test", subtitle: nil, icon: CommandIcon(fallback: "T"), payload: .command, primaryAction: CommandAction(id: "test.open", title: "Open", behavior: OpenSettingsAction()), secondaryActions: [])]
        state.mode = .translator
        state.panelWillClose()

        clock += 120
        state.resetForOpen()

        XCTAssertEqual(state.mode, .search)
        XCTAssertTrue(state.session.query.isEmpty)
        XCTAssertTrue(state.session.results.isEmpty)
        XCTAssertNil(state.session.selectedResultID)
        state.shutdown()
    }

    func testCompactCollapsedOnlyInSearchModeWithEmptyQuery() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics, config: config)

        XCTAssertFalse(state.compactCollapsed)
        state.settings.setWindowMode(.compact)
        XCTAssertTrue(state.compactCollapsed)

        state.session.query = "saf"
        XCTAssertFalse(state.compactCollapsed)

        state.session.query = ""
        state.session.isShowingActions = true
        XCTAssertFalse(state.compactCollapsed)

        state.session.isShowingActions = false
        state.mode = .translator
        XCTAssertFalse(state.compactCollapsed)
        state.shutdown()
    }

    func testHomeSuggestionColdStartRules() {
        let running: Set<String> = ["com.apple.Safari"]

        XCTAssertTrue(HomeSuggestionRules.isSuggestible(payload: .app(identity: "com.apple.Safari"), runningBundleIDs: running, hasUsage: false))
        XCTAssertTrue(HomeSuggestionRules.isSuggestible(payload: .app(identity: "com.apple.Terminal"), runningBundleIDs: [], hasUsage: true))
        XCTAssertFalse(HomeSuggestionRules.isSuggestible(payload: .app(identity: "com.apple.Terminal"), runningBundleIDs: running, hasUsage: false))
        XCTAssertFalse(HomeSuggestionRules.isSuggestible(payload: .app(identity: "com.apple.BluetoothFileExchange"), runningBundleIDs: ["com.apple.BluetoothFileExchange"], hasUsage: true))
        XCTAssertFalse(HomeSuggestionRules.isSuggestible(payload: .command, runningBundleIDs: running, hasUsage: true))
    }

    func testActionFilterIsIndependentOfQueryAndEscapeRestoresTheList() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        let result = CommandResult(
            id: "test.file",
            title: "Report",
            subtitle: nil,
            icon: CommandIcon(fallback: "F"),
            payload: .command,
            primaryAction: CommandAction(id: "open", title: "Open", behavior: LogAction("open")),
            secondaryActions: [
                CommandAction(id: "copy-file", title: "Copy File", behavior: CopyFileAction(path: "/tmp/report")),
                CommandAction(id: "copy", title: "Copy Path", behavior: CopyToClipboardAction("/tmp/report"))
            ]
        )
        state.session.results = [result]
        state.session.selectedResultID = result.id

        state.session.toggleActions()
        state.session.actionFilter = "copy pa"
        XCTAssertEqual(state.session.visibleActions.map(\.id), ["copy"])
        XCTAssertEqual(state.session.selectedActionID, "copy")
        XCTAssertEqual(state.session.query, "")

        state.session.actionFilter = "zzz"
        XCTAssertTrue(state.session.visibleActions.isEmpty)
        XCTAssertNil(state.session.selectedActionID)

        XCTAssertTrue(state.handleEscape())
        XCTAssertTrue(state.session.isShowingActions, "first escape clears the filter")
        XCTAssertEqual(state.session.visibleActions.count, state.session.selectedActions.count)
        XCTAssertTrue(state.handleEscape())
        XCTAssertFalse(state.session.isShowingActions)
        XCTAssertEqual(state.session.results.map(\.id), [result.id], "escape keeps the result list")
        XCTAssertEqual(state.session.selectedResultID, result.id)
        state.shutdown()
    }

    func testActionShortcutsAreAssignedOnceAndFireWithoutOpeningActions() async throws {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        let result = CommandResult(
            id: "test.shortcuts",
            title: "Report",
            subtitle: nil,
            icon: CommandIcon(fallback: "F"),
            payload: .command,
            primaryAction: CommandAction(id: "open", title: "Open", behavior: LogAction("open")),
            secondaryActions: [
                CommandAction(id: "copy", title: "Copy", behavior: CopyToClipboardAction("a")),
                CommandAction(id: "copy2", title: "Copy Path", behavior: CopyToClipboardAction("b")),
                CommandAction(id: "delete", title: "Delete Snippet", behavior: DeleteSnippetAction(id: "x"))
            ]
        )
        state.session.results = [result]
        state.session.selectedResultID = result.id

        let shortcuts = state.session.actionShortcuts
        XCTAssertNil(shortcuts["open"])
        XCTAssertEqual(shortcuts["copy"], .secondary)
        XCTAssertEqual(shortcuts["copy2"]?.display, "⇧⌘C")
        XCTAssertEqual(shortcuts["delete"]?.display, "⌃X")
        XCTAssertEqual(shortcuts["favorite.toggle.\(result.id)"]?.display, "⌘D")
        XCTAssertEqual(Set(shortcuts.values).count, shortcuts.count, "no chord is bound twice")

        XCTAssertFalse(state.performActionShortcut(ActionShortcut(key: "j", modifiers: [.command])) {})
        XCTAssertTrue(state.performActionShortcut(ActionShortcut(key: "d", modifiers: [.command])) {})
        XCTAssertFalse(state.session.isShowingActions)
        for _ in 0..<100 where state.settings.commandPreferences[result.id]?.favoriteRank == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(state.settings.commandPreferences[result.id]?.favoriteRank)
        state.shutdown()
    }

    func testNumberChordsPickADropChoiceInsteadOfAFavorite() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        state.handleDroppedFiles([FileManager.default.temporaryDirectory.appendingPathComponent("dropped-\(UUID()).txt")])

        XCTAssertFalse(state.performModeShortcut(ActionShortcut(key: "9", modifiers: [.command])) {})
        XCTAssertFalse(state.performModeShortcut(ActionShortcut(key: "\u{7f}", modifiers: [.command])) {})
        XCTAssertTrue(state.performModeShortcut(ActionShortcut(key: "1", modifiers: [.command])) {})

        XCTAssertNil(state.pendingDropURLs)
        XCTAssertEqual(state.fileShelf.files.count, 1)
        state.shutdown()
    }

    func testDeveloperToolsNumberChordsSwitchTools() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        state.mode = .developerTools
        XCTAssertTrue(state.performModeShortcut(ActionShortcut(key: "3", modifiers: [.command])) {})
        XCTAssertEqual(state.developerTools.selectedTool, DeveloperToolsState.Tool.allCases[2])
        XCTAssertFalse(state.performModeShortcut(ActionShortcut(key: "9", modifiers: [.command])) {})
        state.shutdown()
    }

    func testCommandYRequestsQuickLookForFileResultsOnly() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        var lookedAt: [URL] = []
        let shell = RecordingShellPort()
        shell.onQuickLook = { lookedAt.append($0) }
        state.shell = shell
        state.session.results = [
            CommandResult(id: "file./tmp/report.pdf", title: "report.pdf", subtitle: nil, icon: CommandIcon(fallback: "F"), payload: .file(URL(fileURLWithPath: "/tmp/report.pdf")), primaryAction: CommandAction(id: "open", title: "Open", behavior: LogAction("open")), secondaryActions: []),
            CommandResult(id: "app.safari", title: "Safari", subtitle: nil, icon: CommandIcon(fallback: "S"), payload: .command, primaryAction: CommandAction(id: "open", title: "Open", behavior: LogAction("open")), secondaryActions: []),
        ]
        state.session.selectedResultID = "app.safari"
        XCTAssertFalse(state.performModeShortcut(ActionShortcut(key: "y", modifiers: [.command])) {})
        XCTAssertTrue(lookedAt.isEmpty)
        state.session.selectedResultID = "file./tmp/report.pdf"
        XCTAssertTrue(state.performModeShortcut(ActionShortcut(key: "y", modifiers: [.command])) {})
        XCTAssertEqual(lookedAt, [URL(fileURLWithPath: "/tmp/report.pdf")])
        state.shutdown()
    }

    func testFavoriteActionTogglesAndResolvesFavoriteResults() async throws {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let registry = CommandRegistry(
            providers: [FavoriteStubProvider()],
            usageRanking: UsageRankingStore.scratch(diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        let state = CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        let result = CommandResult(
            id: "test.favorite",
            title: "Favorite Me",
            subtitle: nil,
            icon: CommandIcon(fallback: "F"),
            payload: .command,
            primaryAction: CommandAction(id: "test.favorite.open", title: "Open", behavior: LogAction("fav")),
            secondaryActions: []
        )
        state.session.results = [result]
        state.session.selectedResultID = result.id

        let addAction = state.session.selectedActions.first { action in
            if action.behavior is ToggleFavoriteAction { return true }
            return false
        }
        XCTAssertEqual(addAction?.title, "Add to Favorites")

        state.settings.toggleFavorite(commandID: result.id)
        XCTAssertTrue(state.settings.commandPreferences[result.id]?.favoriteRank != nil)
        XCTAssertEqual(state.session.selectedActions.first { $0.id == addAction?.id }?.title, "Remove from Favorites")

        for _ in 0..<100 where state.session.favoriteResults.isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(state.session.favoriteResults.map(\.id), [result.id])

        state.settings.toggleFavorite(commandID: result.id)
        for _ in 0..<100 where state.session.favoriteResults.isEmpty == false {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(state.session.favoriteResults.isEmpty)
        state.shutdown()
    }

    private func makeState(diagnostics: DiagnosticsService, config: ConfigService, clipboard: ClipboardHistoryState, actionRunner: ActionRunner? = nil) -> CommandPanelState {
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        return CommandPanelState.isolated(registry: registry, actionRunner: actionRunner ?? ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics, config: config, clipboardHistory: clipboard)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("foundry-panel-\(UUID().uuidString).json")
    }

    func testDecliningAConfirmedProcessDoesNotRunIt() async {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let clipboard = ClipboardHistoryState(pasteboard: TestClipboardPasteboard(), persistence: nil, configuration: config.current.clipboard)
        let state = makeState(diagnostics: diagnostics, config: config, clipboard: clipboard)
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-confirm-\(UUID().uuidString)")
        let behavior = RunProcessAction(path: "/usr/bin/touch", arguments: [marker.path], confirmation: .init(title: "Restart this Mac?", label: "Restart"))

        let run = Task { await state.execute(CommandAction(id: "test.confirm", title: "Restart", behavior: behavior), commandID: "test") }
        for _ in 0..<100 where state.pendingPrompt == nil { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(state.pendingPrompt)
        state.resolvePrompt(.cancelled)
        _ = await run.value

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        state.shutdown()
    }

    func testASecondPromptCancelsTheFirstInsteadOfLeavingItWaiting() async {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: temporaryURL())
        let clipboard = ClipboardHistoryState(pasteboard: TestClipboardPasteboard(), persistence: nil, configuration: config.current.clipboard)
        let state = makeState(diagnostics: diagnostics, config: config, clipboard: clipboard)
        let spec = PanelPromptSpec(title: "First", message: nil, confirmLabel: "OK", cancelLabel: "Cancel")

        let first = Task { await state.requestPrompt(spec) }
        for _ in 0..<50 where state.pendingPrompt == nil { try? await Task.sleep(for: .milliseconds(10)) }
        let second = Task { await state.requestPrompt(spec) }
        let firstResult = await first.value
        state.resolvePrompt(PanelPromptResult(confirmed: true))

        XCTAssertFalse(firstResult.confirmed)
        let secondConfirmed = await second.value.confirmed
        XCTAssertTrue(secondConfirmed)
        state.shutdown()
    }

    func testSearchLoadingStaysActiveUntilTheLatestSearchCompletes() async throws {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(
            diagnostics: diagnostics,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-panel-loading-\(UUID().uuidString).json")
        )
        let registry = CommandRegistry(
            providers: [SlowSearchProvider()],
            usageRanking: UsageRankingStore.scratch(diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        let state = CommandPanelState.isolated(
            registry: registry,
            actionRunner: ActionRunner.isolated(diagnostics: diagnostics),
            diagnostics: diagnostics,
            config: config
        )

        state.session.query = "slow"
        try await Task.sleep(for: .milliseconds(15))
        XCTAssertTrue(state.session.isSearchLoading)

        for _ in 0..<30 where state.session.isSearchLoading {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(state.session.isSearchLoading)
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

final class TestClipboardPasteboard: PasteboardClient, Sendable {
    private struct Box {
        var changeCountValue = 0
        var snapshotValue: PasteboardSnapshot?
        var writtenPayloads: [ClipboardPayload] = []
    }

    private let box = OSAllocatedUnfairLock(uncheckedState: Box())

    var changeCountValue: Int {
        get { box.withLockUnchecked { $0.changeCountValue } }
        set { box.withLockUnchecked { $0.changeCountValue = newValue } }
    }

    var snapshotValue: PasteboardSnapshot? {
        get { box.withLockUnchecked { $0.snapshotValue } }
        set { box.withLockUnchecked { $0.snapshotValue = newValue } }
    }

    var writtenPayloads: [ClipboardPayload] {
        box.withLockUnchecked { $0.writtenPayloads }
    }

    var changeCount: Int { changeCountValue }
    func snapshot() -> PasteboardSnapshot? { snapshotValue }
    func write(_ payload: ClipboardPayload) { box.withLockUnchecked { $0.writtenPayloads.append(payload) } }
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
            payload: .command,
            primaryAction: CommandAction(id: "test.kill-port.perform", title: "Run", behavior: LogAction("collision")),
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
            payload: .command,
            primaryAction: CommandAction(id: "test.favorite.open", title: "Open", behavior: LogAction("fav")),
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
