import AppKit
import SwiftUI
import FoundryDomain

@MainActor
final class TransientNoticeController {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ feedback: ActionFeedback, relativeTo parent: NSWindow?) {
        hideTask?.cancel()
        let panel = panel ?? makePanel()
        let host = panel.contentView as? NSHostingView<NoticeToast>
        host?.rootView = NoticeToast(message: feedback.message, symbol: feedback.symbolName)
        let size = host?.fittingSize ?? NSSize(width: 220, height: 34)
        panel.setContentSize(size)
        panel.alphaValue = 1

        let anchor = parent?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: anchor.midX - size.width / 2, y: anchor.midY - size.height / 2))
        panel.orderFrontRegardless()

        hideTask = Task { [weak panel] in
            try? await Task.sleep(for: .seconds(1.4))
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    panel?.animator().alphaValue = 0
                }
            }
            try? await Task.sleep(for: .milliseconds(200))
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                panel?.orderOut(nil)
            }
        }
    }

    func dismiss() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: NoticeToast(message: "", symbol: "checkmark.circle.fill"))
        self.panel = panel
        return panel
    }

    private struct NoticeToast: View {
        let message: String
        let symbol: String

        var body: some View {
            FoundryGlassSurface(role: .floatingOverlay, shape: Capsule()) {
                Label(message, systemImage: symbol)
                    .font(FoundryTheme.body(size: 12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 32)
            }
        }
    }
}
