import XCTest
@testable import Foundry
import FoundryDomain
import FoundryServices

@MainActor
final class ActionRunnerTests: XCTestCase {
    func testExecutionReturnsTypedClipboardOutcomeAndFeedbackEvent() async {
        let runner = ActionRunner(diagnostics: DiagnosticsService())
        let request = CommandExecutionRequest(
            commandID: "test.copy",
            action: CommandAction(id: "test.copy.perform", title: "Copy", kind: .copyToClipboard("value"))
        )
        var events: [CommandExecutionEvent] = []

        let outcome = await runner.execute(request) { event in
            events.append(event)
        }

        XCTAssertEqual(outcome, .copied(content: "value"))
        XCTAssertTrue(events.contains { event in
            if case .feedback(.success("Copied to clipboard")) = event { return true }
            return false
        })
    }

    func testCopySnippetRendersAtExecutionUsingInjectedContext() async {
        let store = TestSnippetStore(snippets: [StoredSnippet(id: "one", title: "One", content: "{clipboard}")])
        let runner = ActionRunner(
            diagnostics: DiagnosticsService(),
            snippetStore: store,
            snippetContext: { SnippetRenderContext(now: Date(timeIntervalSince1970: 0), locale: Locale(identifier: "en_US_POSIX"), calendar: Calendar(identifier: .gregorian), clipboard: "later") }
        )
        let action = CommandAction(id: "copy", title: "Copy", kind: .copySnippet(id: "one"))

        let outcome = await runner.execute(CommandExecutionRequest(commandID: "copy", action: action)) { _ in }

        XCTAssertEqual(outcome, .copied(content: "later"))
    }

    func testExecutionReturnsProcessFailureWithoutThrowingAcrossTheBoundary() async {
        let runner = ActionRunner(diagnostics: DiagnosticsService())
        let request = CommandExecutionRequest(
            commandID: "test.process",
            action: CommandAction(id: "test.process.perform", title: "Run", kind: .runProcess(path: "/path/that/does/not/exist", arguments: []))
        )

        let outcome = await runner.execute(request) { _ in }

        guard case let .failure(message, retryable) = outcome else {
            return XCTFail("Expected a typed process failure")
        }
        XCTAssertEqual(message, "Failed to run process")
        XCTAssertTrue(retryable)
    }

    func testOpenActionReturnsTypedRouteWithPayload() async {
        let runner = ActionRunner(diagnostics: DiagnosticsService())
        let request = CommandExecutionRequest(
            commandID: "test.translate",
            action: CommandAction(
                id: "test.translate.open",
                title: "Open Translator",
                kind: .openTranslator(text: "hello", language: "Spanish")
            )
        )

        let outcome = await runner.execute(request) { _ in }

        XCTAssertEqual(outcome, .open(route: .translator(text: "hello", language: "Spanish")))
        XCTAssertFalse(outcome.shouldDismissPanel)
    }

    func testResetRankingRunsThroughTheExecutorBoundary() async {
        var resetCommandID: String?
        let runner = ActionRunner(
            diagnostics: DiagnosticsService(),
            resetRanking: { resetCommandID = $0 }
        )
        let request = CommandExecutionRequest(
            commandID: "test.command",
            action: CommandAction(
                id: "test.command.reset",
                title: "Reset Ranking",
                kind: .resetRanking(commandID: "test.command")
            )
        )

        let outcome = await runner.execute(request) { _ in }

        XCTAssertEqual(resetCommandID, "test.command")
        XCTAssertEqual(outcome, .stayOpen(message: "Ranking reset"))
    }

    func testDestructiveActionRequiresConfirmation() async {
        let runner = ActionRunner(
            diagnostics: DiagnosticsService(),
            confirmAction: { _, _ in false }
        )
        let request = CommandExecutionRequest(
            commandID: "test.quit",
            action: CommandAction(id: "test.quit.perform", title: "Quit", kind: .quit)
        )

        let outcome = await runner.execute(request) { _ in }

        XCTAssertEqual(outcome, .denied(message: "Action cancelled"))
    }

    func testWindowPermissionKeepsThePanelStateAvailable() async {
        let runner = ActionRunner(
            diagnostics: DiagnosticsService(),
            windowManager: PermissionWindowManager()
        )
        let request = CommandExecutionRequest(
            commandID: "test.window",
            action: CommandAction(id: "test.window.perform", title: "Tile", kind: .tileWindow(.leftHalf))
        )

        let outcome = await runner.execute(request) { _ in }

        XCTAssertEqual(outcome, .stayOpen(message: "Accessibility permission required for window control"))
    }

    func testWindowPermissionDoesNotOpenSettingsAcrossRepeatedAttemptsButExplicitURLDoes() async {
        var openedURLs: [URL] = []
        let runner = ActionRunner(
            diagnostics: DiagnosticsService(),
            windowManager: PermissionWindowManager(),
            openURL: { url in
                openedURLs.append(url)
                return true
            }
        )
        let tileRequest = CommandExecutionRequest(
            commandID: "test.window.repeated",
            action: CommandAction(id: "test.window.repeated.perform", title: "Tile", kind: .tileWindow(.leftHalf))
        )

        for _ in 0..<3 {
            let outcome = await runner.execute(tileRequest) { _ in }
            XCTAssertEqual(outcome, .stayOpen(message: "Accessibility permission required for window control"))
        }
        XCTAssertTrue(openedURLs.isEmpty)

        let openSettingsRequest = CommandExecutionRequest(
            commandID: "test.accessibility.settings",
            action: CommandAction(
                id: "test.accessibility.settings.open",
                title: "Open Accessibility Settings",
                kind: .openURL(NativeWindowManager.accessibilitySettingsURL.absoluteString)
            )
        )

        let openSettingsOutcome = await runner.execute(openSettingsRequest) { _ in }
        XCTAssertEqual(openSettingsOutcome, .success(message: "Opened link"))
        XCTAssertEqual(openedURLs, [NativeWindowManager.accessibilitySettingsURL])
    }

    func testCancellationCancelsAProcessExecution() async throws {
        let runner = ActionRunner(diagnostics: DiagnosticsService())
        let cancellationID = UUID()
        let request = CommandExecutionRequest(
            commandID: "test.sleep",
            action: CommandAction(id: "test.sleep.perform", title: "Sleep", kind: .runProcess(path: "/bin/sleep", arguments: ["10"])),
            cancellationID: cancellationID
        )

        let task = Task { await runner.execute(request) { _ in } }
        try await Task.sleep(for: .milliseconds(50))
        runner.cancel(cancellationID)
        let outcome = await task.value

        XCTAssertEqual(outcome, .cancelled)
    }

    func testCallerCancellationCancelsTheOwnedExecution() async throws {
        let runner = ActionRunner(diagnostics: DiagnosticsService())
        let request = CommandExecutionRequest(
            commandID: "test.sleep.caller-cancel",
            action: CommandAction(
                id: "test.sleep.caller-cancel.perform",
                title: "Sleep",
                kind: .runProcess(path: "/bin/sleep", arguments: ["10"])
            )
        )

        let task = Task { await runner.execute(request) { _ in } }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
    }

    func testDuplicateCancellationIDsDoNotReplaceTheOriginalExecution() async throws {
        let runner = ActionRunner(diagnostics: DiagnosticsService())
        let cancellationID = UUID()
        let request = CommandExecutionRequest(
            commandID: "test.sleep.duplicate",
            action: CommandAction(
                id: "test.sleep.duplicate.perform",
                title: "Sleep",
                kind: .runProcess(path: "/bin/sleep", arguments: ["10"])
            ),
            cancellationID: cancellationID
        )

        let first = Task { await runner.execute(request) { _ in } }
        try await Task.sleep(for: .milliseconds(50))
        let duplicate = await runner.execute(request) { _ in }

        guard case let .failure(message, retryable) = duplicate else {
            return XCTFail("Expected duplicate execution to be rejected")
        }
        XCTAssertTrue(message.contains("already running"))
        XCTAssertTrue(retryable)
        runner.cancel(cancellationID)
        let outcome = await first.value
        XCTAssertEqual(outcome, .cancelled)
    }

    func testMediaExecutionsHaveIndependentCancellationOwnership() async throws {
        let media = FakeMediaDownloadService()
        let runner = ActionRunner(
            diagnostics: DiagnosticsService(),
            mediaDownloadService: media
        )
        let firstID = UUID()
        let secondID = UUID()
        let firstRequest = CommandExecutionRequest(
            commandID: "test.media.first",
            action: CommandAction(id: "test.media.first.perform", title: "Download", kind: .downloadMedia(url: "https://example.com/first")),
            cancellationID: firstID
        )
        let secondRequest = CommandExecutionRequest(
            commandID: "test.media.second",
            action: CommandAction(id: "test.media.second.perform", title: "Download", kind: .downloadMedia(url: "https://example.com/second")),
            cancellationID: secondID
        )

        let first = Task { await runner.execute(firstRequest) { _ in } }
        try await Task.sleep(for: .milliseconds(20))
        let second = Task { await runner.execute(secondRequest) { _ in } }
        try await Task.sleep(for: .milliseconds(20))
        runner.cancel(secondID)

        let secondOutcome = await second.value
        let firstOutcome = await first.value
        let maxConcurrent = await media.maxConcurrentValue()

        XCTAssertEqual(secondOutcome, .cancelled)
        XCTAssertEqual(firstOutcome, .stayOpen(message: "Downloaded first"))
        XCTAssertEqual(maxConcurrent, 2)
    }

    private actor FakeMediaDownloadService: MediaDownloading {
        nonisolated let downloadFolder = URL(fileURLWithPath: "/tmp")
        private var active = 0
        private var maxConcurrent = 0

        func download(
            urlString: String,
            status: (@MainActor @Sendable (String) -> Void)?
        ) async throws -> String {
            active += 1
            maxConcurrent = max(maxConcurrent, active)
            defer {
                active -= 1
            }

            try await Task.sleep(for: .milliseconds(100))
            return "Downloaded \(URL(string: urlString)?.lastPathComponent ?? "media")"
        }

        func maxConcurrentValue() -> Int {
            maxConcurrent
        }
    }

    private final class TestSnippetStore: SnippetStore, @unchecked Sendable {
        let url = URL(fileURLWithPath: "/tmp/test-snippets.json")
        var snippets: [StoredSnippet]
        init(snippets: [StoredSnippet]) { self.snippets = snippets }
        func load() -> [StoredSnippet] { snippets }
        @discardableResult func save(_ snippets: [StoredSnippet]) -> Result<Void, Error> { self.snippets = snippets; return .success(()) }
    }

    @MainActor
    private final class PermissionWindowManager: WindowManaging {
        func isTrusted() -> Bool { false }

        func apply(_ placement: WindowPlacement) async -> WindowOperationResult {
            .needsAccessibilityPermission
        }
    }
}
