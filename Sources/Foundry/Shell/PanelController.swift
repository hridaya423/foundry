import AppKit
import SwiftUI
import FoundryServices

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private static let rootSize = NSSize(width: 750, height: 495)

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

        state.hoverHighlightsArmed = false
        panel.setFrame(frame(for: panel), display: false)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak panel] in
            guard let panel, panel.isVisible, panel.isKeyWindow == false else { return }
            panel.makeKeyAndOrderFront(nil)
        }
        diagnostics.endSpan(span)
    }

    func hide() {
        state.panelWillClose()
        panel?.orderOut(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel?.isVisible == true else { return }
            self.state.focusToken = UUID()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let panel, panel.isVisible else { return }
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, panel.isVisible, panel.isKeyWindow == false else { return }
            guard PanelDismissalPolicy.shouldDismiss(
                hasAttachedSheet: panel.attachedSheet != nil,
                hasChildWindows: panel.childWindows?.isEmpty == false,
                hasModalWindow: NSApp.modalWindow != nil
            ) else { return }
            self.hide()
        }
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
        panel.acceptsMouseMovedEvents = true
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
        panel.onMouseMoved = { [weak self] in
            self?.state.hoverHighlightsArmed = true
        }
        panel.onKeyDown = { [weak self] in
            self?.state.hoverHighlightsArmed = false
        }

        let rootView = CommandPanelView(state: state) { [weak self] in
            self?.hide()
        }
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        return panel
    }

    static func contentSize(for _: CommandPanelState.Mode) -> NSSize {
        rootSize
    }

    private func frame(for panel: NSWindow) -> NSRect {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let visibleFrame = screen?.visibleFrame else { return panel.frame }
        let topOffsetPixels: CGFloat = 280
        let topInset = topOffsetPixels / max(screen?.backingScaleFactor ?? 1, 1)
        let origin = CGPoint(
            x: visibleFrame.midX - Self.rootSize.width / 2,
            y: max(visibleFrame.minY, visibleFrame.maxY - Self.rootSize.height - topInset)
        )
        return NSRect(origin: origin, size: Self.rootSize)
    }
}

enum PanelDismissalPolicy {
    static func shouldDismiss(hasAttachedSheet: Bool, hasChildWindows: Bool, hasModalWindow: Bool) -> Bool {
        hasAttachedSheet == false && hasChildWindows == false && hasModalWindow == false
    }
}

@MainActor
final class FoundryPanel: NSPanel {
    var onCommandK: (() -> Void)?
    var onCommandComma: (() -> Void)?
    var onCommandV: (() -> Bool)?
    var onAskAI: (() -> Void)?
    var onMouseMoved: (() -> Void)?
    var onKeyDown: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved:
            onMouseMoved?()
        case .keyDown:
            onKeyDown?()
        default:
            break
        }
        super.sendEvent(event)
    }

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
