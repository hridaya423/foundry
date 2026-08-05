import Foundation
import FoundryDomain
import FoundryServices

@MainActor
final class CommandSearchCoordinator {
    typealias ResultsHandler = ([CommandResult]) -> Void

    private let registry: CommandRegistry
    private let diagnostics: DiagnosticsService
    private var task: Task<Void, Never>?
    private var generation = 0

    init(registry: CommandRegistry, diagnostics: DiagnosticsService) {
        self.registry = registry
        self.diagnostics = diagnostics
    }

    func search(
        query: String,
        onImmediate: @escaping ResultsHandler,
        onComplete: @escaping ResultsHandler
    ) {
        cancel()
        generation += 1
        let currentGeneration = generation
        let registry = registry
        let diagnostics = diagnostics

        task = Task { [weak self] in
            let span = diagnostics.startSpan("search.async")
            defer { diagnostics.endSpan(span) }
            do {
                try await Task.sleep(for: .milliseconds(40))
            } catch {
                return
            }
            guard Task.isCancelled == false else { return }

            let immediatePhase = await registry.immediateSearchPhase(matching: query)
            guard let self, self.isCurrent(currentGeneration) else { return }
            onImmediate(immediatePhase.results)

            let completeResults = await registry.completeResults(
                matching: query,
                initialResults: immediatePhase.results,
                completedProviderIDs: immediatePhase.completedProviderIDs
            )
            guard Task.isCancelled == false, self.isCurrent(currentGeneration) else { return }
            onComplete(completeResults)
        }
    }

    func loadHome(onResults: @escaping ResultsHandler) {
        cancel()
        generation += 1
        let currentGeneration = generation
        let registry = registry
        let diagnostics = diagnostics

        task = Task { [weak self] in
            let span = diagnostics.startSpan("search.home")
            defer { diagnostics.endSpan(span) }
            let results = await registry.homeResults()
            guard let self, Task.isCancelled == false, self.generation == currentGeneration else { return }
            onResults(results)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
    }

    private func isCurrent(_ generation: Int) -> Bool {
        self.generation == generation && task?.isCancelled == false
    }
}
