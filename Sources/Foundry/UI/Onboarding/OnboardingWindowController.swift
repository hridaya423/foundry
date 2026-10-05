import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let state: OnboardingState
    private var window: NSWindow?

    init(state: OnboardingState) {
        self.state = state
        super.init()
    }

    func show(startAt step: OnboardingStep? = nil) {
        if let step {
            state.go(to: step)
        }
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 580),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Foundry"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        let size = NSSize(width: 800, height: 580)
        let hosting = NSHostingController(rootView: OnboardingView(state: state).frame(width: size.width, height: size.height))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.contentMinSize = size
        window.contentMaxSize = size
        window.setContentSize(size)
        window.center()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        state.stopWaitingForSpotlight()
    }
}
