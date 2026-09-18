@testable import Foundry

extension CommandRegistry {
    func fullResults(matching query: String) async -> [CommandResult] {
        let phase = await immediateSearchPhase(matching: query)
        return await completeResults(matching: query, initialResults: phase.results, completedProviderIDs: phase.completedProviderIDs)
    }
}
