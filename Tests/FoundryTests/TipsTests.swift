import XCTest
@testable import Foundry

final class TipsTests: XCTestCase {
    func testNoTipBeforeFiveLaunches() {
        XCTAssertNil(Tip.today(launchCount: 4, day: "2026-11-01", shownDay: nil, shownID: nil, dismissed: []))
        XCTAssertEqual(Tip.today(launchCount: 5, day: "2026-11-01", shownDay: nil, shownID: nil, dismissed: [])?.id, Tip.all[0].id)
    }

    func testOneTipPerDay() {
        let first = Tip.all[0].id
        XCTAssertEqual(Tip.today(launchCount: 9, day: "2026-11-01", shownDay: "2026-11-01", shownID: first, dismissed: [])?.id, first)
        XCTAssertEqual(Tip.today(launchCount: 9, day: "2026-11-02", shownDay: "2026-11-01", shownID: first, dismissed: [])?.id, Tip.all[1].id)
    }

    func testDismissedTipNeverReturns() {
        let first = Tip.all[0].id
        XCTAssertNil(Tip.today(launchCount: 9, day: "2026-11-01", shownDay: "2026-11-01", shownID: first, dismissed: [first]))
        XCTAssertEqual(Tip.today(launchCount: 9, day: "2026-11-02", shownDay: "2026-11-01", shownID: first, dismissed: [first])?.id,
            Tip.all[1].id)
        XCTAssertNil(Tip.today(launchCount: 9, day: "2026-11-09", shownDay: nil, shownID: nil, dismissed: Set(Tip.all.map(\.id))))
    }

    func testAtMostFiveTips() {
        XCTAssertLessThanOrEqual(Tip.all.count, 5)
    }
}
