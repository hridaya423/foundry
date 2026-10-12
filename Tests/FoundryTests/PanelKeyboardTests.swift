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
            usageRanking: UsageRankingStore(diagnostics: diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        return CommandPanelState(
            registry: registry,
            actionRunner: ActionRunner(diagnostics: diagnostics),
            diagnostics: diagnostics,
            config: config
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

    func testEscapeInFeatureModeGoesHome() {
        let state = makeState()
        state.mode = .snippets
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

    // MARK: Home never blanks

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
}
