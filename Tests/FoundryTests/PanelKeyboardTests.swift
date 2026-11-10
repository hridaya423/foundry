import AppKit
import XCTest
@testable import Foundry
import FoundryDomain
import FoundryServices

@MainActor
final class PanelKeyboardTests: XCTestCase {

    private struct HomeProvider: CommandProvider {
        let id = "test.home"
        let home: [CommandResult]
        func search(_ request: CommandSearchRequest) async throws -> [CommandResult] { [] }
        func defaultResults() async throws -> [CommandResult] { home }
    }

    private func result(
        _ id: String,
        title: String = "Result",
        payload: ResultPayload = .command,
        primary: any ResultAction = OpenHomeAction()
    ) -> CommandResult {
        CommandResult(
            id: id,
            title: title,
            subtitle: nil,
            icon: CommandIcon(fallback: "T"),
            payload: payload,
            primaryAction: CommandAction(id: id + ".primary", title: "Open", behavior: primary),
            secondaryActions: []
        )
    }

    private func appResult(_ id: String, title: String) -> CommandResult {
        CommandResult(
            id: id,
            title: title,
            subtitle: nil,
            icon: CommandIcon(fallback: "A"),
            payload: .app(identity: id),
            primaryAction: CommandAction(id: id + ".open", title: "Open", behavior: OpenAppAction(path: "/Applications/\(title).app", name: title)),
            secondaryActions: []
        )
    }

    private func makeState(providers: [any CommandProvider] = []) -> CommandPanelState {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(
            diagnostics: diagnostics,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-kbd-\(UUID().uuidString).json")
        )
        let registry = CommandRegistry(
            providers: providers,
            usageRanking: UsageRankingStore.scratch(diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        return CommandPanelState.isolated(
            registry: registry,
            actionRunner: ActionRunner.isolated(diagnostics: diagnostics),
            diagnostics: diagnostics,
            config: config,
            snippetStore: FileSnippetStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-kbd-snippets-\(UUID().uuidString).json"))
        )
    }

    // MARK: Escape ordering — Raycast semantics

    func testEscapeClearsQueryBeforeClosing() {
        let state = makeState()
        state.mode = .search
        state.session.query = "saf"

        XCTAssertTrue(state.handleEscape(), "first Esc should clear the query, not close")
        XCTAssertEqual(state.session.query, "")
        XCTAssertFalse(state.handleEscape(), "second Esc with an empty query closes the panel")
        state.shutdown()
    }

    func testEscapeClearsFeatureFilterBeforeGoingHome() {
        let state = makeState()
        state.mode = .clipboardHistory
        state.clipboardHistory.query = "a"
        XCTAssertTrue(state.handleEscape())
        XCTAssertEqual(state.mode, .clipboardHistory)
        XCTAssertEqual(state.clipboardHistory.query, "")
        XCTAssertTrue(state.handleEscape())
        XCTAssertEqual(state.mode, .search)
        state.shutdown()
    }

    private func listState(count: Int) -> CommandPanelState {
        let state = makeState()
        state.session.query = "x"
        state.session.results = (0..<count).map { result("test.r\($0)") }
        state.session.selectedResultID = "test.r0"
        return state
    }

    func testShelfCommandASelectsAllAndSpaceIsQuickLook() {
        let state = makeState()
        state.fileShelf.add(urls: [URL(fileURLWithPath: #filePath), URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")])
        state.mode = .fileShelf
        state.fileShelf.select(id: state.fileShelf.files[0].id)
        XCTAssertTrue(state.spaceTogglesQuickLook())
        XCTAssertTrue(state.performModeShortcut(ActionShortcut(key: "a", modifiers: [.command]), dismiss: {}))
        XCTAssertEqual(state.fileShelf.selectedFiles.count, 2)
    }

    func testMediaActionsFollowTheSelectedDownload() {
        let state = makeState()
        state.mode = .mediaDownloads
        XCTAssertEqual(state.featureActions(dismiss: {})?.actions.map(\.id), ["feature.open-folder", "feature.change-folder"])
        let failed = UUID()
        state.mediaDownloads.start(id: failed, sourceURL: "https://example.com/b.mp4")
        state.mediaDownloads.fail(id: failed, message: "nope")
        state.moveSelectionDown()
        let ids = state.featureActions(dismiss: {})?.actions.map(\.id) ?? []
        XCTAssertEqual(ids.first, "feature.retry")
        XCTAssertEqual(ids.last, "feature.remove")
        XCTAssertTrue(state.performModeShortcut(ActionShortcut(key: "\u{7f}", modifiers: [.command]), dismiss: {}))
        XCTAssertTrue(state.mediaDownloads.items.isEmpty)
    }

    func testControlNAndPMoveSelection() {
        let state = listState(count: 3)
        XCTAssertTrue(state.performModeShortcut(ActionShortcut(key: "n", modifiers: [.control]), dismiss: {}))
        XCTAssertEqual(state.session.selectedResultID, "test.r1")
        XCTAssertTrue(state.performModeShortcut(ActionShortcut(key: "p", modifiers: [.control]), dismiss: {}))
        XCTAssertEqual(state.session.selectedResultID, "test.r0")
        state.shutdown()
    }

    func testCommandArrowsJumpToEndsAndPagesMoveSeven() {
        let state = listState(count: 20)
        state.moveSelection(.last)
        XCTAssertEqual(state.session.selectedResultID, "test.r19")
        state.moveSelection(.first)
        XCTAssertEqual(state.session.selectedResultID, "test.r0")
        state.moveSelection(.pageDown)
        XCTAssertEqual(state.session.selectedResultID, "test.r7")
        state.moveSelection(.pageUp)
        XCTAssertEqual(state.session.selectedResultID, "test.r0")
        state.shutdown()
    }

    func testCommandDigitOpensFavorite() {
        let state = makeState()
        let favorites = (0..<3).map { result("test.fav\($0)") }
        state.session.favoriteResults = favorites
        XCTAssertTrue(state.performModeShortcut(ActionShortcut(key: "3", modifiers: [.command]), dismiss: {}))
        XCTAssertEqual(state.session.selectedResultID, "test.fav2")
        XCTAssertFalse(state.performModeShortcut(ActionShortcut(key: "4", modifiers: [.command]), dismiss: {}))
        state.session.query = "x"
        XCTAssertFalse(state.performModeShortcut(ActionShortcut(key: "1", modifiers: [.command]), dismiss: {}))
        state.shutdown()
    }

    func testSelectionChangeAnnounces() {
        let state = listState(count: 3)
        var heard: [String] = []
        state.session.announce = { heard.append($0) }
        state.moveSelectionDown()
        XCTAssertEqual(heard, ["Result, 2 of 3"])
        state.shutdown()
    }

    func testCommandKOpensActionsInClipboardMode() {
        let pasteboard = TestClipboardPasteboard()
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-kbd-\(UUID().uuidString).json"))
        let clipboard = ClipboardHistoryState(pasteboard: pasteboard, persistence: nil, configuration: config.current.clipboard)
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics,
            configService: config)
        let state = CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics,
            config: config, clipboardHistory: clipboard)
        let item = ClipboardHistoryItem(payload: .text("https://foundry.app"))
        pasteboard.snapshotValue = PasteboardSnapshot(types: [.string], payload: item.payload, sourceBundleIdentifier: "com.example")
        pasteboard.changeCountValue += 1
        clipboard.captureIfChanged()
        clipboard.select(id: clipboard.visibleItems[0].id)
        state.mode = .clipboardHistory

        state.toggleActions {}
        XCTAssertTrue(state.session.isShowingActions)
        XCTAssertEqual(state.session.selectedActions.map(\.title),
            ["Paste", "Copy", "Open Link", "Pin", "Remove", "Clear History…"])
        XCTAssertEqual(state.session.actionShortcuts["feature.copy"]?.display, "⌘↵")
        XCTAssertEqual(state.session.actionShortcuts["feature.clear"]?.display, "⇧⌘⌫")

        state.moveSelectionDown()
        XCTAssertEqual(state.session.selectedActionID, "feature.copy")
        XCTAssertEqual(clipboard.selectedItem?.id, clipboard.visibleItems[0].id, "arrows move the action list, not the history")

        XCTAssertTrue(state.handleEscape())
        XCTAssertFalse(state.session.isShowingActions)
        XCTAssertNil(state.session.featureActions)
        XCTAssertEqual(state.mode, .clipboardHistory)
        state.shutdown()
    }

    func testCopyingAClipboardItemConfirmsAfterThePanelCloses() {
        let pasteboard = TestClipboardPasteboard()
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-kbd-\(UUID().uuidString).json"))
        let clipboard = ClipboardHistoryState(pasteboard: pasteboard, persistence: nil, configuration: config.current.clipboard)
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics,
            configService: config)
        let state = CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics,
            config: config, clipboardHistory: clipboard)
        let shell = RecordingShellPort()
        var notices: [ActionFeedback] = []
        shell.onTransientNotice = { notices.append($0) }
        state.shell = shell
        pasteboard.snapshotValue = PasteboardSnapshot(types: [.string], payload: .text("ship it\nsecond line"), sourceBundleIdentifier: nil)
        pasteboard.changeCountValue += 1
        clipboard.captureIfChanged()
        clipboard.select(id: clipboard.visibleItems[0].id)
        state.mode = .clipboardHistory
        var dismissed = false

        XCTAssertTrue(state.performModeShortcut(ActionShortcut(key: "\r", modifiers: [.command]), dismiss: { dismissed = true }))

        XCTAssertTrue(dismissed)
        XCTAssertEqual(notices, [.success("Copied ship it")])
        state.shutdown()
    }

    func testSnippetActionsListInsertFirstAndDeleteLast() {
        let state = makeState()
        state.snippets.newSnippet()
        state.mode = .snippets
        state.toggleActions {}
        let titles = state.session.selectedActions.map(\.title)
        XCTAssertEqual(titles.first, "Insert")
        XCTAssertEqual(titles.last, "Delete…")
        XCTAssertTrue(titles.contains("Duplicate"))
        let before = state.snippets.items.count
        XCTAssertTrue(state.performModeShortcut(ActionShortcut(key: "d", modifiers: [.command]), dismiss: {}))
        XCTAssertEqual(state.snippets.items.count, before + 1)
        state.shutdown()
    }

    func testCommandNCreatesASnippetReadyForItsTitle() {
        let state = makeState()
        state.mode = .snippets

        XCTAssertTrue(state.performModeShortcut(ActionShortcut(key: "n", modifiers: [.command]), dismiss: {}))

        XCTAssertEqual(state.snippets.items.count, 1)
        XCTAssertEqual(state.snippets.freshSnippetID, state.snippets.selectedID)
        state.shutdown()
    }

    func testDroppingOnTheShelfShelvesAndTheChooserFollowsArrowsAndReturn() throws {
        let state = makeState()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("drop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = dir.appendingPathComponent("a.txt"), second = dir.appendingPathComponent("b.txt")
        try Data("a".utf8).write(to: first)
        try Data("b".utf8).write(to: second)

        state.mode = .fileShelf
        state.handleDroppedFiles([first])
        XCTAssertNil(state.pendingDropURLs, "the shelf takes its own drops without asking")
        XCTAssertEqual(state.fileShelf.files.map(\.url), [first])

        state.handleDroppedFiles([URL(string: "https://foundry.app")!])
        XCTAssertEqual(state.actionFeedback, .failure("Only files can go on the shelf. Drop them from Finder."))

        state.showHome()
        state.handleDroppedFiles([second])
        XCTAssertEqual(state.dropSelection, 0)
        state.moveSelectionDown()
        XCTAssertEqual(state.dropChoices[state.dropSelection], .convert)
        XCTAssertTrue(state.resolveSelectedDrop())
        XCTAssertNil(state.pendingDropURLs)
        XCTAssertEqual(state.mode, .fileConversion)
        state.shutdown()
    }

    func testShelfHeaderCountsFilesAndSelection() {
        XCTAssertEqual(FileShelfView.headerTitle(selected: 0, total: 1), "1 File")
        XCTAssertEqual(FileShelfView.headerTitle(selected: 0, total: 3), "3 Files")
        XCTAssertEqual(FileShelfView.headerTitle(selected: 2, total: 3), "2 of 3 Selected")
    }

    func testDeveloperToolsPrimaryOutputIsTheFirstRow() {
        let state = makeState()
        state.developerTools.selectedTool = .base
        state.developerTools.baseInput = "255"
        XCTAssertEqual(state.developerTools.primaryOutput, state.developerTools.baseRows.first?.value)
        state.developerTools.baseInput = ""
        XCTAssertNil(state.developerTools.primaryOutput)
        state.shutdown()
    }

    func testEscapeClosesSnippetArgumentPromptFirst() {
        let state = makeState()
        state.mode = .snippets
        state.pendingSnippetArguments = SnippetArgumentRequest(names: ["name"], copyOnly: false)
        XCTAssertTrue(state.handleEscape())
        XCTAssertNil(state.pendingSnippetArguments)
        XCTAssertEqual(state.mode, .snippets)
        state.shutdown()
    }

    func testEscapeClearsQuickAIComposerBeforeLeaving() {
        let state = makeState()
        state.mode = .quickAI
        state.quickAI.quickAIQuery = "draft"
        XCTAssertTrue(state.handleEscape())
        XCTAssertEqual(state.quickAI.quickAIQuery, "")
        XCTAssertEqual(state.mode, .quickAI)
        XCTAssertTrue(state.handleEscape())
        XCTAssertEqual(state.mode, .search)
        state.shutdown()
    }

    // MARK: What you see is what you navigate

    func testNavigableRowsMatchWhatTheViewRendersAtHome() {
        let state = makeState()
        // Non-suggestible app rows are filtered out of Home's Recent strip by
        // the view; navigation must not land on them.
        let hiddenApp = appResult("app.hidden", title: "HiddenApp")
        let command = result("test.command", title: "Some Command")
        state.session.results = [hiddenApp, command]

        let navigableIDs = state.session.navigableResults.map(\.id)
        XCTAssertFalse(navigableIDs.contains("app.hidden"), "non-suggestible app should not be navigable")
        XCTAssertTrue(navigableIDs.contains("test.command"))

        state.session.selectedResultID = nil
        state.moveSelectionDown()
        XCTAssertEqual(state.session.selectedResultID, "test.command")
        state.shutdown()
    }

    func testCalculatorFallbackRowsAreReachableByKeyboard() {
        let state = makeState()
        let calc = result("calculator.expr", title: "42", payload: .calculation(expression: "6*7", value: "42"), primary: CopyToClipboardAction("42"))
        state.session.results = [calc]
        state.session.query = "6*7"
        state.session.selectedResultID = calc.id

        let navigableIDs = state.session.navigableResults.map(\.id)
        for fallback in PanelSession.calculatorFallbackResults {
            XCTAssertTrue(navigableIDs.contains(fallback.id), "fallback \(fallback.id) must be keyboard-reachable")
        }
        state.shutdown()
    }

    func testFileShelfRowIsNotNavigableWhenShelfHoldsFiles() {
        let state = makeState()
        state.session.results = [
            result("foundry.file-shelf", title: "File Shelf"),
            result("test.command", title: "Some Command")
        ]
        state.fileShelf.add(urls: [URL(fileURLWithPath: "/tmp/x.txt")])
        state.session.query = ""

        XCTAssertFalse(state.session.navigableResults.map(\.id).contains("foundry.file-shelf"))
        state.shutdown()
    }

    // MARK: Quick Look — Space, ⌘Y, Esc ordering

    private func fileResult(_ id: String = "file./tmp/doc.pdf") -> CommandResult {
        result(id, title: "doc.pdf", payload: .file(URL(fileURLWithPath: "/tmp/doc.pdf")),
               primary: OpenFileWithAppAction(path: "/tmp/doc.pdf", appPath: ""))
    }

    func testSpaceTogglesQuickLookForSelectedFile() {
        let state = makeState()
        let shell = RecordingShellPort()
        var previewed: URL?
        shell.onQuickLook = { previewed = $0 }
        state.shell = shell
        state.mode = .search
        let file = fileResult()
        state.session.results = [file]
        state.session.selectedResultID = file.id

        XCTAssertTrue(state.spaceTogglesQuickLook())
        XCTAssertEqual(previewed, URL(fileURLWithPath: "/tmp/doc.pdf"))
        state.shutdown()
    }

    func testSpaceTypesNormallyWithoutAFileSelection() {
        let state = makeState()
        let shell = RecordingShellPort()
        state.shell = shell
        state.mode = .search
        let command = result("test.command", title: "Some Command")
        state.session.results = [command]
        state.session.selectedResultID = command.id

        XCTAssertFalse(state.spaceTogglesQuickLook())
        state.shutdown()
    }

    func testEscapeClosesQuickLookBeforeThePanel() {
        let state = makeState()
        let shell = RecordingShellPort()
        var closes = 0
        shell.quickLookShowing = true
        shell.onCloseQuickLook = { closes += 1 }
        state.shell = shell
        state.mode = .search
        state.session.query = "doc"

        XCTAssertTrue(state.handleEscape())
        XCTAssertEqual(closes, 1)
        XCTAssertEqual(state.session.query, "doc", "Esc closed the preview, not the query")
        state.shutdown()
    }

    func testSelectionChangeFollowsThroughToQuickLook() {
        let state = makeState()
        let shell = RecordingShellPort()
        var follows = 0
        shell.onQuickLookFollowSelection = { follows += 1 }
        state.shell = shell
        state.session.results = [fileResult("file./tmp/a.txt"), fileResult("file./tmp/b.txt")]

        state.session.selectedResultID = nil
        state.moveSelectionDown()
        XCTAssertEqual(follows, 1)
        state.shutdown()
    }

    // MARK: Meta actions only on durable results

    func testMetaActionsHiddenForEphemeralResults() {
        let state = makeState()
        let file = result("file./tmp/doc.pdf", title: "doc.pdf", payload: .file(URL(fileURLWithPath: "/tmp/doc.pdf")), primary: OpenFileWithAppAction(path: "/tmp/doc.pdf", appPath: ""))
        state.session.results = [file]
        state.session.query = "doc"
        state.session.selectedResultID = file.id

        let behaviors = state.session.selectedActions.map(\.behavior)
        XCTAssertFalse(behaviors.contains { $0 is ToggleFavoriteAction })
        XCTAssertFalse(behaviors.contains { $0 is OpenCommandSettingsAction })
        XCTAssertFalse(behaviors.contains { $0 is ResetRankingAction })
        state.shutdown()
    }

    func testMetaActionsPresentForCommands() {
        let state = makeState()
        let command = result("test.command", title: "Some Command")
        state.session.results = [command]
        state.session.query = "some"
        state.session.selectedResultID = command.id

        let behaviors = state.session.selectedActions.map(\.behavior)
        XCTAssertTrue(behaviors.contains { $0 is ToggleFavoriteAction })
        XCTAssertTrue(behaviors.contains { $0 is OpenCommandSettingsAction })
        state.shutdown()
    }

    // MARK: Footer truth

    func testPreferredActionTitleReflectsRealAction() {
        let state = makeState()
        let copy = CommandResult(
            id: "test.copy",
            title: "Random Number",
            subtitle: nil,
            icon: CommandIcon(fallback: "T"),
            payload: .command,
            primaryAction: CommandAction(id: "test.copy.primary", title: "Copy", behavior: CopyToClipboardAction("7")),
            secondaryActions: []
        )
        state.session.results = [copy]
        state.session.query = "rand"
        state.session.selectedResultID = copy.id
        XCTAssertEqual(state.session.preferredActionTitle, "Copy", "the footer must name the action ↵ actually runs")
        state.shutdown()
    }

    func testHomeOpensWithTheFirstVisibleRowSelected() async {
        // A non-suggestible app loads first but Home doesn't paint it; the
        // opening selection must land on a row the user can see.
        let hiddenApp = appResult("app.hidden", title: "HiddenApp")
        let command = result("test.command", title: "Some Command")
        let state = makeState(providers: [HomeProvider(home: [hiddenApp, command])])
        state.session.refreshHomeResults()
        let filled = await waitUntilTrue { state.session.results.isEmpty == false }
        XCTAssertTrue(filled)
        XCTAssertEqual(state.session.selectedResultID, "test.command")
        state.shutdown()
    }

    private func footer(_ state: CommandPanelState) -> [String] {
        state.searchFooterActions(isWindowLayoutQuery: false).map { "\($0.keys) \(String(localized: $0.label))" }
    }

    func testArrowsInFeatureModesNeverMoveTheHiddenRootList() {
        let state = makeState()
        state.session.results = [result("test.one"), result("test.two")]
        state.session.selectedResultID = "test.one"
        for mode in [CommandPanelState.Mode.mediaDownloads, .developerTools, .quickAI, .agents] {
            state.mode = mode
            state.moveSelectionDown()
            XCTAssertEqual(state.session.selectedResultID, "test.one", "\(mode)")
        }
        state.mode = .search
        state.moveSelectionDown()
        XCTAssertEqual(state.session.selectedResultID, "test.two")
        state.shutdown()
    }

    func testActionsKeepTheRootQueryAndListDestructiveActionsLast() {
        let state = makeState()
        let file = CommandResult(id: "file.a", title: "Report.pdf", subtitle: nil, icon: CommandIcon(fallback: "F"),
            payload: .file(URL(fileURLWithPath: "/tmp/Report.pdf")),
            primaryAction: CommandAction(id: "file.open", title: "Open", behavior: OpenHomeAction()),
            secondaryActions: [
                CommandAction(id: "file.trash", title: "Move to Trash", behavior: MoveToTrashAction(path: "/tmp/Report.pdf")),
                CommandAction(id: "file.copy", title: "Copy Path", behavior: CopyToClipboardAction("/tmp/Report.pdf")),
            ])
        state.session.query = "rep"
        state.session.results = [file]
        state.session.selectedResultID = file.id
        state.session.toggleActions()
        XCTAssertEqual(state.session.query, "rep")
        let titles = state.session.selectedActions.map(\.title)
        XCTAssertEqual(titles.first, "Open")
        XCTAssertEqual(titles.last, "Move to Trash")
        state.shutdown()
    }

    func testFooterShowsNothingWhenNothingIsSelected() {
        let state = makeState()
        state.session.results = []
        state.session.selectedResultID = nil
        XCTAssertEqual(footer(state), [])
        state.shutdown()
    }

    func testFooterNamesTheSelectedResultsAction() {
        let state = makeState()
        state.session.results = [result("test.one")]
        state.session.selectedResultID = "test.one"
        XCTAssertEqual(footer(state), ["↵ Open", "⌘K Actions"])
        state.shutdown()
    }

    func testFooterShowsThePromptsVerbsWhileAPromptIsUp() {
        let state = makeState()
        state.session.results = [result("test.one")]
        state.session.selectedResultID = "test.one"
        state.pendingPrompt = PendingPrompt(
            spec: .confirmation(title: "Move to Trash?", confirmLabel: "Move to Trash", isDestructive: true),
            resume: { _ in })
        XCTAssertEqual(footer(state), ["↵ Move to Trash", "esc Cancel"])
        state.shutdown()
    }

    // MARK: Home never blanks

    func testReopenInsidePopToRootWindowKeepsTheQueryAndItsResults() async {
        let command = result("test.homecmd", title: "Home Command")
        let state = makeState(providers: [HomeProvider(home: [command])])
        state.resetForOpen()
        let filled = await waitUntilTrue { state.session.results.isEmpty == false }
        XCTAssertTrue(filled)
        state.session.query = "ho"
        state.session.results = [command]
        state.session.selectedResultID = command.id
        state.panelWillClose()

        state.resetForOpen()
        XCTAssertEqual(state.session.query, "ho")
        XCTAssertEqual(state.session.results.map(\.id), ["test.homecmd"])
        XCTAssertEqual(state.session.selectedResultID, "test.homecmd")
        state.shutdown()
    }

    func testNoResultsOffersNavigableFallbacks() async {
        let state = makeState()
        state.session.query = "zzzq"
        let filled = await waitUntilTrue { state.session.results.isEmpty == false }
        XCTAssertTrue(filled)
        XCTAssertTrue(state.session.navigableResults.contains { $0.title == "Ask AI about zzzq" })
        XCTAssertEqual(state.session.selectedResultID, state.session.navigableResults.first?.id)
        state.shutdown()
    }

    func testShiftTabDoesNothingInSearch() {
        var tabs = 0
        let coordinator = LauncherSearchField.Coordinator(text: .constant(""), onTab: { tabs += 1 })
        let field = NSTextField()
        let handled = coordinator.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertBacktab(_:)))
        XCTAssertTrue(handled)
        XCTAssertEqual(tabs, 0)
        _ = coordinator.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(tabs, 1)
    }

    func testHomeSnapshotFillsSynchronouslyOnReopen() async {
        let command = result("test.homecmd", title: "Home Command")
        let provider = HomeProvider(home: [command])
        let state = makeState(providers: [provider])
        state.session.refreshHomeResults()
        let filled = await waitUntilTrue { state.session.results.isEmpty == false }
        XCTAssertTrue(filled, "home must populate from providers")
        let snapshotCount = state.session.results.count

        // Simulate open→close→reopen where the query never changed.
        state.session.results = []
        state.session.refreshHomeResults()
        XCTAssertEqual(state.session.results.count, snapshotCount, "the cached snapshot must paint Home synchronously")
        state.shutdown()
    }

    private func waitUntilTrue(_ condition: @escaping () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(16))
        }
        return condition()
    }

    func testControlChordReachesActionShortcutsBeforeTheFieldEditor() throws {
        let panel = FoundryPanel(contentRect: .zero, styleMask: [.nonactivatingPanel], backing: .buffered, defer: true)
        var received: ActionShortcut?
        panel.onActionShortcut = { received = $0; return true }
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .control, timestamp: 0,
            windowNumber: 0, context: nil, characters: "\u{18}", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7))
        panel.sendEvent(event)
        XCTAssertEqual(received, ActionShortcut(key: "x", modifiers: [.control]))
    }

    private final class QueryRecorder: CommandProvider, @unchecked Sendable {
        let id = "test.recorder"
        private let lock = NSLock()
        private var seen: [String] = []
        var queries: [String] { lock.withLock { seen } }
        func search(_ request: CommandSearchRequest) async throws -> [CommandResult] {
            lock.withLock { seen.append(request.query) }
            return []
        }
    }

    func testFilePrefixAloneReachesSearchWithItsSpace() async {
        let recorder = QueryRecorder()
        let state = makeState(providers: [recorder])
        state.session.query = "f "
        let reached = await waitUntilTrue { recorder.queries.contains("f ") }
        XCTAssertTrue(reached, "bare `f ` lists recent files, so the prefix space must survive trimming: \(recorder.queries)")
        state.shutdown()
    }

    func testOpenAndCloseLeaveUnusedFeatureStatesUnbuilt() {
        let state = makeState()
        state.resetForOpen()
        state.panelWillClose()
        XCTAssertTrue(state.builtFeatures.isEmpty, "\(state.builtFeatures)")
        state.router.openTranslator()
        XCTAssertEqual(state.builtFeatures, [.translator])
        state.shutdown()
    }
}
