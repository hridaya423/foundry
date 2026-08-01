import XCTest
@testable import Foundry

final class AgentMonitorTests: XCTestCase {
    func testBrandProviderIconsResolveFromPackagedResources() {
        XCTAssertNotNil(AgentProviderIcon.brandResourceURL(for: .opencode))
        XCTAssertNotNil(AgentProviderIcon.brandResourceURL(for: .claude))
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
}
