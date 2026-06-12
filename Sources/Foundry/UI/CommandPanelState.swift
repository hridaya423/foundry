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
    private let diagnostics: DiagnosticsService

    var selectedResult: CommandResult? {
        results.first { $0.id == selectedResultID }
    }

    init(registry: CommandRegistry, diagnostics: DiagnosticsService) {
        self.registry = registry
        self.diagnostics = diagnostics
    }

    func resetForOpen() {
        query = ""
        results = []
        selectedResultID = nil
        diagnosticsSummary = "READY"
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
        selectedResult.primaryAction.perform()
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
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            results = []
            selectedResultID = nil
            diagnosticsSummary = "READY"
            return
        }

        let span = diagnostics.startSpan("search.stub")
        results = registry.results(matching: trimmed)
        selectedResultID = results.first?.id
        diagnosticsSummary = "\(results.count) RESULTS"
        diagnostics.endSpan(span)
    }
}
