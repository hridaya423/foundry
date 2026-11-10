import AppKit
import SwiftUI

/// The dedicated Settings window — a standard resizable `NSWindow`
/// hosting `SettingsView`. Settings live here, not in the transient
/// launcher, so they survive clicking away to another app. One instance
/// per `ShellController`; the window persists across closes.
@MainActor
final class SettingsWindowController: NSWindowController {
    init(state: CommandPanelState) {
        let window = Self.makeWindow(rootView: SettingsView(state: state))
        Self.place(window, autosaveName: "FoundrySettings")
        super.init(window: window)
    }

    static func makeWindow(rootView: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Settings")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        let minimum = NSSize(width: 720, height: 560)
        window.minSize = minimum
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(FoundryTheme.windowGround)
        // A hosting view replaces the window's `minSize` with the SwiftUI content's own minimum on first layout, so the content states it too.
        let content = NSHostingView(rootView: FoundryIncreaseContrastRoot { rootView }
            .frame(minWidth: minimum.width, minHeight: minimum.height))
        content.safeAreaRegions = []
        window.contentView = content
        return window
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
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
