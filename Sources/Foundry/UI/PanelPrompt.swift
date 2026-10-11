import AppKit
import Foundation

/// Specification for an in-panel prompt — the PanelForm/ConfirmBar
/// replacement for NSAlert. Built by actions, rendered by
/// `CommandPanelView`, resolved through `CommandPanelState.requestPrompt`.
struct PanelPromptSpec {
    var title: String
    var message: String?
    var fields: [Field] = []
    var picker: Picker?
    var image: NSImage?
    var confirmLabel: String
    var cancelLabel: String?
    var isDestructive = false

    /// A labeled single-line input.
    struct Field: Identifiable {
        let id: String
        let placeholder: String
        var isSecure = false
        var initial = ""
    }

    /// One labeled option row rendered as a segmented picker.
    struct Picker {
        let id: String
        let options: [String]
        var selected: Int
    }

    /// Confirm/cancel-only prompt (ConfirmBar).
    static func confirmation(
        title: String,
        message: String? = nil,
        confirmLabel: String,
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
