import XCTest
@testable import Foundry
import FoundryDomain

final class ResultSectionTests: XCTestCase {
    private func result(_ id: String, _ behavior: any ResultAction) -> CommandResult {
        CommandResult(id: id, title: id, subtitle: nil, icon: CommandIcon(fallback: "X"), payload: .command, primaryAction: CommandAction(id: "\(id).open", title: "Open", behavior: behavior), secondaryActions: [])
    }

    func testTopHitLeadsItsNaturalSectionWhichRendersFirst() {
        let ranked = [
            result("cmd.clipboard", OpenClipboardHistoryAction()),
            result("app.com.apple.Safari", OpenAppAction(path: "/Applications/Safari.app", name: "Safari")),
            result("cmd.shelf", OpenFileShelfAction()),
            result("app.com.apple.Notes", OpenAppAction(path: "/Applications/Notes.app", name: "Notes"))
        ]

        let groups = ResultSection.group(ranked)

        XCTAssertEqual(groups.map(\.section), [.commands, .applications])
        XCTAssertEqual(groups.first?.results.map(\.id), ["cmd.clipboard", "cmd.shelf"])
        XCTAssertEqual(groups[1].results.map(\.id), ["app.com.apple.Safari", "app.com.apple.Notes"])
    }

    func testAIFallbackNeverBecomesTopHitWhenRealResultsExist() {
        let ranked = [
            result("ai", OpenQuickAIAction(prompt: "saf")),
            result("app.com.apple.Safari", OpenAppAction(path: "/Applications/Safari.app", name: "Safari"))
        ]

        XCTAssertEqual(ResultSection.ordered(ranked).map(\.id), ["app.com.apple.Safari", "ai"])
    }

    func testOrderingIsStableWhenReappliedSoNavigationMatchesTheRenderedSections() {
        let ranked = [
            result("ai", OpenQuickAIAction(prompt: "x")),
            result("cmd.a", OpenFileShelfAction()),
            result("app.a", OpenAppAction(path: "/a.app", name: "A")),
            result("cmd.b", OpenClipboardHistoryAction())
        ]
        let ordered = ResultSection.ordered(ranked)

        XCTAssertEqual(ResultSection.ordered(ordered), ordered)
        XCTAssertEqual(ResultSection.group(ordered).flatMap(\.results), ordered)
    }

    func testSingleResultHasOneSectionAndEmptyHasNone() {
        XCTAssertTrue(ResultSection.group([]).isEmpty)
        XCTAssertEqual(ResultSection.group([result("ai", OpenQuickAIAction(prompt: "x"))]).count, 1)
    }
}
