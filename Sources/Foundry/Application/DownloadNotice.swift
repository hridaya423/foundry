import AppKit
import Darwin
import Foundation

@MainActor
enum DownloadNotice {
    private static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    private static var isQuarantined: Bool {
        Bundle.main.bundlePath.withCString { getxattr($0, "com.apple.quarantine", nil, 0, 0, 0) >= 0 }
    }

    /// Launch-time download warnings rendered through the in-panel prompt.
    /// The requestPrompt seam must already be wired (call after the shell
    /// starts); it defaults to decline so nothing modal runs under tests.
    static func showIfNeeded(
        localState: LocalStateStore = .shared,
        requestPrompt: @MainActor (PanelPromptSpec) async -> PanelPromptResult = { _ in .cancelled }
    ) async {
        if isTranslocated {
            await showTranslocatedNotice(requestPrompt: requestPrompt)
            return
        }
        guard isQuarantined, localState.get(\.downloadedNoticeShown) == false else { return }
        let prompt = await requestPrompt(PanelPromptSpec(
            title: "Foundry isn't notarized yet",
            message: """
                You downloaded Foundry directly, so macOS may warn that the developer can't be verified. \
                That's expected for this build — if it refuses to open now or after an update, go to \
                System Settings → Privacy & Security → Security → Open Anyway.
                """,
            confirmLabel: "Open Privacy & Security",
            cancelLabel: "Dismiss"
        ))
        localState.set(\.downloadedNoticeShown, true)
        if prompt.confirmed,
           let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") {
            NSWorkspace.shared.open(url)
        }
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
