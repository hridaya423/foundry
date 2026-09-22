import AppKit
import SwiftUI
import FoundryServices

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private static let rootSize = NSSize(width: 750, height: 495)
    private static let compactHeight: CGFloat = 68

    private let state: CommandPanelState
    private let diagnostics: DiagnosticsService
    private let directPasteService: DirectPasteService
    private let quickLook = QuickLookPanelController()
    private let toast = TransientNoticeController()
    private var panel: FoundryPanel?

    private var hideGate = PanelHideGate()
    private var isSuspended = false

    var isVisible: Bool {
        panel?.isVisible == true && isSuspended == false
    }

    init(state: CommandPanelState, diagnostics: DiagnosticsService, directPasteService: DirectPasteService = .shared) {
        self.state = state
        self.diagnostics = diagnostics
        self.directPasteService = directPasteService
        super.init()
    }

    func prewarm() {
        if panel == nil {
            panel = makePanel()
        }
    }

    func setCompactCollapsed(_ collapsed: Bool) {
        guard let panel else { return }
        let height = collapsed ? Self.compactHeight : Self.rootSize.height
        var frame = panel.frame
        guard frame.height != height else { return }
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true, animate: true)
    }

    func show() {
        hideGate.cancelPendingHide()
        toast.dismiss()
        directPasteService.captureTarget()
        let span = diagnostics.startSpan("panel.show")
        let panel = panel ?? makePanel()
        self.panel = panel
        isSuspended = false

        state.presentationToken = UUID()
        state.hoverHighlightsArmed = false
        panel.setFrame(frame(for: panel), display: false)
        panel.ignoresMouseEvents = false
        panel.inputEnabled = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        CATransaction.flush()
        DispatchQueue.main.async { [weak panel, diagnostics] in
            diagnostics.endSpan(span)
            guard let panel, panel.isVisible, panel.isKeyWindow == false else { return }
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func hide() {
        quickLook.close()
        state.panelWillClose()
        guard let panel else { return }
        let generation = hideGate.beginHide()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.09
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak panel] in
            MainActor.assumeIsolated {
                guard let self, let panel, self.hideGate.allowsCompletion(for: generation) else { return }
                panel.ignoresMouseEvents = true
                panel.alphaValue = 0
                panel.inputEnabled = false
                self.isSuspended = true
                self.completePendingPaste()
            }
        })
    }

    private func completePendingPaste() {
        guard directPasteService.hasPendingPaste else { return }
        Task { @MainActor [directPasteService] in
            do {
                try await directPasteService.completePendingPaste()
            } catch {
                state.setDirectPasteError(error)
            }
        }
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
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.onCommandK = { [weak self] in
            self?.state.toggleActions()
        }
        panel.onActionShortcut = { [weak self] shortcut in
            guard let self else { return false }
            let dismiss: @MainActor () -> Void = { [weak self] in self?.hide() }
            return self.state.performActionShortcut(shortcut, dismiss: dismiss) || self.state.performModeShortcut(shortcut, dismiss: dismiss)
        }
        panel.onCommandComma = { [weak self] in
            self?.state.openSettings()
        }
        panel.onCommandV = { [weak self] in
            self?.state.pasteFromClipboard() ?? false
        }
        panel.onEscape = { [weak self] in
            guard let self else { return }
            if self.state.handleEscape() == false {
                self.hide()
            }
        }
        panel.onMouseMoved = { [weak self] in
            self?.state.hoverHighlightsArmed = true
        }
        panel.onKeyDown = { [weak self] in
            self?.state.hoverHighlightsArmed = false
        }

        state.onQuickLook = { [weak self] url in
            self?.quickLook.toggle(url, relativeTo: self?.panel)
        }
        state.onTransientNotice = { [weak self] feedback in
            self?.toast.show(feedback, relativeTo: self?.panel)
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
        let height = state.compactCollapsed ? Self.compactHeight : Self.rootSize.height
        let origin = CGPoint(
            x: visibleFrame.midX - Self.rootSize.width / 2,
            y: max(visibleFrame.minY, visibleFrame.maxY - height - topInset)
        )
        return NSRect(origin: origin, size: NSSize(width: Self.rootSize.width, height: height))
    }
}

struct PanelHideGate {
    private(set) var generation = 0

    mutating func beginHide() -> Int {
        generation += 1
        return generation
    }

    mutating func cancelPendingHide() {
        generation += 1
    }

    func allowsCompletion(for generation: Int) -> Bool {
        generation == self.generation
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
    var onActionShortcut: ((ActionShortcut) -> Bool)?
    var onCommandV: (() -> Bool)?
    var onEscape: (() -> Void)?
    var onMouseMoved: (() -> Void)?
    var onKeyDown: (() -> Void)?
    var inputEnabled = true

    override var canBecomeKey: Bool { inputEnabled }
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
        if event.keyCode == 53 {
            onEscape?()
            return
        }

        if handleShortcut(event) {
            return
        }

        super.keyDown(with: event)
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased(), key.isEmpty == false {
            let modifiers = Set(zip([NSEvent.ModifierFlags.control, .option, .shift, .command], ActionShortcut.Modifier.allCases).compactMap { flags.contains($0) ? $1 : nil })
            if onActionShortcut?(ActionShortcut(key: key, modifiers: modifiers)) == true { return true }
        }
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
