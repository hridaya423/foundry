import AppKit
import QuickLookUI

@MainActor
final class QuickLookPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var previewView: QLPreviewView?
    private var currentURL: URL?

    func toggle(_ url: URL, relativeTo parent: NSWindow?) {
        if panel?.isVisible == true, currentURL == url {
            close()
            return
        }
        show(url, relativeTo: parent)
    }

    func show(_ url: URL, relativeTo parent: NSWindow?) {
        let panel = panel ?? makePanel()
        currentURL = url
        panel.title = url.lastPathComponent
        previewView?.previewItem = url as QLPreviewItem
        if let parent {
            let frame = parent.frame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.midY - panel.frame.height / 2
            ))
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        currentURL = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        guard let preview = QLPreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 520), style: .normal) else {
            return panel
        }
        preview.autoresizingMask = [.width, .height]
        preview.autostarts = true
        panel.contentView?.addSubview(preview)
        previewView = preview
        self.panel = panel
        return panel
    }

    func windowWillClose(_ notification: Notification) {
        currentURL = nil
    }
}
