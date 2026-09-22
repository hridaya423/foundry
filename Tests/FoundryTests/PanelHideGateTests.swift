import XCTest
@testable import Foundry

final class PanelHideGateTests: XCTestCase {
    func testShowCancelsPendingHideCompletion() {
        var gate = PanelHideGate()
        let stale = gate.beginHide()
        gate.cancelPendingHide()
        XCTAssertFalse(gate.allowsCompletion(for: stale))
    }

    func testLatestHideCompletes() {
        var gate = PanelHideGate()
        let generation = gate.beginHide()
        XCTAssertTrue(gate.allowsCompletion(for: generation))
    }

    func testNewerHideInvalidatesOlderGeneration() {
        var gate = PanelHideGate()
        let first = gate.beginHide()
        let second = gate.beginHide()
        XCTAssertFalse(gate.allowsCompletion(for: first))
        XCTAssertTrue(gate.allowsCompletion(for: second))
    }
}
