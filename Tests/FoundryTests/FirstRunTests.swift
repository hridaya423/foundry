import XCTest
import FoundryDomain
import FoundryServices
@testable import Foundry

@MainActor
final class FirstRunTests: XCTestCase {
    private func makeState(_ localState: LocalStateStore) -> CommandPanelState {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-first-\(UUID().uuidString).json"))
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        return CommandPanelState(registry: registry, actionRunner: ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics,
            config: config, localState: localState)
    }

    func testFirstOpenAfterOnboardingUsesTaskPlaceholderOnce() {
        let localState = LocalStateStore()
        let state = makeState(localState)
        state.resetForOpen()
        XCTAssertNil(state.searchHint, "no hint before onboarding finishes")
        state.panelWillClose()
        localState.set(\.onboardingCompletedVersion, "1.3.0")
        state.resetForOpen()
        XCTAssertEqual(state.searchHint, CommandPanelState.firstRunHint)
        state.panelWillClose()
        XCTAssertNil(state.searchHint)
        state.resetForOpen()
        XCTAssertNil(state.searchHint)
        state.shutdown()
    }

    func testFirstEverRunShowsOneAcknowledgementOnce() async {
        let localState = LocalStateStore()
        localState.set(\.onboardingCompletedVersion, "1.3.0")
        let state = makeState(localState)
        let result = CommandResult(id: "test.copy", title: "Copy", subtitle: nil, icon: CommandIcon(fallback: "C"), payload: .command,
            primaryAction: CommandAction(id: "test.copy.run", title: "Run", behavior: OpenHomeAction()), secondaryActions: [])
        await state.executeResult(result)
        XCTAssertTrue(localState.get(\.firstLaunchAcknowledged))
        guard case let .info(message)? = state.actionFeedback else { return XCTFail("expected the acknowledgement") }
        XCTAssertTrue(message.hasPrefix("That’s it."))
        state.shutdown()
        let later = makeState(localState)
        await later.executeResult(result)
        XCTAssertNil(later.actionFeedback)
        later.shutdown()
    }

    func testTipAppearsAfterFiveLaunchesAndDismissalSticks() {
        let localState = LocalStateStore()
        localState.set(\.launchCount, 4)
        let state = makeState(localState)
        state.resetForOpen()
        XCTAssertEqual(state.tip?.id, Tip.all[0].id)
        state.dismissTip()
        XCTAssertNil(state.tip)
        state.panelWillClose()
        state.resetForOpen()
        XCTAssertNil(state.tip, "the next tip waits for tomorrow")
        state.shutdown()
    }

    func testLoginNudgeShowsOnSecondLaunchWhenTheLoginItemIsOff() {
        let localState = LocalStateStore()
        localState.set(\.onboardingCompletedVersion, "1.3.0")
        localState.set(\.launchCount, 1)
        let state = makeState(localState)
        state.loginItemIsOff = { true }
        state.resetForOpen()
        XCTAssertTrue(state.showsLoginNudge)
        XCTAssertNil(state.tip, "one notice at a time")
        state.answerLoginNudge(turnOn: false)
        state.panelWillClose()
        state.resetForOpen()
        XCTAssertFalse(state.showsLoginNudge)
        state.shutdown()
    }

    func testNoLoginNudgeWhenTheLoginItemIsOn() {
        let localState = LocalStateStore()
        localState.set(\.onboardingCompletedVersion, "1.3.0")
        localState.set(\.launchCount, 3)
        let state = makeState(localState)
        state.loginItemIsOff = { false }
        state.resetForOpen()
        XCTAssertFalse(state.showsLoginNudge)
        state.shutdown()
    }
}