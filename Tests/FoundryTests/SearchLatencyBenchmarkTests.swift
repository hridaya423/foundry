import XCTest
@testable import Foundry
import FoundryServices

@MainActor
final class SearchLatencyBenchmarkTests: XCTestCase {
    func testTypingLatencyThroughDefaultRegistry() async throws {
        guard let out = ProcessInfo.processInfo.environment["FOUNDRY_BENCH_OUT"] else { throw XCTSkip("set FOUNDRY_BENCH_OUT") }
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("bench-\(UUID().uuidString).json"))
        let registry = CommandRegistry.defaultRegistry(config: config, diagnostics: diagnostics)
        let coordinator = CommandSearchCoordinator(registry: registry, diagnostics: diagnostics)
        _ = await registry.homeResults()

        let queries = ["saf", "calc", "clip", "wifi", "12*34", "term", "note", "emoji"]
        let rounds = Int(ProcessInfo.processInfo.environment["FOUNDRY_BENCH_ROUNDS"] ?? "") ?? 4
        var immediate: [Double] = []
        var complete: [Double] = []
        for round in 0..<(rounds + 1) {
            for query in queries {
                for length in 1...query.count {
                    let start = ContinuousClock.now
                    let record = round > 0
                    coordinator.search(
                        query: String(query.prefix(length)),
                        onImmediate: { _ in if record { immediate.append(Self.ms(ContinuousClock.now - start)) } },
                        onComplete: { _ in if record { complete.append(Self.ms(ContinuousClock.now - start)) } }
                    )
                    try await Task.sleep(for: .milliseconds(90))
                }
                try await Task.sleep(for: .milliseconds(400))
            }
        }
        coordinator.cancel()

        let report: [String: Any] = [
            "driver": "Tests/FoundryTests/SearchLatencyBenchmarkTests.swift (in-process, default registry, 90 ms keystrokes, first round warm-up)",
            "unit": "ms",
            "search.immediate": Self.summary(immediate),
            "search.complete": Self.summary(complete)
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: out))
        XCTAssertFalse(immediate.isEmpty)
    }

    private static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    private static func summary(_ values: [Double]) -> [String: Double] {
        let sorted = values.sorted()
        func pct(_ p: Double) -> Double { sorted.isEmpty ? 0 : (sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))] * 100).rounded() / 100 }
        return ["n": Double(sorted.count), "p50": pct(0.5), "p95": pct(0.95), "max": pct(1)]
    }
}
