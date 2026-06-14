import AppKit
import SwiftUI

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private static let panelSize = NSSize(width: 760, height: 500)

    private let state: CommandPanelState
    private let diagnostics: DiagnosticsService
    private var panel: FoundryPanel?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    init(state: CommandPanelState, diagnostics: DiagnosticsService) {
        self.state = state
        self.diagnostics = diagnostics
        super.init()
    }

    func show() {
        let span = diagnostics.startSpan("panel.show")
        let panel = panel ?? makePanel()
        self.panel = panel

        position(panel)
        panel.makeKeyAndOrderFront(nil)
        diagnostics.endSpan(span)
    }

    func hide() {
        state.panelWillClose()
        panel?.orderOut(nil)
    }

    private func makePanel() -> FoundryPanel {
        let panel = FoundryPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.onCommandK = { [weak self] in
            self?.state.toggleActions()
        }

        let rootView = CommandPanelView(state: state) { [weak self] in
            self?.hide()
        }
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 28
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView

        return panel
    }

    private func position(_ panel: NSWindow) {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let visibleFrame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}

@MainActor
final class FoundryPanel: NSPanel {
    var onCommandK: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handlesCommandK(event) {
            onCommandK?()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handlesCommandK(event) {
            onCommandK?()
            return
        }

        super.keyDown(with: event)
    }

    private func handlesCommandK(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags == .command && event.charactersIgnoringModifiers?.lowercased() == "k"
    }
}
