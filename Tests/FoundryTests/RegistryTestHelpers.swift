import Foundation
import FoundryServices
@testable import Foundry

extension CommandRegistry {
    func fullResults(matching query: String) async -> [CommandResult] {
        let phase = await immediateSearchPhase(matching: query)
        return await completeResults(matching: query, initialResults: phase.results, completedProviderIDs: phase.completedProviderIDs)
    }
}

extension UsageRankingStore {
    static func scratch(_ diagnostics: DiagnosticsService) -> UsageRankingStore {
        UsageRankingStore(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString).json"))
    }
}
