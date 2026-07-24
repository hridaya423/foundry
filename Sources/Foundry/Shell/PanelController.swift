import AppKit
import Combine
import SwiftUI

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private static let rootSize = NSSize(width: 750, height: 495)
    private static let expandedSize = NSSize(width: 750, height: 625)

    private let state: CommandPanelState
    private let diagnostics: DiagnosticsService
    private var panel: FoundryPanel?
    private var modeCancellable: AnyCancellable?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    init(state: CommandPanelState, diagnostics: DiagnosticsService) {
        self.state = state
        self.diagnostics = diagnostics
        super.init()
        modeCancellable = state.$mode.sink { [weak self] mode in
            Task { @MainActor [weak self] in
                self?.resize(for: mode)
            }
        }
    }

    func show() {
        let span = diagnostics.startSpan("panel.show")
        let panel = panel ?? makePanel()
        self.panel = panel

        resize(for: state.mode)
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
            contentRect: NSRect(origin: .zero, size: Self.rootSize),
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
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.onCommandK = { [weak self] in
            self?.state.toggleActions()
        }
        panel.onCommandComma = { [weak self] in
            self?.state.openSettings()
        }
        panel.onCommandV = { [weak self] in
            self?.state.pasteFromClipboard() ?? false
        }
        panel.onAskAI = { [weak self] in
            guard let self, self.state.mode == .search else { return }
            self.state.openQuickAI(initialPrompt: self.state.query)
        }

        let rootView = CommandPanelView(state: state) { [weak self] in
            self?.hide()
        }
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        panel.contentView = hostingView

        return panel
    }

    private func resize(for mode: CommandPanelState.Mode) {
        guard let panel else { return }
        panel.setContentSize(Self.contentSize(for: mode))
        position(panel)
    }

    static func contentSize(for mode: CommandPanelState.Mode) -> NSSize {
        mode == .search || mode == .quickAI ? rootSize : expandedSize
    }

    private func position(_ panel: NSWindow) {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let visibleFrame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let topOffsetPixels: CGFloat = 280
        let topInset = topOffsetPixels / max(screen?.backingScaleFactor ?? 1, 1)
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: max(visibleFrame.minY, visibleFrame.maxY - size.height - topInset)
        )
        panel.setFrameOrigin(origin)
    }
}

@MainActor
final class FoundryPanel: NSPanel {
    var onCommandK: (() -> Void)?
    var onCommandComma: (() -> Void)?
    var onCommandV: (() -> Bool)?
    var onAskAI: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleShortcut(event) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleShortcut(event) {
            return
        }

        super.keyDown(with: event)
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        if event.keyCode == 48, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            onAskAI?()
            return true
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "k":
            onCommandK?()
            return true
        case ",":
            onCommandComma?()
            return true
        case "q":
            NSApp.terminate(nil)
            return true
        case "v":
            return onCommandV?() ?? false
        default:
            return false
        }
    }
}
