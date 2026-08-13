import XCTest
@testable import Foundry
import FoundryDomain
import FoundryServices

final class PerformanceRegressionTests: XCTestCase {
    func testSearchScoringHandlesARepresentativeCatalog() {
        let catalog = (0..<2_000).map { index in
            (title: "Developer Command \(index)", subtitle: "Foundry utility", keywords: ["command", "developer"])
        }
        var matches = 0

        measure {
            matches = catalog.reduce(into: 0) { count, item in
                if SearchScoring.match(query: "developer command", title: item.title, subtitle: item.subtitle, keywords: item.keywords, aliases: []) != nil {
                    count += 1
                }
            }
        }

        XCTAssertEqual(matches, catalog.count)
    }

    func testClipboardHistoryPolicyBoundsRepresentativeHistory() {
        let policy = ClipboardHistoryPolicy()
        let items = (0..<policy.maxItems).map { index in
            ClipboardHistoryItem(
                payload: .text(String(repeating: "x", count: 512 * 1024)),
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let retained = policy.bounded(items)
        let total = retained.reduce(0) { $0 + $1.memoryCost }

        XCTAssertLessThanOrEqual(total, policy.maxBytes)
        XCTAssertLessThanOrEqual(retained.count, policy.maxItems)
    }

    func testHomePollingWorkload() async throws {
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-home-profile-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config = ConfigService(diagnostics: DiagnosticsService(), url: configURL)
        let board = await MainActor.run { WidgetBoardState(configService: config) }

        await MainActor.run { board.start() }
        try await Task.sleep(for: .seconds(6))
        await MainActor.run { board.stop() }

        let memoryTotal = await MainActor.run { board.metrics.memoryTotal }
        XCTAssertGreaterThan(memoryTotal, 0)
    }

    func testCommandRegistrySearchWorkload() async throws {
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-search-profile-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: configURL) }
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: configURL)
        let registry = CommandRegistry.defaultRegistry(config: config, diagnostics: diagnostics)
        let queries = ["calc", "developer", "system", "open"]

        var resultCount = 0
        for query in queries {
            resultCount += await registry.results(matching: query).count
        }

        XCTAssertGreaterThan(resultCount, 0)
    }
}
