import Foundation
import FoundryServices

@MainActor
final class CommandSearchCoordinator {
    typealias ResultsHandler = ([CommandResult]) -> Void

    private let registry: CommandRegistry
    private let diagnostics: DiagnosticsService
    private var task: Task<Void, Never>?
    private var generation = 0
    private var searchInFlight = false
    private var immediateSpan: DiagnosticsService.Span?
    private var completeSpan: DiagnosticsService.Span?

    init(registry: CommandRegistry, diagnostics: DiagnosticsService) {
        self.registry = registry
        self.diagnostics = diagnostics
    }

    func search(
        query: String,
        onImmediate: @escaping ResultsHandler,
        onComplete: @escaping ResultsHandler
    ) {
        let coalesce = searchInFlight
        cancel()
        generation += 1
        searchInFlight = true
        let currentGeneration = generation
        let registry = registry
        let diagnostics = diagnostics
        immediateSpan = diagnostics.startSpan("search.immediate")
        completeSpan = diagnostics.startSpan("search.complete")

        task = Task { [weak self] in
            let span = diagnostics.startSpan("search.async")
            defer { diagnostics.endSpan(span) }
            if coalesce {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
            guard Task.isCancelled == false else { return }

            let immediatePhase = await registry.immediateSearchPhase(matching: query)
            guard let self, self.isCurrent(currentGeneration) else { return }
            if let immediateSpan = self.immediateSpan {
                diagnostics.endSpan(immediateSpan)
                self.immediateSpan = nil
            }

            let phase2Span = diagnostics.startSpan("search.phase2")
            async let completeTask = registry.completeResults(
                matching: query,
                initialResults: immediatePhase.results,
                completedProviderIDs: immediatePhase.completedProviderIDs
            )
            onImmediate(immediatePhase.results)
            let completeResults = await completeTask
            diagnostics.endSpan(phase2Span)
            guard Task.isCancelled == false, self.isCurrent(currentGeneration) else { return }
            if let completeSpan = self.completeSpan {
                diagnostics.endSpan(completeSpan)
                self.completeSpan = nil
            }
            self.searchInFlight = false
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
        searchInFlight = false
        generation += 1
        if let immediateSpan {
            diagnostics.discardSpan(immediateSpan)
            self.immediateSpan = nil
        }
        if let completeSpan {
            diagnostics.discardSpan(completeSpan)
            self.completeSpan = nil
        }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        self.generation == generation && task?.isCancelled == false
    }
}
