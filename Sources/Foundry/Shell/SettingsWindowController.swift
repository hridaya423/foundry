import AppKit
import SwiftUI

/// The dedicated Settings window — a standard resizable `NSWindow`
/// hosting `SettingsView`. Settings live here, not in the transient
/// launcher, so they survive clicking away to another app. One instance
/// per `ShellController`; the window persists across closes.
@MainActor
final class SettingsWindowController: NSWindowController {
    init(state: CommandPanelState) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Settings")
        window.minSize = NSSize(width: 680, height: 480)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: FoundryIncreaseContrastRoot {
            SettingsView(state: state)
        })
        Self.place(window, autosaveName: "FoundrySettings")
        super.init(window: window)
    }

    static func place(_ window: NSWindow, autosaveName: String) {
        if window.setFrameUsingName(autosaveName) == false { window.center() }
        window.setFrameAutosaveName(autosaveName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Brings the window forward and activates the app — Settings is the
    /// one place Foundry legitimately takes focus.
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
