import AppKit

@MainActor
enum DownloadNotice {
    private static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    /// Launch-time warning for a copy still running from the disk image,
    /// rendered through the in-panel prompt. The requestPrompt seam must
    /// already be wired; it defaults to decline so nothing modal runs under tests.
    static func showIfNeeded(
        requestPrompt: @MainActor (PanelPromptSpec) async -> PanelPromptResult = { _ in .cancelled }
    ) async {
        guard isTranslocated else { return }
        await showTranslocatedNotice(requestPrompt: requestPrompt)
    }

    private static func showTranslocatedNotice(
        requestPrompt: @MainActor (PanelPromptSpec) async -> PanelPromptResult
    ) async {
        let prompt = await requestPrompt(PanelPromptSpec(
            title: "Move Foundry to Applications",
            message: """
                You're running Foundry straight from the disk image, so macOS is keeping it in a \
                temporary sandbox. Features like launch at login won't work until it's installed. \
                Quit, drag Foundry into Applications from the DMG window, then open it again.
                """,
            confirmLabel: "Quit",
            cancelLabel: "Continue Anyway",
            isDestructive: true
        ))
        if prompt.confirmed {
            NSApp.terminate(nil)
        }
    }
}
