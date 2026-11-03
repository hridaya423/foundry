import AppKit
import Foundation

/// Specification for an in-panel prompt — the PanelForm/ConfirmBar
/// replacement for NSAlert. Built by actions, rendered by
/// `CommandPanelView`, resolved through `CommandPanelState.requestPrompt`.
struct PanelPromptSpec {
    var title: LocalizedStringResource
    var message: LocalizedStringResource?
    var fields: [Field] = []
    var picker: Picker?
    var image: NSImage?
    var confirmLabel: LocalizedStringResource
    var cancelLabel: LocalizedStringResource?
    var isDestructive = false

    /// A labeled single-line input.
    struct Field: Identifiable {
        let id: String
        let placeholder: LocalizedStringResource
        var isSecure = false
        var initial = ""
    }

    /// One labeled option row rendered as a segmented picker.
    struct Picker {
        let id: String
        let options: [LocalizedStringResource]
        var selected: Int
    }

    /// Confirm/cancel-only prompt (ConfirmBar).
    static func confirmation(
        title: LocalizedStringResource,
        message: LocalizedStringResource? = nil,
        confirmLabel: LocalizedStringResource,
        isDestructive: Bool = false
    ) -> PanelPromptSpec {
        PanelPromptSpec(
            title: title,
            message: message,
            confirmLabel: confirmLabel,
            cancelLabel: "Cancel",
            isDestructive: isDestructive
        )
    }
}

/// What the user left behind when the prompt closed.
struct PanelPromptResult: Sendable {
    var confirmed: Bool
    /// Field values in declaration order.
    var texts: [String] = []
    /// Picker selection index, or -1 when the spec had no picker.
    var selection: Int = -1

    static let cancelled = PanelPromptResult(confirmed: false)
}

/// A spec plus the continuation waiting on the user's answer.
struct PendingPrompt {
    let spec: PanelPromptSpec
    let resume: (PanelPromptResult) -> Void
}
