import os
import XCTest
import FoundryDomain
import FoundryServices
@testable import Foundry

@MainActor
final class UpdateCheckTests: XCTestCase {
    func testOnlyAStrictlyNewerReleaseIsAnUpdate() {
        XCTAssertEqual(UpdateCheck.update(in: Self.release("v1.4.1"), newerThan: "1.4.0"),
            AvailableUpdate(version: "1.4.1", pageURL: URL(string: "https://github.com/hridaya423/foundry/releases/tag/v1.4.1")!))
        XCTAssertEqual(UpdateCheck.update(in: Self.release("v1.10.0"), newerThan: "1.9.2")?.version, "1.10.0")
        XCTAssertEqual(UpdateCheck.update(in: Self.release("2.0.0"), newerThan: "1.4.0")?.version, "2.0.0")
        XCTAssertNil(UpdateCheck.update(in: Self.release("v1.4.0"), newerThan: "1.4.0"))
        XCTAssertNil(UpdateCheck.update(in: Self.release("v1.3.0"), newerThan: "1.4.0"))
        XCTAssertNil(UpdateCheck.update(in: Data("{\"message\":\"Not Found\"}".utf8), newerThan: "1.4.0"))
    }

    func testOpeningThePanelChecksOnceADayAndShowsANewerVersion() async {
        let fetches = OSAllocatedUnfairLock(initialState: 0)
        let state = makeState(installedVersion: "1.4.0") {
            fetches.withLock { $0 += 1 }
            return Self.release("v1.4.1")
        }
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        state.now = { clock }

        state.resetForOpen()
        await waitUntil { state.availableUpdate?.version == "1.4.1" }
        state.resetForOpen()
        state.checkForUpdateIfDue()
        await settle()
        XCTAssertEqual(fetches.withLock { $0 }, 1)

        clock += UpdateCheck.interval
        state.checkForUpdateIfDue()
        await waitUntil { fetches.withLock { $0 } == 2 }
        state.shutdown()
    }

    func testAFailedCheckRetriesAfterAnHour() async {
        let fetches = OSAllocatedUnfairLock(initialState: 0)
        let state = makeState(installedVersion: "1.4.0") {
            fetches.withLock { $0 += 1 }
            return nil
        }
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        state.now = { clock }

        state.checkForUpdateIfDue()
        await waitUntil { fetches.withLock { $0 } == 1 }
        clock += UpdateCheck.retryInterval - 1
        state.checkForUpdateIfDue()
        await settle()
        XCTAssertEqual(fetches.withLock { $0 }, 1)
        clock += 1
        state.checkForUpdateIfDue()
        await waitUntil { fetches.withLock { $0 } == 2 }
        XCTAssertNil(state.availableUpdate)
        state.shutdown()
    }

    func testDismissingHidesThatVersionButNotTheNextOne() async {
        let localState = LocalStateStore()
        let first = makeState(installedVersion: "1.4.0", localState: localState) { Self.release("v1.4.1") }
        first.checkForUpdateIfDue()
        await waitUntil { first.availableUpdate != nil }
        first.dismissUpdate()
        XCTAssertNil(first.availableUpdate)
        XCTAssertEqual(localState.get(\.updateDismissedVersion), "1.4.1")
        first.shutdown()

        let relaunched = makeState(installedVersion: "1.4.0", localState: localState) { Self.release("v1.4.1") }
        relaunched.checkForUpdateIfDue()
        await settle()
        XCTAssertNil(relaunched.availableUpdate)
        relaunched.shutdown()

        let later = makeState(installedVersion: "1.4.0", localState: localState) { Self.release("v1.4.2") }
        later.checkForUpdateIfDue()
        await waitUntil { later.availableUpdate?.version == "1.4.2" }
        later.shutdown()
    }

    func testTurningTheSettingOffOrRunningAnUnversionedBuildNeverFetches() async {
        let fetches = OSAllocatedUnfairLock(initialState: 0)
        let fetch: @Sendable () async -> Data? = {
            fetches.withLock { $0 += 1 }
            return nil
        }
        let off = makeState(installedVersion: "1.4.0", latestRelease: fetch)
        off.settings.setCheckForUpdates(false)
        off.checkForUpdateIfDue()
        let unversioned = makeState(installedVersion: nil, latestRelease: fetch)
        unversioned.checkForUpdateIfDue()
        await settle()
        XCTAssertEqual(fetches.withLock { $0 }, 0)
        off.shutdown()
        unversioned.shutdown()
    }

    private nonisolated static func release(_ tag: String) -> Data {
        Data("""
            {"tag_name":"\(tag)","html_url":"https://github.com/hridaya423/foundry/releases/tag/\(tag)","draft":false}
            """.utf8)
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(50))
    }

    private func makeState(installedVersion: String?, localState: LocalStateStore = LocalStateStore(),
                           latestRelease: @escaping @Sendable () async -> Data?) -> CommandPanelState {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-update-\(UUID().uuidString).json"))
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        return CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics,
            config: config, localState: localState, latestRelease: latestRelease, installedVersion: installedVersion)
    }
}
