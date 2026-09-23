import XCTest
@testable import Foundry
import FoundryDomain

final class ResultSectionTests: XCTestCase {
    private func result(_ id: String, _ kind: CommandActionKind) -> CommandResult {
        CommandResult(id: id, title: id, subtitle: nil, icon: CommandIcon(fallback: "X"), primaryAction: CommandAction(id: "\(id).open", title: "Open", kind: kind), secondaryActions: [])
    }

    func testTopHitLeadsItsNaturalSectionWhichRendersFirst() {
        let ranked = [
            result("cmd.clipboard", .openClipboardHistory),
            result("app.com.apple.Safari", .openApp(path: "/Applications/Safari.app", name: "Safari")),
            result("cmd.shelf", .openFileShelf),
            result("app.com.apple.Notes", .openApp(path: "/Applications/Notes.app", name: "Notes"))
        ]

        let groups = ResultSection.group(ranked)

        XCTAssertEqual(groups.map(\.section), [.commands, .applications])
        XCTAssertEqual(groups.first?.results.map(\.id), ["cmd.clipboard", "cmd.shelf"])
        XCTAssertEqual(groups[1].results.map(\.id), ["app.com.apple.Safari", "app.com.apple.Notes"])
    }

    func testAIFallbackNeverBecomesTopHitWhenRealResultsExist() {
        let ranked = [
            result("ai", .openQuickAI(prompt: "saf")),
            result("app.com.apple.Safari", .openApp(path: "/Applications/Safari.app", name: "Safari"))
        ]

        XCTAssertEqual(ResultSection.ordered(ranked).map(\.id), ["app.com.apple.Safari", "ai"])
    }

    func testOrderingIsStableWhenReappliedSoNavigationMatchesTheRenderedSections() {
        let ranked = [
            result("ai", .openQuickAI(prompt: "x")),
            result("cmd.a", .openFileShelf),
            result("app.a", .openApp(path: "/a.app", name: "A")),
            result("cmd.b", .openCamera)
        ]
        let ordered = ResultSection.ordered(ranked)

        XCTAssertEqual(ResultSection.ordered(ordered), ordered)
        XCTAssertEqual(ResultSection.group(ordered).flatMap(\.results), ordered)
    }

    func testSingleResultHasOneSectionAndEmptyHasNone() {
        XCTAssertTrue(ResultSection.group([]).isEmpty)
        XCTAssertEqual(ResultSection.group([result("ai", .openQuickAI(prompt: "x"))]).count, 1)
    }
}
