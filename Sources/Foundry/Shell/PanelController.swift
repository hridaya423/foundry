import AppKit
import SwiftUI

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
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
        panel?.orderOut(nil)
    }

    private func makePanel() -> FoundryPanel {
        let panel = FoundryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 500),
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

        let rootView = CommandPanelView(state: state) { [weak self] in
            self?.hide()
        }
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 18
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
            y: visibleFrame.midY - size.height / 2 + 72
        )
        panel.setFrameOrigin(origin)
    }
}

final class FoundryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
