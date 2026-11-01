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

    func testResumesAfterQuitWhenAStepWasSaved() {
        localState.set(\.onboardingStep, OnboardingStep.tryIt.rawValue)
        XCTAssertTrue(OnboardingState.shouldShowAutomatically(localState: localState, configExistedAtLaunch: true))
        localState.set(\.onboardingCompletedVersion, "1.0.0")
        XCTAssertFalse(OnboardingState.shouldShowAutomatically(localState: localState, configExistedAtLaunch: true))
    }

    func testPresentingWelcomeSavesTheStepSoAQuitResumes() {
        let state = makeState()
        state.markPresented()
        XCTAssertEqual(localState.get(\.onboardingStep), OnboardingStep.welcome.rawValue)
        XCTAssertTrue(OnboardingState.shouldShowAutomatically(localState: localState, configExistedAtLaunch: true))
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
        state.completeTryIt()
        XCTAssertFalse(state.didTryPanel)
        state.go(to: .tryIt)
        state.completeTryIt()
        XCTAssertTrue(state.didTryPanel)
    }

    func testCommandSpaceAppliesImmediatelyWhenSpotlightIsOff() {
        let state = makeState()
        state.useCommandSpace(spotlightEnabled: { false })
        XCTAssertEqual(state.panel.settings.hotkey, .commandSpace)
        XCTAssertFalse(state.isWaitingForSpotlight)
    }

    func testCommandSpaceAutoDisablesSpotlight() {
        let state = makeState()
        state.useCommandSpace(spotlightEnabled: { true }, disableSpotlight: { true })
        XCTAssertTrue(state.isWaitingForSpotlight)
        XCTAssertFalse(state.spotlightHoldsCommandSpace)
        state.spotlightPollTick(spotlightEnabled: { false })
        XCTAssertEqual(state.panel.settings.hotkey, .commandSpace)
        XCTAssertFalse(state.isWaitingForSpotlight)
    }

    func testCommandSpaceShowsManualStepsWhenAutoDisableFails() {
        let state = makeState()
        state.panel.settings.setHotkey(.optionSpace)
        state.useCommandSpace(spotlightEnabled: { true }, disableSpotlight: { false })
        XCTAssertTrue(state.spotlightHoldsCommandSpace)
        XCTAssertTrue(state.isWaitingForSpotlight)
        XCTAssertNotEqual(state.panel.settings.hotkey, .commandSpace)
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

    func testRaycastHoldingCommandSpaceMovesToOptionSpace() {
        let suite = "foundry-raycast-\(UUID().uuidString)"
        let rival = LauncherRival.raycast(suiteName: suite)
        XCTAssertFalse(rival.holdsCommandSpace())
        UserDefaults(suiteName: suite)!.set("Command-49", forKey: "raycastGlobalHotkey")
        XCTAssertTrue(rival.holdsCommandSpace())
        XCTAssertTrue(rival.moveToOptionSpace())
        XCTAssertEqual(UserDefaults(suiteName: suite)!.string(forKey: "raycastGlobalHotkey"), "Option-49")
        XCTAssertFalse(rival.holdsCommandSpace())
    }

    func testAlfredHoldingCommandSpaceMovesToOptionSpace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-alfred-\(UUID().uuidString)/Alfred.alfredpreferences")
        let hotkey = root.appendingPathComponent("preferences/local/abc123/hotkey")
        try FileManager.default.createDirectory(at: hotkey, withIntermediateDirectories: true)
        let prefs = hotkey.appendingPathComponent("prefs.plist")
        let command = Int(NSEvent.ModifierFlags.command.rawValue), option = Int(NSEvent.ModifierFlags.option.rawValue)
        try (["key": 49, "mod": command, "string": "Space"] as NSDictionary).write(to: prefs)
        let rival = LauncherRival.alfred(preferencesRoot: root)
        XCTAssertTrue(rival.holdsCommandSpace())
        XCTAssertTrue(rival.moveToOptionSpace())
        XCTAssertEqual(NSDictionary(contentsOf: prefs)?["mod"] as? Int, option)
        XCTAssertEqual(NSDictionary(contentsOf: prefs)?["key"] as? Int, 49)
        XCTAssertFalse(rival.holdsCommandSpace())
    }

    func testAbandonTouchesNoOtherAppAndFallsBackToOptionSpace() {
        let state = makeState()
        state.panel.settings.setHotkey(.commandSpace)
        let moved = LockedFlag()
        let rival = LauncherRival(id: "test", name: "Test", bundleID: "app.foundry.tests.absent",
            holdsCommandSpace: { true }, moveToOptionSpace: { moved.value = true; return true })
        state.abandon(rivals: [rival], spotlightEnabled: { true })
        XCTAssertFalse(state.didClaimCommandSpace)
        XCTAssertTrue(state.takeovers.isEmpty)
        XCTAssertFalse(moved.value)
        XCTAssertEqual(state.panel.settings.hotkey, .optionSpace)
        XCTAssertNotNil(localState.get(\.onboardingCompletedVersion))
        XCTAssertNil(localState.get(\.onboardingStep))
    }

    func testAbandonKeepsCommandSpaceWhenNothingElseHoldsIt() {
        let state = makeState()
        state.panel.settings.setHotkey(.commandSpace)
        state.abandon(rivals: [], spotlightEnabled: { false })
        XCTAssertEqual(state.panel.settings.hotkey, .commandSpace)
    }

    func testClaimingCommandSpaceTurnsOffSpotlightAndMovesRivals() async {
        let state = makeState()
        let moved = LockedFlag()
        let rival = LauncherRival(id: "test", name: "Test", bundleID: "app.foundry.tests.absent",
            holdsCommandSpace: { moved.value == false }, moveToOptionSpace: { moved.value = true; return true })
        state.claimCommandSpace(rivals: [rival], spotlightEnabled: { true }, disableSpotlight: { true })
        XCTAssertTrue(state.didClaimSpotlight)
        XCTAssertEqual(state.takeovers.map(\.status), [.working])
        for _ in 0..<50 where state.takeovers.first?.status == .working { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(state.takeovers.map(\.status), [.done])
        XCTAssertTrue(moved.value)
        state.claimCommandSpace(rivals: [rival], spotlightEnabled: { false })
        XCTAssertEqual(state.takeovers.count, 1)
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
