import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let state: OnboardingState
    private let keyboard = KeyboardMirror()
    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible == true }

    init(state: OnboardingState) {
        self.state = state
        super.init()
    }

    func show(startAt step: OnboardingStep? = nil) {
        if let step {
            state.go(to: step)
        }
        state.markPresented()
        let window = window ?? makeWindow()
        self.window = window
        keyboard.start()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        _ = FoundryTheme.Brand.registerFonts
        let size = OnboardingView.size
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Welcome to Foundry")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // The brand surface is always dark, like the website.
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(FoundryTheme.Brand.ink)
        window.delegate = self
        let hosting = NSHostingController(rootView: OnboardingView(state: state, keyboard: keyboard))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.contentMinSize = size
        window.contentMaxSize = size
        window.setContentSize(size)
        window.center()
        return window
    }

    func windowDidBecomeKey(_ notification: Notification) {
        keyboard.resync()
    }

    func windowWillClose(_ notification: Notification) {
        keyboard.stop()
        state.abandon()
    }
}
