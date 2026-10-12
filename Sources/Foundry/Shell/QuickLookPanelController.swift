import AppKit
import QuickLookUI

/// Drives the system `QLPreviewPanel` instead of a hand-rolled
/// `QLPreviewView` in a utility window — fullscreen, markup and Open With
/// come with it. The shared panel is ordered front *without* taking key,
/// so the launcher's arrow keys keep driving the selection and typing
/// still lands in the search field; selection changes call
/// `followSelection` to swap the previewed item.
@MainActor
final class QuickLookPanelController: NSObject {
    private var currentURL: URL?

    var isShowing: Bool {
        QLPreviewPanel.sharedPreviewPanelExists()
            && QLPreviewPanel.shared()?.isVisible == true
            && currentURL != nil
    }

    func toggle(_ url: URL) {
        if isShowing, currentURL == url {
            close()
            return
        }
        show(url)
    }

    func show(_ url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        currentURL = url
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.orderFront(nil)
    }

    /// Keeps the previewed item in step with the launcher's selection
    /// while the panel is up.
    func followSelection(_ url: URL?) {
        guard isShowing else { return }
        guard let url else {
            close()
            return
        }
        guard url != currentURL else { return }
        currentURL = url
        QLPreviewPanel.shared()?.refreshCurrentPreviewItem()
    }

    func close() {
        currentURL = nil
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.orderOut(nil)
        panel.dataSource = nil
        panel.delegate = nil
    }
}

// The QLPreviewPanel protocols are ObjC-era and nonisolated; the panel
// only ever calls them on the main thread, hence @preconcurrency.
extension QuickLookPanelController: @preconcurrency QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        currentURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        currentURL as QLPreviewItem?
    }
}

extension QuickLookPanelController: @preconcurrency QLPreviewPanelDelegate {
    /// The launcher keeps its keys — arrows and Space belong to the panel,
    /// not to Quick Look's own navigation.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        false
    }

    func sourceFrameOnScreenForPreviewItem(_ item: QLPreviewItem!) -> NSRect {
        .zero
    }

    /// Zoom the preview in from the item's icon.
    func transitionImageForPreviewItem(_ item: QLPreviewItem!, contentRect: UnsafeMutablePointer<NSRect>!) -> Any! {
        guard let url = item as? URL else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
