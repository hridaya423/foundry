import Foundation
import FoundryDomain
import FoundryServices

struct DeleteQuicklinkAction: ResultAction, Equatable {
    let id: String

    var icon: String? { "trash" }
    var style: ActionStyle { .destructive }
    var confirmationMessage: LocalizedStringResource? { "This removes it from Foundry. You can’t undo this." }
    var shortcut: ActionShortcut? { ActionShortcut(key: "x", modifiers: [.control]) }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let store = QuicklinkStore.shared
        let links = store.load()
        guard links.contains(where: { $0.id == id }) else { return .failure(message: String(localized: "Quicklink not found"), retryable: false) }
        do {
            try store.save(links.filter { $0.id != id })
        } catch {
            return ctx.finish(
                .failure(message: String(localized: "Quicklink could not be deleted"), retryable: true),
                 feedback: .failure(String(localized: "Quicklink could not be deleted")))
        }
        return ctx.finish(.refreshResults(message: String(localized: "Quicklink deleted")), feedback: .success(String(localized: "Quicklink deleted")))
    }
}
