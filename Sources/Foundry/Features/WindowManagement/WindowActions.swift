import Foundation
import FoundryDomain
import FoundryServices

struct TileWindowAction: ResultAction, Equatable {
    let placement: WindowPlacement

    init(_ placement: WindowPlacement) { self.placement = placement }

    var icon: String? { "rectangle.split.2x1" }
    var hidesPanelForHotkey: Bool { true }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        switch await ctx.windowManager.apply(placement) {
        case let .tiled(resultPlacement):
            let message = WindowPlacementMetadata(resultPlacement).successMessage
            return ctx.finish(.success(message: message), feedback: .success(message))
        case let .constrained(resultPlacement):
            let message = String(localized: "Window was constrained while applying \(WindowPlacementMetadata(resultPlacement).title.lowercased())")
            return ctx.finish(.success(message: message), feedback: .info(message))
        case .restored:
            return ctx.finish(
                .success(message: String(localized: "Restored previous window frame")),
                 feedback: .success(String(localized: "Restored previous window frame")))
        case .needsAccessibilityPermission:
            let answer = await ctx.panel.requestPrompt(PanelPromptSpec(
                title: "Allow Accessibility to arrange windows.",
                message: "Foundry moves and resizes the frontmost window. Nothing else.",
                confirmLabel: "Allow",
                cancelLabel: "Not Now"))
            if answer.confirmed { await ctx.panel.requestPermission(.accessibility) }
            return .stayOpen(message: String(localized: "Accessibility permission required for window control"))
        case let .failed(message):
            return ctx.finish(.failure(message: message, retryable: false), feedback: .failure(message))
        }
    }
}
