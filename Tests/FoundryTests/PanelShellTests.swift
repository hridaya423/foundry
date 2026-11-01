import XCTest
@testable import Foundry
import FoundryServices
import FoundryDomain
import AppKit

@MainActor
final class PanelShellTests: XCTestCase {

    @MainActor
    private final class FakeActivation: AppActivation {
        var activateCalls = 0
        var deactivateCalls = 0
        var isActive = true
        func activate() { activateCalls += 1; isActive = true }
        func deactivate() { deactivateCalls += 1; isActive = false }
    }

    private func makeState() -> (CommandPanelState, ConfigService) {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(
            diagnostics: diagnostics,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-shell-\(UUID().uuidString).json")
        )
        let registry = CommandRegistry(
            providers: [],
            usageRanking: UsageRankingStore(diagnostics: diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        let state = CommandPanelState(
            registry: registry,
            actionRunner: ActionRunner(diagnostics: diagnostics),
            diagnostics: diagnostics,
            config: config
        )
        return (state, config)
    }

    /// The launcher contract: when the panel dismisses, it must really leave
    /// the screen — an alpha-0 ordered-in window still composites and still
    /// shows up to window-list callers.
    func testHideOrdersPanelOut() async {
        let (state, _) = makeState()
        let activation = FakeActivation()
        let controller = PanelController(
            state: state,
            diagnostics: DiagnosticsService(),
            directPasteService: DirectPasteService(),
            activation: activation,
            otherWindowsVisible: { false }
        )
        controller.show()
        XCTAssertTrue(controller.isVisible, "precondition: panel should be visible after show()")

        controller.hide()
        let orderedOut = await waitForTrue { controller.isVisible == false }
        XCTAssertTrue(orderedOut, "hide() must orderOut — an invisible-but-onscreen panel is a leak")
    }

    func testExecutedHideLeavesTheScreenImmediately() {
        let (state, _) = makeState()
        let controller = PanelController(state: state, diagnostics: DiagnosticsService(), directPasteService: DirectPasteService(),
            activation: FakeActivation(), otherWindowsVisible: { false })
        controller.show()
        XCTAssertTrue(controller.isVisible)
        controller.hide(reason: .executed)
        XCTAssertFalse(controller.isVisible)
    }

    /// Focus goes back to the previously active app when nothing else of ours
    /// is on screen.
    func testHideRestoresFocusWhenNoOtherWindows() async {
        let (state, _) = makeState()
        let activation = FakeActivation()
        let controller = PanelController(
            state: state,
            diagnostics: DiagnosticsService(),
            directPasteService: DirectPasteService(),
            activation: activation,
            otherWindowsVisible: { false }
        )
        controller.show()
        controller.hide()
        let deactivated = await waitForTrue { activation.deactivateCalls > 0 }
        XCTAssertTrue(deactivated, "hide() should deactivate the app so focus returns to the prior app")
    }

    /// But deactivation must not tear down another Foundry window — e.g. the
    /// onboarding flow that stays open while the panel is hidden.
    func testHideKeepsAppActiveWhenOtherWindowVisible() async {
        let (state, _) = makeState()
        let activation = FakeActivation()
        let controller = PanelController(
            state: state,
            diagnostics: DiagnosticsService(),
            directPasteService: DirectPasteService(),
            activation: activation,
            otherWindowsVisible: { true }
        )
        controller.show()
        controller.hide()
        _ = await waitForTrue { controller.isVisible == false }
        XCTAssertEqual(activation.deactivateCalls, 0, "hide() must not hide the app while another window is up")
    }

    private func waitForTrue(timeout: Duration = .seconds(3), _ condition: @escaping () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(16))
        }
        return condition()
    }

    func testToastsShareOneHoldAndErrorsStayLonger() {
        XCTAssertEqual(ActionFeedback.success("Copied").displayDuration, FoundryTheme.Motion.toastHold)
        XCTAssertEqual(ActionFeedback.info("Copied").displayDuration, FoundryTheme.Motion.toastHold)
        XCTAssertGreaterThan(ActionFeedback.failure("No").displayDuration, FoundryTheme.Motion.toastHold)
    }
}