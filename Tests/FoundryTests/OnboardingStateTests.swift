import XCTest
import FoundryServices
@testable import Foundry

@MainActor
final class OnboardingStateTests: XCTestCase {
    private let localState = LocalStateStore()

    private func makeState() -> OnboardingState {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-onboarding-\(UUID().uuidString).json"))
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        let panel = CommandPanelState(registry: registry, actionRunner: ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        return OnboardingState(panel: panel, permissions: PermissionHealthState(accessibilityTrusted: { false }), localState: localState, version: "1.1.0")
    }

    func testShowsAutomaticallyOnlyForFreshInstallsThatHaveNotCompleted() {
        XCTAssertTrue(OnboardingState.shouldShowAutomatically(localState: localState, configExistedAtLaunch: false))
        XCTAssertFalse(OnboardingState.shouldShowAutomatically(localState: localState, configExistedAtLaunch: true))
        localState.set(\.onboardingCompletedVersion, "1.0.0")
        XCTAssertFalse(OnboardingState.shouldShowAutomatically(localState: localState, configExistedAtLaunch: false))
    }

    func testStepPersistsAndResumes() {
        let state = makeState()
        XCTAssertEqual(state.step, .welcome)
        state.back()
        XCTAssertEqual(state.step, .welcome)
        state.advance()
        state.advance()
        XCTAssertEqual(state.step, .tryIt)
        XCTAssertEqual(makeState().step, .tryIt)
    }

    func testFinishRecordsVersionClearsStepAndNotifies() {
        let state = makeState()
        var finished = 0
        state.onFinish = { finished += 1 }
        state.go(to: .permissions)
        state.finish()
        XCTAssertEqual(finished, 1)
        XCTAssertEqual(localState.snapshot.onboardingCompletedVersion, "1.1.0")
        XCTAssertNil(localState.snapshot.onboardingStep)
        XCTAssertEqual(makeState().step, .welcome)
    }

    func testAdvancingPastLastStepFinishes() {
        let state = makeState()
        var finished = false
        state.onFinish = { finished = true }
        state.go(to: .done)
        state.advance()
        XCTAssertTrue(finished)
    }

    func testStepChangesFireInstrumentationCallback() {
        let state = makeState()
        var steps: [OnboardingStep] = []
        state.onStepChanged = { steps.append($0) }
        state.go(to: .shortcut)
        state.go(to: .tryIt)
        state.finish()
        XCTAssertEqual(steps, [.shortcut, .tryIt, .done])
    }

    func testTryItOnlyCountsCommandsRunDuringThatStep() {
        let state = makeState()
        state.panelDidRunCommand()
        XCTAssertFalse(state.didTryPanel)
        state.go(to: .tryIt)
        state.panelDidRunCommand()
        XCTAssertTrue(state.didTryPanel)
    }

    func testCommandSpaceAppliesImmediatelyWhenSpotlightIsOff() {
        let state = makeState()
        state.useCommandSpace(spotlightEnabled: { false })
        XCTAssertEqual(state.panel.hotkey, .commandSpace)
        XCTAssertFalse(state.isWaitingForSpotlight)
    }

    func testCommandSpaceAutoDisablesSpotlight() {
        let state = makeState()
        state.useCommandSpace(spotlightEnabled: { true }, disableSpotlight: { true })
        XCTAssertTrue(state.isWaitingForSpotlight)
        XCTAssertFalse(state.spotlightHoldsCommandSpace)
        state.spotlightPollTick(spotlightEnabled: { false })
        XCTAssertEqual(state.panel.hotkey, .commandSpace)
        XCTAssertFalse(state.isWaitingForSpotlight)
    }

    func testCommandSpaceShowsManualStepsWhenAutoDisableFails() {
        let state = makeState()
        state.useCommandSpace(spotlightEnabled: { true }, disableSpotlight: { false })
        XCTAssertTrue(state.spotlightHoldsCommandSpace)
        XCTAssertTrue(state.isWaitingForSpotlight)
        XCTAssertNotEqual(state.panel.hotkey, .commandSpace)
        state.stopWaitingForSpotlight()
        XCTAssertFalse(state.isWaitingForSpotlight)
    }

    func testCommandSpaceFallsBackToManualStepsAfterTimeout() {
        let state = makeState()
        state.useCommandSpace(spotlightEnabled: { true }, disableSpotlight: { true })
        XCTAssertFalse(state.spotlightHoldsCommandSpace)
        for _ in 0..<10 { state.spotlightPollTick(spotlightEnabled: { true }) }
        XCTAssertTrue(state.spotlightHoldsCommandSpace)
        XCTAssertTrue(state.isWaitingForSpotlight)
    }

    func testSpotlightSetEnabledPreservesEntryAndWritesFlag() {
        let suite = "foundry-spotlight-\(UUID().uuidString)"
        let suiteDefaults = UserDefaults(suiteName: suite)!
        suiteDefaults.set(["64": ["enabled": true, "value": ["type": "standard"]]], forKey: "AppleSymbolicHotKeys")
        XCTAssertTrue(SpotlightShortcut.setEnabled(false, suiteName: suite, reloadPreferences: {}))
        let hotkeys = suiteDefaults.dictionary(forKey: "AppleSymbolicHotKeys")
        XCTAssertFalse(SpotlightShortcut.isEnabled(symbolicHotKeys: hotkeys))
        let entry = hotkeys?["64"] as? [String: Any]
        XCTAssertNotNil(entry?["value"])
        XCTAssertTrue(SpotlightShortcut.setEnabled(true, suiteName: suite, reloadPreferences: {}))
        XCTAssertTrue(SpotlightShortcut.isEnabled(symbolicHotKeys: suiteDefaults.dictionary(forKey: "AppleSymbolicHotKeys")))
    }

    func testSpotlightShortcutParsing() {
        XCTAssertTrue(SpotlightShortcut.isEnabled(symbolicHotKeys: nil))
        XCTAssertTrue(SpotlightShortcut.isEnabled(symbolicHotKeys: ["64": ["enabled": true]]))
        XCTAssertFalse(SpotlightShortcut.isEnabled(symbolicHotKeys: ["64": ["enabled": false]]))
        XCTAssertFalse(SpotlightShortcut.isEnabled(symbolicHotKeys: ["64": ["enabled": 0]]))
        XCTAssertTrue(SpotlightShortcut.isEnabled(symbolicHotKeys: ["65": ["enabled": false]]))
    }

    func testPermissionHealthMapping() {
        XCTAssertEqual(PermissionHealthState.status(for: .accessibility, accessibilityTrusted: true), .granted)
        XCTAssertEqual(PermissionHealthState.status(for: .accessibility, accessibilityTrusted: false), .notGranted)
        XCTAssertEqual(PermissionHealthState.status(for: .automation, accessibilityTrusted: true), .askedOnUse)
        var trusted = false
        let health = PermissionHealthState(accessibilityTrusted: { trusted })
        XCTAssertEqual(health.status(for: .accessibility), .notGranted)
        trusted = true
        health.refresh()
        XCTAssertEqual(health.status(for: .accessibility), .granted)
    }
}
