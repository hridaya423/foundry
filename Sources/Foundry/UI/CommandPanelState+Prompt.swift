import Foundation

// In-panel prompts (ConfirmBar/PanelForm): actions request a spec, the
// overlay resolves it asynchronously. Modal UI never runs under tests —
// the default PanelPorts prompt returns `.cancelled`.
extension CommandPanelState {
    /// Presents a prompt and suspends until the user answers or the panel
    /// lifecycle cancels it. The panel is raised first when hidden — a
    /// confirmation can arrive from a hotkey-invoked action.
    func requestPrompt(_ spec: PanelPromptSpec) async -> PanelPromptResult {
        shell?.ensurePanelVisible()
        cancelPrompt()
        return await withCheckedContinuation { continuation in
            pendingPrompt = PendingPrompt(spec: spec) { result in
                continuation.resume(returning: result)
            }
        }
    }

    func resolvePrompt(_ result: PanelPromptResult) {
        guard let prompt = pendingPrompt else { return }
        pendingPrompt = nil
        prompt.resume(result)
    }

    func cancelPrompt() {
        resolvePrompt(.cancelled)
    }

    func searchFooterActions(isWindowLayoutQuery: Bool) -> [FooterActionSpec] {
        if let prompt = pendingPrompt {
            return [
                .init(label: prompt.spec.confirmLabel, keys: "↵", emphasized: true),
                .init(label: prompt.spec.cancelLabel ?? "Cancel", keys: "esc"),
            ]
        }
        if session.isShowingActions {
            return [
                .init(label: session.selectedAction.map { LocalizedStringResource("\($0.title)") } ?? "Run", keys: "↵", emphasized: true),
                .init(label: "Back", keys: "esc"),
            ]
        }
        if isWindowLayoutQuery {
            return [.init(label: "Apply", keys: "↵", emphasized: true), .actions]
        }
        guard let title = session.preferredActionTitle else { return [] }
        return [.init(label: LocalizedStringResource("\(title)"), keys: "↵", emphasized: true), .actions]
    }
}
