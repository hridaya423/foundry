import Foundation

@MainActor
final class CommandPanelState: ObservableObject {
    @Published var query = "" {
        didSet { refreshResults() }
    }
    @Published var results: [CommandResult] = []
    @Published var selectedResultID: String?
    @Published var diagnosticsSummary = "IDLE"

    private let registry: CommandRegistry
    private let actionRunner: ActionRunner
    private let diagnostics: DiagnosticsService
    private var statusTimer: Timer?
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0

    var selectedResult: CommandResult? {
        results.first { $0.id == selectedResultID }
    }

    init(registry: CommandRegistry, actionRunner: ActionRunner, diagnostics: DiagnosticsService) {
        self.registry = registry
        self.actionRunner = actionRunner
        self.diagnostics = diagnostics
        self.statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusSummary()
            }
        }
    }

    func resetForOpen() {
        query = ""
        results = []
        selectedResultID = nil
        refreshStatusSummary(fallback: "READY")
    }

    func handleEscape() -> Bool {
        if query.isEmpty == false {
            query = ""
            return true
        }
        return false
    }

    func executeSelectedResult() {
        guard let selectedResult else { return }
        diagnostics.log("Executing result: \(selectedResult.id)")
        registry.recordExecution(resultID: selectedResult.id)
        actionRunner.perform(selectedResult.primaryAction)
    }

    func select(resultID: String) {
        selectedResultID = resultID
    }

    func moveSelectionDown() {
        moveSelection(offset: 1)
    }

    func moveSelectionUp() {
        moveSelection(offset: -1)
    }

    private func moveSelection(offset: Int) {
        guard results.isEmpty == false else { return }
        let currentIndex = selectedResultID.flatMap { id in results.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), results.count - 1)
        selectedResultID = results[nextIndex].id
    }

    private func refreshResults() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            results = []
            selectedResultID = nil
            refreshStatusSummary(fallback: "READY")
            return
        }

        searchGeneration += 1
        let generation = searchGeneration
        let registry = registry
        let diagnostics = diagnostics
        let span = diagnostics.startSpan("search.async")

        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                diagnostics.endSpan(span)
                return
            }

            guard Task.isCancelled == false else {
                diagnostics.endSpan(span)
                return
            }

            let foundResults = await registry.results(matching: trimmed)
            guard let self,
                  Task.isCancelled == false,
                  self.searchGeneration == generation,
                  self.query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else {
                diagnostics.endSpan(span)
                return
            }

            self.results = foundResults
            self.selectedResultID = foundResults.first?.id
            self.refreshStatusSummary()
            diagnostics.endSpan(span)
        }
    }

    private func refreshStatusSummary(fallback: String = "READY") {
        diagnosticsSummary = registry.statusSummary(resultCount: results.count, fallback: fallback)
    }
}
