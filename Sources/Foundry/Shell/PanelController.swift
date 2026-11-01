import AppKit
import FoundryDomain
import SwiftUI
import FoundryServices

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private static let rootSize = NSSize(width: 750, height: 495)
    private static let compactHeight: CGFloat = 68

    private let state: CommandPanelState
    private let diagnostics: DiagnosticsService
    private let directPasteService: DirectPasteService
    private let activation: any AppActivation
    /// Reports whether another Foundry window (onboarding, settings) is up;
    /// hides must not tear down those windows. Wired post-init because
    /// onboarding is constructed after the panel in ShellController.
    var otherWindowsVisible: () -> Bool
    private let quickLook = QuickLookPanelController()
    private let toast = TransientNoticeController()
    private var panel: FoundryPanel?

    private var hideGate = PanelHideGate()

    var isVisible: Bool {
        panel?.isVisible == true
    }

    init(
        state: CommandPanelState,
        diagnostics: DiagnosticsService,
        directPasteService: DirectPasteService = .shared,
        activation: (any AppActivation)? = nil,
        otherWindowsVisible: (() -> Bool)? = nil
    ) {
        self.state = state
        self.diagnostics = diagnostics
        self.directPasteService = directPasteService
        self.activation = activation ?? NSAppActivation()
        self.otherWindowsVisible = otherWindowsVisible ?? {
            NSApp.windows.contains { $0.isVisible && $0.isKind(of: FoundryPanel.self) == false }
        }
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
        panel.setFrame(frame, display: true, animate: false)
        panel.invalidateShadow()
    }

    func show() {
        hideGate.cancelPendingHide()
        toast.dismiss()
        directPasteService.captureTarget()
        SelectionSnapshot.capture(processIdentifier: directPasteService.targetProcessIdentifier)
        let span = diagnostics.startSpan("panel.show")
        let panel = panel ?? makePanel()
        self.panel = panel

        state.presentationToken = UUID()
        state.session.hoverHighlightsArmed = false
        panel.setFrame(frame(for: panel), display: false)
        panel.ignoresMouseEvents = false
        panel.inputEnabled = true
        let fades = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == false
        panel.alphaValue = fades ? 0 : 1
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        if fades {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = FoundryTheme.Motion.enterDuration
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
                panel.animator().alphaValue = 1
            }, completionHandler: { [weak panel] in
                MainActor.assumeIsolated { panel?.invalidateShadow() }
            })
        }
        CATransaction.setCompletionBlock { [diagnostics] in
            diagnostics.mark("panel.firstFrame")
        }
        CATransaction.flush()
        DispatchQueue.main.async { [weak panel, diagnostics] in
            diagnostics.endSpan(span)
            guard let panel, panel.isVisible else { return }
            if panel.isKeyWindow == false { panel.makeKeyAndOrderFront(nil) }
            (panel.firstResponder as? NSTextView)?.selectAll(nil)
        }
    }

    /// ⌘Y / Space on a file result toggles Quick Look — `ShellPort.quickLook`.
    func toggleQuickLook(_ url: URL) {
        quickLook.toggle(url)
    }

    var isQuickLookShowing: Bool { quickLook.isShowing }

    func closeQuickLook() {
        quickLook.close()
    }

    /// Arrow-key moves keep the launcher's selection — and the preview
    /// follows it while the panel is up.
    func quickLookFollowSelection() {
        guard case let .file(url)? = state.session.selectedResult?.payload else {
            quickLook.followSelection(nil)
            return
        }
        quickLook.followSelection(url)
    }

    /// Post-dismissal success toast — `ShellPort.showTransientNotice`.
    func showTransientNotice(_ feedback: ActionFeedback) {
        toast.show(feedback, relativeTo: panel)
    }

    func previewFile(_ url: URL) {
        quickLook.show(url)
    }

    enum HideReason {
        case dismissed
        case executed
    }

    func hide(reason: HideReason = .dismissed) {
        quickLook.close()
        SelectionSnapshot.clear()
        state.panelWillClose()
        guard let panel else {
            completePendingPaste()
            return
        }
        let generation = hideGate.beginHide()
        let finishHide: @MainActor () -> Void = { [weak self, weak panel] in
            guard let self, let panel, self.hideGate.allowsCompletion(for: generation) else { return }
            // Really leave: an alpha-0 ordered-in panel still composites,
            // counts as onscreen to window-list callers, and can sit on
            // top of system alerts.
            panel.orderOut(nil)
            panel.alphaValue = 0
            self.hideGate.cancelPendingHide()
            self.restoreFocusIfNeeded()
            self.completePendingPaste()
        }
        guard reason == .dismissed else { return finishHide() }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = FoundryTheme.Motion.exitDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { finishHide() }
        })
        // Failsafe: when the window can't composite (headless, occluded,
        // terminating), the group completion never fires and the panel would
        // leak onscreen. orderOut on a deadline; generation guards a show()
        // that lands first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            MainActor.assumeIsolated { finishHide() }
        }
    }

    /// A launcher owes the previous app its focus back on dismiss. Deactivate
    /// unless another Foundry window (onboarding, settings, a modal) is up.
    private func restoreFocusIfNeeded() {
        guard activation.isActive, otherWindowsVisible() == false else { return }
        activation.deactivate()
    }

    private func completePendingPaste() {
        guard directPasteService.hasPendingPaste else { return }
        Task { @MainActor [directPasteService] in
            do {
                try await directPasteService.completePendingPaste()
            } catch {
                state.settings.setDirectPasteError(error)
            }
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel?.isVisible == true else { return }
            self.state.session.focusToken = UUID()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let panel, panel.isVisible else { return }
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, panel.isVisible, panel.isKeyWindow == false else { return }
            guard PanelDismissalPolicy.shouldDismiss(
                hasAttachedSheet: panel.attachedSheet != nil,
                hasChildWindows: panel.childWindows?.isEmpty == false,
                hasModalWindow: NSApp.modalWindow != nil,
                hasQuickLook: quickLook.isShowing
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
        // .floating sits under modal panels and system sheets; .statusBar
        // painted the launcher over its own alerts and save panels.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.onCommandK = { [weak self] in
            self?.state.session.toggleActions()
        }
        panel.onActionShortcut = { [weak self] shortcut in
            guard let self else { return false }
            let dismiss: @MainActor () -> Void = { [weak self] in self?.hide(reason: .executed) }
            return self.state.performActionShortcut(shortcut, dismiss: dismiss) || self.state.performModeShortcut(shortcut, dismiss: dismiss)
        }
        panel.onCommandComma = { [weak self] in
            self?.state.router.openSettings()
        }
        panel.onCommandV = { [weak self] in
            self?.state.pasteFromClipboard() ?? false
        }
        panel.onCommandHeld = { [weak self] held in
            self?.state.session.isCommandHeld = held
        }
        panel.onEscape = { [weak self] in
            guard let self else { return }
            if self.state.handleEscape() == false {
                self.hide()
            }
        }
        panel.onMouseMoved = { [weak self] in
            self?.state.session.hoverHighlightsArmed = true
        }
        panel.onKeyDown = { [weak self] in
            self?.state.session.hoverHighlightsArmed = false
        }
        panel.onSpace = { [weak self] in
            self?.state.spaceTogglesQuickLook() ?? false
        }

        let rootView = FoundryIncreaseContrastRoot {
            CommandPanelView(state: state) { [weak self] in
                self?.hide(reason: .executed)
            }
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
        // A seventh down the usable height, in points: 140 pt on a 14" MacBook,
        // where the 1.1 release sat and the user prefers it.
        let topInset = visibleFrame.height / 7
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
    static func shouldDismiss(hasAttachedSheet: Bool, hasChildWindows: Bool, hasModalWindow: Bool, hasQuickLook: Bool = false) -> Bool {
        hasAttachedSheet == false && hasChildWindows == false && hasModalWindow == false && hasQuickLook == false
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
    var onCommandHeld: ((Bool) -> Void)?
    /// Returns true when Space toggled Quick Look — swallow the event so
    /// it never lands in the query field.
    var onSpace: (() -> Bool)?
    var inputEnabled = true

    override var canBecomeKey: Bool { inputEnabled }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved:
            onMouseMoved?()
        case .flagsChanged:
            onCommandHeld?(event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command)
        case .keyDown:
            onKeyDown?()
            // Space previews the selected file — handled here, before the
            // field editor, so it works with the query field focused.
            if event.keyCode == 49,
               event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
               onSpace?() == true { return }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control),
               event.modifierFlags.contains(.command) == false,
               handleShortcut(event) { return }
        default:
            break
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Text editing wins over result actions: with a selection, ⌘C copies
        // the query; without one, it falls through to the Copy action. Same
        // deal for ⌘⌫ — it clears the field first, trashes files only when
        // there's no field content to delete.
        if fieldEditorConsumes(event) {
            return super.performKeyEquivalent(with: event)
        }
        if handleShortcut(event) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    /// Whether the focused text field should get this chord instead of the
    /// action-shortcut layer.
    private func fieldEditorConsumes(_ event: NSEvent) -> Bool {
        guard let editor = firstResponder as? NSTextView, editor.isFieldEditor else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        switch (flags, key, event.keyCode) {
        case (.command, "v", _), (.command, "a", _), (.command, "z", _), (.command, "x", _):
            return true
        case ([.command, .shift], "z", _):
            return true
        case (.command, "c", _):
            return editor.selectedRange().length > 0
        case (.command, _, 51):
            return editor.string.isEmpty == false
        default:
            return false
        }
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
        if flags.contains(.command) || flags.contains(.control),
           let key = event.charactersIgnoringModifiers?.lowercased(), key.isEmpty == false {
            let modifiers = Set(zip([NSEvent.ModifierFlags.control, .option, .shift, .command],
                ActionShortcut.Modifier.allCases).compactMap { flags.contains($0) ? $1 : nil })
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
        case "v":
            return onCommandV?() ?? false
        default:
            return false
        }
    }
}
