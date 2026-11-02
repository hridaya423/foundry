import AppKit
import Foundation
import SwiftUI
import FoundryDomain
import FoundryServices

// Media-download orchestration: retry, destination, and the bounded
// parallel batch that queues downloads from a pasted list.
extension CommandPanelState {

    func cancelDownload(_ id: UUID) {
        actionRunner.cancel(id)
    }

    func retryDownload(_ item: MediaDownloadItem) {
        guard item.status != .active else { return }
        let action = CommandAction(
            id: "media.download.retry.\(UUID().uuidString)",
            title: "Retry Download",
            behavior: DownloadMediaAction(url: item.sourceURL)
        )
        router.openMediaDownloads()
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await execute(action, commandID: "media.download.retry")
        }
    }

    func changeMediaDownloadFolder() {
        let action = CommandAction(
            id: "media.download.choose-folder.\(UUID().uuidString)",
            title: "Change Download Folder",
            behavior: ChooseMediaDownloadFolderAction()
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await execute(action, commandID: "media.download.choose-folder")
        }
    }

    func submitMediaLinks() {
        let manager = mediaDownloads
        guard manager.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            if let item = manager.selectedItem { openMediaDownload(item) }
            return
        }
        guard startMediaDownloads(from: manager.composerText) > 0 else {
            manager.composerMessage = String(localized: "Paste a full video or audio URL, starting with https://.")
            return
        }
        manager.composerText = MediaDownloadProvider.remainingInput(after: manager.composerText)
        manager.composerMessage = MediaDownloadsView.skippedMessage(remaining: manager.composerText)
    }

    func openMediaDownload(_ item: MediaDownloadItem) {
        switch item.status {
        case .completed:
            let files = item.progress.outputURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            if files.count == 1, let file = files.first {
                NSWorkspace.shared.open(file)
            } else if files.isEmpty == false {
                NSWorkspace.shared.activateFileViewerSelecting(files)
            } else {
                showActionFeedback(.failure(String(localized: "The saved files have been moved or deleted.")))
            }
        case .failed, .cancelled:
            retryDownload(item)
        case .active:
            break
        }
    }

    @discardableResult
    func startMediaDownloads(from value: String) -> Int {
        let urls = MediaDownloadProvider.mediaURLs(in: value)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                var pending = urls[...]
                for _ in 0..<min(3, pending.count) {
                    let url = pending.removeFirst()
                    group.addTask { [weak self] in
                        _ = await self?.execute(Self.mediaDownloadAction(for: url), commandID: "media.download.batch")
                    }
                }
                while await group.next() != nil, pending.isEmpty == false {
                    let url = pending.removeFirst()
                    group.addTask { [weak self] in
                        _ = await self?.execute(Self.mediaDownloadAction(for: url), commandID: "media.download.batch")
                    }
                }
            }
        }
        return urls.count
    }

    static func mediaDownloadAction(for url: URL) -> CommandAction {
        CommandAction(
            id: "media.download.batch.\(UUID().uuidString)",
            title: "Download",
            behavior: DownloadMediaAction(url: url.absoluteString)
        )
    }
}
