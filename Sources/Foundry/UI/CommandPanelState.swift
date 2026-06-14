import Foundation

@MainActor
final class CommandPanelState: ObservableObject {
    enum Mode {
        case search
        case activityMonitor
    }

    @Published var query = "" {
        didSet { refreshResults() }
    }
    @Published var results: [CommandResult] = []
    @Published var selectedResultID: String?
    @Published var isShowingActions = false
    @Published var selectedActionID: String?
    @Published var diagnosticsSummary = "IDLE"
    @Published var mode: Mode = .search

    let activityMonitor = ActivityMonitorState()

    private let registry: CommandRegistry
    private let actionRunner: ActionRunner
    private let diagnostics: DiagnosticsService
    private var statusTimer: Timer?
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0

    var selectedResult: CommandResult? {
        results.first { $0.id == selectedResultID }
    }

    var selectedActions: [CommandAction] {
        guard let selectedResult else { return [] }
        return [selectedResult.primaryAction] + selectedResult.secondaryActions
    }

    var selectedAction: CommandAction? {
        selectedActions.first { $0.id == selectedActionID }
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
        mode = .search
        activityMonitor.stop()
        query = ""
        results = []
        selectedResultID = nil
        isShowingActions = false
        selectedActionID = nil
        refreshStatusSummary(fallback: "READY")
    }

    func panelWillClose() {
        activityMonitor.stop()
    }

    func handleEscape() -> Bool {
        return false
    }

    func backToSearch() {
        mode = .search
        activityMonitor.stop()
        query = ""
        results = []
        selectedResultID = nil
        isShowingActions = false
        selectedActionID = nil
        refreshStatusSummary(fallback: "READY")
    }

    @discardableResult
    func executeSelectedResult() -> Bool {
        guard let selectedResult else { return false }
        if isShowingActions, let selectedAction {
            diagnostics.log("Executing action: \(selectedAction.id)")
            registry.recordExecution(resultID: selectedResult.id)
            actionRunner.perform(selectedAction)
            return true
        }

        diagnostics.log("Executing result: \(selectedResult.id)")
        registry.recordExecution(resultID: selectedResult.id)
        if selectedResult.primaryAction.kind == .openActivityMonitor {
            openActivityMonitor()
            return false
        }
        actionRunner.perform(selectedResult.primaryAction)
        return true
    }

    func select(resultID: String) {
        selectedResultID = resultID
        if isShowingActions {
            selectedActionID = selectedActions.first?.id
        }
    }

    func select(actionID: String) {
        selectedActionID = actionID
    }

    func toggleActions() {
        guard selectedResult != nil else {
            diagnostics.log("No selected result for actions")
            return
        }
        isShowingActions.toggle()
        selectedActionID = isShowingActions ? selectedActions.first?.id : nil
    }

    func moveSelectionDown() {
        moveSelection(offset: 1)
    }

    func moveSelectionUp() {
        moveSelection(offset: -1)
    }

    private func moveSelection(offset: Int) {
        if mode == .activityMonitor {
            activityMonitor.moveSelection(offset: offset)
            return
        }

        if isShowingActions {
            let actions = selectedActions
            guard actions.isEmpty == false else { return }
            let currentIndex = selectedActionID.flatMap { id in actions.firstIndex { $0.id == id } } ?? 0
            let nextIndex = min(max(currentIndex + offset, 0), actions.count - 1)
            selectedActionID = actions[nextIndex].id
            return
        }

        guard results.isEmpty == false else { return }
        let currentIndex = selectedResultID.flatMap { id in results.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), results.count - 1)
        selectedResultID = results[nextIndex].id
    }

    private func refreshResults() {
        guard mode == .search else { return }
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        isShowingActions = false
        selectedActionID = nil
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

    private func openActivityMonitor() {
        mode = .activityMonitor
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        activityMonitor.reset()
        activityMonitor.start()
        diagnosticsSummary = "activity monitor"
    }
}
