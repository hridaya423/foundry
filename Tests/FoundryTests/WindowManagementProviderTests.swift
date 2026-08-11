import XCTest
@testable import Foundry
import FoundryDomain
import FoundryServices

final class WindowManagementProviderTests: XCTestCase {
    private let provider = WindowManagementProvider()

    func testExposesOneCommandPerPlacement() async throws {
        for placement in WindowPlacement.allCases {
            let results = await provider.results(matching: WindowPlacementMetadata(placement).title)
            let result = try XCTUnwrap(results.first { $0.id == "window.\(placement.rawValue)" },
                                       "Missing command for \(placement)")
            XCTAssertEqual(result.primaryAction.kind, .tileWindow(placement))
        }
    }

    func testRegistryKeepsTheFullCatalogForAnOverviewQuery() async {
        let diagnostics = DiagnosticsService()
        let registry = CommandRegistry(
            providers: [provider],
            usageRanking: UsageRankingStore(diagnostics: diagnostics),
            diagnostics: diagnostics
        )

        let results = await registry.immediateResults(matching: "window")

        XCTAssertEqual(results.count, WindowPlacement.allCases.count)
    }

    func testAliasesResolveToTheExpectedPlacement() async throws {
        let matches: [(query: String, placement: WindowPlacement)] = [
            ("left half", .leftHalf),
            ("tile right", .rightHalf),
            ("max", .maximize),
            ("center window", .center),
            ("undo tile", .restore),
            ("next monitor", .nextDisplay),
            ("grow", .increaseSize),
            ("third right", .rightThird),
            ("top-left", .topLeft),
            ("nudge down", .nudgeDown),
        ]
        for match in matches {
            let results = await provider.results(matching: match.query)
            let result = try XCTUnwrap(results.first { $0.id == "window.\(match.placement.rawValue)" },
                                       "No result for query \(match.query)")
            XCTAssertEqual(result.primaryAction.kind, .tileWindow(match.placement), "Wrong placement for query \(match.query)")
        }
    }

    func testHomeDefaultsSurfaceAsDefaultResults() async throws {
        let results = try await provider.defaultResults()
        XCTAssertEqual(results.map(\.id), WindowPlacement.homeDefaults.map { "window.\($0.rawValue)" })
    }

    func testLayoutOverviewIncludesEveryPlacementForEveryOverviewKeyword() async throws {
        for keyword in ["tile", "window", "layout", "snap"] {
            let results = await provider.results(matching: keyword)
            let placements = results.compactMap { result -> WindowPlacement? in
                guard case let .tileWindow(placement) = result.primaryAction.kind else { return nil }
                return placement
            }

            XCTAssertEqual(Set(placements), Set(WindowPlacement.allCases), "Incomplete layout catalog for \(keyword)")
            XCTAssertEqual(placements.count, WindowPlacement.allCases.count, "Duplicate layout result for \(keyword)")
        }
    }

    func testEveryPlacementProvidesMetadata() {
        for placement in WindowPlacement.allCases {
            let metadata = WindowPlacementMetadata(placement)
            XCTAssertFalse(metadata.title.isEmpty)
            XCTAssertFalse(metadata.subtitle.isEmpty)
            XCTAssertFalse(metadata.successMessage.isEmpty)
            XCTAssertFalse(metadata.icon.isEmpty)
        }
    }

    func testWindowActionsAreFireAndForgetForHotkeys() {
        for placement in WindowPlacement.allCases {
            guard case .tileWindow(let mapped) = CommandActionKind.tileWindow(placement) else {
                XCTFail("Unreachable")
                return
            }
            XCTAssertEqual(mapped, placement)
            XCTAssertTrue(CommandActionKind.tileWindow(placement).shouldHidePanelForHotkey)
        }
    }
}
