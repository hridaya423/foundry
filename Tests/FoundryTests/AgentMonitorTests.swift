import XCTest
@testable import Foundry
import FoundryServices

final class AgentMonitorTests: XCTestCase {
    func testOpenCodeCatalogDoesNotMarkEverySessionRunningFromOneProcess() {
        let unrelated = ProcessInfoRow(pid: "1", startedAt: Date(), args: "/usr/local/bin/opencode --session other-session")
        XCTAssertEqual(AgentMonitorService.openCodeCatalogStatus(sessionID: "target-session", processes: [unrelated]), .recent)
    }

    func testWorkspaceDiffIncludesStagedAndUntrackedFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertTrue(runGit(["init"], in: directory))
        try Data("staged".utf8).write(to: directory.appendingPathComponent("staged.txt"))
        XCTAssertTrue(runGit(["add", "staged.txt"], in: directory))
        try Data("untracked".utf8).write(to: directory.appendingPathComponent("untracked.txt"))

        let summary = AgentMonitorService.workspaceDiffSummary(directory: directory.path)

        XCTAssertTrue(summary?.contains("2 files") == true)
        XCTAssertTrue(summary?.contains("+1") == true)
    }

    func testWorkspaceDiffLabelsUntrackedFilesSeparatelyFromLineChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertTrue(runGit(["init"], in: directory))
        try Data("untracked\n".utf8).write(to: directory.appendingPathComponent("untracked.txt"))

        let summary = AgentMonitorService.workspaceDiffSummary(directory: directory.path)

        XCTAssertTrue(summary?.contains("1 untracked") == true)
    }

    func testWorkspaceDiffCountsFilesInsideUntrackedDirectories() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let nested = directory.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        XCTAssertTrue(runGit(["init"], in: directory))
        try Data("one\n".utf8).write(to: nested.appendingPathComponent("one.txt"))
        try Data("two\n".utf8).write(to: nested.appendingPathComponent("two.txt"))

        let summary = AgentMonitorService.workspaceDiffSummary(directory: directory.path)

        XCTAssertTrue(summary?.contains("2 files") == true)
        XCTAssertTrue(summary?.contains("2 untracked") == true)
    }

    func testNativeProcessArgumentParsingUsesArgumentCount() {
        var argumentCount: Int32 = 2
        var buffer = [UInt8]()
        withUnsafeBytes(of: &argumentCount) { buffer.append(contentsOf: $0) }
        buffer.append(contentsOf: Array("/usr/bin/claude".utf8) + [0])
        buffer.append(contentsOf: Array("claude".utf8) + [0])
        buffer.append(contentsOf: Array("--session-id".utf8) + [0])
        buffer.append(contentsOf: Array("ignored-environment-value".utf8) + [0])

        XCTAssertEqual(
            NativeProcessSnapshotProvider.parseArguments(from: buffer),
            "/usr/bin/claude claude --session-id"
        )
    }

    func testProcessInfoRowUsesFirstArgumentAsExecutableName() {
        let process = ProcessInfoRow(pid: "42", startedAt: nil, args: "/Applications/Codex.app/Contents/MacOS/Codex --resume")

        XCTAssertEqual(process.executableName, "Codex")
    }

    func testBrandProviderIconsResolveFromPackagedResources() {
        XCTAssertNotNil(AgentProviderIcon.brandResourceURL(for: .opencode))
        XCTAssertNotNil(AgentProviderIcon.brandResourceURL(for: .claude))
    }

    func testClaudeHistoryExcludesCodexBarUsageProbesAndKeepsRealSessions() {
        let now = Date()
        let timestamp = Int(now.timeIntervalSince1970 * 1_000)
        let history = [
            "{\"display\":\"/usage\",\"timestamp\":\(timestamp),\"project\":\"/Users/test/Library/Application Support/CodexBar/ClaudeProbe\",\"sessionId\":\"probe-1\"}",
            "{\"display\":\"/usage\",\"timestamp\":\(timestamp - 1_000),\"project\":\"/Users/test/Library/Application Support/CodexBar/ClaudeProbe\",\"sessionId\":\"probe-2\"}",
            "{\"display\":\"Fix the session picker\",\"timestamp\":\(timestamp - 1_000),\"project\":\"/Users/test/anvil\",\"sessionId\":\"real-1\"}",
            "{\"display\":\"Continue the session picker\",\"timestamp\":\(timestamp),\"project\":\"/Users/test/anvil\",\"sessionId\":\"real-1\"}",
            "not json"
        ].joined(separator: "\n")

        let cards = AgentMonitorService.claudeHistorySessions(from: history, now: now)

        XCTAssertEqual(cards.map(\.id), ["claude.real-1"])
        XCTAssertEqual(cards.first?.title, "Continue the session picker")
        XCTAssertEqual(cards.first?.workingDirectory, "/Users/test/anvil")
    }

    func testClaudeHistoryDoesNotOverFilterOrdinaryClaudeProbeProject() {
        let now = Date()
        let timestamp = Int(now.timeIntervalSince1970 * 1_000)
        let history = "{\"display\":\"Investigate ClaudeProbe\",\"timestamp\":\(timestamp),\"project\":\"/Users/test/projects/ClaudeProbe\",\"sessionId\":\"real-2\"}"

        let cards = AgentMonitorService.claudeHistorySessions(from: history, now: now)

        XCTAssertEqual(cards.map(\.id), ["claude.real-2"])
    }

    func testAgentShelfProviderFilteringKeepsAllOpenCodeSessions() {
        let sessions = (0..<7).map { index in
            AgentSessionCard(
                id: "opencode.session-\(index)",
                provider: .opencode,
                title: "OpenCode Session \(index)",
                subtitle: "build",
                project: "anvil",
                model: "gpt-test",
                status: .recent,
                startedAt: Date(),
                updatedAt: Date(),
                openTarget: .terminal(command: "opencode"),
                key: AgentSessionKey(provider: .opencode, rawSessionID: "session-\(index)"),
                origin: .catalog,
                capabilities: [.observe, .jumpTerminal]
            )
        }

        let filtered = AgentShelfView.sessions(for: .opencode, in: sessions)

        XCTAssertEqual(filtered.count, 7)
        XCTAssertEqual(filtered.map(\.id), sessions.map(\.id))
    }

    func testAgentEventValidationRejectsDeadlinesOutsideTheFiveMinuteWindow() {
        let now = Date()
        let envelope = AgentEventEnvelope(
            requestID: "request-1",
            provider: .opencode,
            sessionID: "session-1",
            deadline: now.addingTimeInterval(301),
            event: .sessionStart(metadata: nil)
        )

        XCTAssertThrowsError(try envelope.validated(now: now)) { error in
            XCTAssertEqual(error as? AgentEventValidationError, .invalidDeadline)
        }
    }

    func testSessionStoreRejectsReplayAndPublishesProviderScopedSession() async {
        let store = AgentSessionStore()
        let envelope = AgentEventEnvelope(
            requestID: "request-1",
            provider: .opencode,
            sessionID: "session-1",
            origin: .plugin,
            capabilities: [.observe, .liveText, .questions],
            metadata: AgentSessionMetadata(
                title: "Foundry work",
                workingDirectory: "/tmp/foundry",
                project: "Foundry",
                model: "gpt-test",
                terminalCommand: "opencode",
                terminalLocator: nil
            ),
            event: .sessionStart(metadata: nil)
        )

        let first = await store.apply(envelope)
        let replay = await store.apply(envelope)

        XCTAssertTrue(first.accepted)
        XCTAssertFalse(replay.accepted)
        XCTAssertEqual(first.cards.count, 1)
        XCTAssertEqual(first.cards.first?.origin, .plugin)
        XCTAssertTrue(first.cards.first?.capabilities.contains(.questions) == true)
        XCTAssertEqual(first.cards.first?.project, "Foundry")
    }

    func testReplayIdentifiersAreScopedToProviderAndSession() async {
        let store = AgentSessionStore()
        let first = AgentEventEnvelope(
            requestID: "shared-request",
            provider: .claude,
            sessionID: "session-1",
            eventID: "shared-event",
            event: .sessionStart(metadata: nil)
        )
        let second = AgentEventEnvelope(
            requestID: "shared-request",
            provider: .codex,
            sessionID: "session-2",
            eventID: "shared-event",
            event: .sessionStart(metadata: nil)
        )

        let firstUpdate = await store.apply(first)
        let secondUpdate = await store.apply(second)
        XCTAssertTrue(firstUpdate.accepted)
        XCTAssertTrue(secondUpdate.accepted)
    }

    func testSessionEndRemovesParentAndChildren() async {
        let store = AgentSessionStore()
        let parent = AgentEventEnvelope(
            requestID: "parent-start",
            provider: .claude,
            sessionID: "parent",
            origin: .hook,
            event: .sessionStart(metadata: nil)
        )
        let child = AgentEventEnvelope(
            requestID: "child-start",
            provider: .claude,
            sessionID: "child",
            parentSessionID: "parent",
            origin: .hook,
            event: .sessionStart(metadata: nil)
        )
        let end = AgentEventEnvelope(
            requestID: "parent-end",
            provider: .claude,
            sessionID: "parent",
            origin: .hook,
            event: .sessionEnd
        )

        _ = await store.apply(parent)
        _ = await store.apply(child)
        let update = await store.apply(end)

        XCTAssertTrue(update.accepted)
        XCTAssertTrue(update.cards.isEmpty)
    }

    func testHookSessionCannotBeDowngradedByProcessFallback() async {
        let store = AgentSessionStore()
        let fallback = AgentSessionCard(
            id: "opencode.session-1",
            provider: .opencode,
            title: "Fallback",
            subtitle: "process",
            project: nil,
            model: nil,
            status: .running,
            startedAt: Date(),
            updatedAt: Date(),
            openTarget: .application(name: "OpenCode")
        )
        _ = await store.reconcileObserved([fallback])

        let event = AgentEventEnvelope(
            requestID: "hook-start",
            provider: .opencode,
            sessionID: "session-1",
            origin: .plugin,
            event: .sessionStart(metadata: AgentSessionMetadata(
                title: "Plugin session",
                workingDirectory: nil,
                project: nil,
                model: nil,
                terminalCommand: nil,
                terminalLocator: nil
            ))
        )
        _ = await store.apply(event)
        let cards = await store.reconcileObserved([fallback])

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.origin, .plugin)
        XCTAssertEqual(cards.first?.title, "Plugin session")
    }

    func testCatalogSessionRetainsCatalogAuthority() async {
        let store = AgentSessionStore()
        let card = AgentSessionCard(
            id: "codex.thread-1",
            provider: .codex,
            title: "Thread",
            subtitle: "Project",
            project: "Project",
            model: "gpt-test",
            status: .working,
            startedAt: Date(),
            updatedAt: Date(),
            openTarget: .deepLink(URL(string: "codex://threads/thread-1")!),
            key: AgentSessionKey(provider: .codex, rawSessionID: "thread-1"),
            origin: .catalog,
            capabilities: [.observe, .jumpTask]
        )

        let cards = await store.reconcileObserved([card])

        XCTAssertEqual(cards.first?.origin, .catalog)
        XCTAssertEqual(cards.first?.status, .working)
    }

    func testGeneratedTitleSurvivesCatalogReconciliation() async {
        let store = AgentSessionStore()
        let key = AgentSessionKey(provider: .codex, rawSessionID: "thread-2")
        let card = AgentSessionCard(
            id: "codex.thread-2",
            provider: .codex,
            title: "Original prompt",
            subtitle: "Project",
            project: "Project",
            model: "gpt-test",
            status: .recent,
            startedAt: Date(),
            updatedAt: Date(),
            openTarget: .deepLink(URL(string: "codex://threads/thread-2")!),
            key: key,
            origin: .catalog,
            capabilities: [.observe, .jumpTask],
            needsTitleGeneration: true
        )

        _ = await store.reconcileObserved([card])
        await store.updateTitle("Generated title", for: key)
        let reconciled = await store.reconcileObserved([card])

        XCTAssertEqual(reconciled.first?.title, "Generated title")
        XCTAssertEqual(reconciled.first?.needsTitleGeneration, false)
        XCTAssertEqual(reconciled.first?.isGeneratedTitle, true)
    }

    private func runGit(_ arguments: [String], in directory: URL) -> Bool {
        ProcessRunner.runSynchronously(path: "/usr/bin/git", arguments: ["-C", directory.path] + arguments, timeout: 10)?.succeeded == true
    }
}
