import XCTest
import FoundryServices
@testable import Foundry

@MainActor
final class OnboardingStateTests: XCTestCase {
    private let localState = LocalStateStore()

    private func makeState(imports: [ImportSource] = [], appleIntelligence: Bool = false,
        loginItem: ((Bool) -> Void)? = { _ in }) -> OnboardingState {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-onboarding-\(UUID().uuidString).json"))
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        let panel = CommandPanelState(registry: registry, actionRunner: ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        return OnboardingState(panel: panel, permissions: PermissionHealthState(accessibilityTrusted: { false }), localState: localState,
            version: "1.1.0", importSources: { imports }, appleIntelligence: { appleIntelligence }, registerLoginItem: loginItem)
    }

    func testShowsAutomaticallyOnlyForFreshInstallsThatHaveNotCompleted() {
        XCTAssertTrue(OnboardingState.shouldShowAutomatically(localState: localState, configExistedAtLaunch: false))
        XCTAssertFalse(OnboardingState.shouldShowAutomatically(localState: localState, configExistedAtLaunch: true))
        localState.set(\.onboardingCompletedVersion, "1.0.0")
        XCTAssertFalse(OnboardingState.shouldShowAutomatically(localState: localState, configExistedAtLaunch: false))
    }

    func testResumesAfterQuitWhenAStepWasSaved() {
        localState.set(\.onboardingStep, OnboardingStep.shortcut.rawValue)
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
        XCTAssertEqual(state.step, .shortcut)
        XCTAssertEqual(makeState().step, .shortcut)
    }

    func testFinishRecordsVersionClearsStepAndNotifies() {
        let state = makeState()
        var finished = 0
        state.onFinish = { finished += 1 }
        state.go(to: .shortcut)
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
        state.go(to: .bringYourStuff)
        state.finish()
        XCTAssertEqual(steps, [.shortcut, .bringYourStuff, .done])
    }

    func testFlowHasFourStepsAtMost() {
        XCTAssertEqual(OnboardingStep.allCases, [.welcome, .shortcut, .bringYourStuff, .done])
    }

    func testBringYourStuffIsSkippedWhenNothingIsInstalled() {
        let state = makeState()
        state.go(to: .shortcut)
        state.advance()
        XCTAssertEqual(state.step, .done)
        state.back()
        XCTAssertEqual(state.step, .shortcut)
    }

    func testBringYourStuffShowsWhenAlfredHasSnippets() {
        let state = makeState(imports: [ImportSource(kind: .alfred, available: 12)])
        state.go(to: .shortcut)
        state.advance()
        XCTAssertEqual(state.step, .bringYourStuff)
        XCTAssertEqual(state.importSources.map(\.available), [12])
    }

    func testTryItCompletesOnlyWhenAResultRuns() {
        let state = makeState()
        state.completeTryIt()
        XCTAssertFalse(state.didLaunch)
        state.go(to: .shortcut)
        state.panelClosedWithoutLaunch()
        XCTAssertFalse(state.didLaunch)
        XCTAssertTrue(state.openedWithoutLaunch)
        state.completeTryIt()
        XCTAssertTrue(state.didLaunch)
    }

    func testTryItLeadNamesARunningAppThatIsNotFoundOrFrontmost() {
        let running = [(name: "Finder", bundleID: "com.apple.finder"), (name: "Xcode", bundleID: "com.apple.dt.Xcode"),
            (name: "T3 Code (Nightly)", bundleID: "com.t3.nightly"),
            (name: "Notes", bundleID: "com.apple.Notes")]
        XCTAssertEqual(OnboardingState.suggestedLaunch(running: running, frontmost: "com.apple.dt.Xcode"),
            .init(name: "Notes", prefix: "no"))
        XCTAssertEqual(OnboardingState.suggestedLaunch(running: [], frontmost: nil), .init(name: "Safari", prefix: "sa"))
    }

    func testShortcutStepDoesNotMoveRivalsWithoutConsent() {
        let state = makeState()
        let moved = LockedFlag()
        let rival = LauncherRival(id: "test", name: "Raycast", bundleID: "app.foundry.tests.absent",
            holdsCommandSpace: { true }, moveToOptionSpace: { moved.value = true; return true })
        state.go(to: .shortcut)
        state.detectCommandSpaceHolders(rivals: [rival], spotlightEnabled: { true })
        XCTAssertEqual(state.commandSpaceHolders, ["Spotlight", "Raycast"])
        XCTAssertFalse(moved.value)
        XCTAssertFalse(state.didClaimCommandSpace)
        state.useOptionSpace()
        XCTAssertEqual(state.panel.settings.hotkey, .optionSpace)
        XCTAssertFalse(moved.value)
    }

    func testUnclaimedChordOffersOptionSpace() {
        let state = makeState()
        state.panel.settings.setHotkey(.commandSpace)
        state.go(to: .shortcut)
        state.commandSpaceReachedWindow()
        XCTAssertTrue(state.commandSpaceUnreachable)
        state.finish()
        XCTAssertEqual(state.panel.settings.hotkey, .optionSpace)
    }

    func testReceiptListsOnlyWhatHappened() {
        let state = makeState(appleIntelligence: true)
        state.panel.settings.setHotkey(.commandSpace)
        state.go(to: .done)
        XCTAssertEqual(state.receipt, ["⌘ Space is yours", "Apple Intelligence answers Tab"])
    }

    func testFinishRegistersLoginItemOnlyWhenTheRowIsOn() {
        var registered: [Bool] = []
        let on = makeState(loginItem: { registered.append($0) })
        on.finish()
        XCTAssertEqual(registered, [true])
        let off = makeState(loginItem: { registered.append($0) })
        off.startsAtLogin = false
        off.finish()
        XCTAssertEqual(registered, [true])
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

    func testAccessibilityRequestShowsTheSystemPromptFirstAndSettingsAfter() {
        var prompts = 0
        var opened: [URL] = []
        let health = PermissionHealthState(accessibilityTrusted: { false }, localState: localState,
            prompt: { prompts += 1 }, open: { opened.append($0) })
        health.request(.accessibility)
        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(opened, [])
        health.request(.accessibility)
        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(opened, [PermissionKind.accessibility.settingsURL])
    }

    func testScreenRecordingRequestOpensOneSystemSurfaceAtATime() {
        var requests = 0
        var opened: [URL] = []
        let health = PermissionHealthState(accessibilityTrusted: { false }, localState: localState, open: { opened.append($0) },
            screenCaptureAllowed: { false }, requestScreenCapture: { requests += 1 })
        XCTAssertEqual(health.status(for: .screenRecording), .notGranted)
        health.request(.screenRecording)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(opened, [])
        health.request(.screenRecording)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(opened, [PermissionKind.screenRecording.settingsURL])
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
