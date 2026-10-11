import AppKit
import Foundation
import FoundryDomain
import FoundryServices

struct MediaBatchResult: Sendable {
    enum Status: Sendable, Equatable {
        case completed
        case failed(String)
        case cancelled

        var isCompleted: Bool {
            if case .completed = self { return true }
            return false
        }
    }

    let index: Int
    let status: Status
}

struct DownloadMediaAction: ResultAction, Equatable {
    let url: String

    init(url: String) { self.url = url }

    var icon: String? { "arrow.down.circle" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        ctx.panel.presentMediaDownloads()
        ctx.diagnostics.log("Starting media download")
        ctx.mediaDownloadManager.setCapabilities(ctx.mediaDownloadService.mediaCapabilities())
        let downloadID = ctx.invocation.cancellationID
        ctx.mediaDownloadManager.start(id: downloadID, sourceURL: url)
        let result: String
        do {
            result = try await ctx.mediaDownloadService.download(
                urlString: url,
                status: { status in ctx.emit(.status(status)) },
                progress: { progress in
                    ctx.mediaDownloadManager.update(id: downloadID, progress: progress)
                    ctx.emit(.downloadProgress(progress))
                }
            )
        } catch {
            if isExecutionCancellation(error) {
                ctx.mediaDownloadManager.cancel(id: downloadID)
                return .cancelled
            }
            let message = error.localizedDescription
            ctx.mediaDownloadManager.fail(id: downloadID, message: message)
            ctx.diagnostics.log(message)
            return ctx.finish(.failure(message: message, retryable: (error as? MediaDownloadError)?.isRetryable ?? false), feedback: .failure(message))
        }
        guard Task.isCancelled == false else {
            ctx.mediaDownloadManager.cancel(id: downloadID)
            return .cancelled
        }
        ctx.emit(.status(result))
        ctx.diagnostics.log(result)
        ctx.mediaDownloadManager.complete(id: downloadID, message: result)
        return .stayOpen(message: result)
    }
}

struct DownloadMediaBatchAction: ResultAction, Equatable {
    let urls: [String]

    var icon: String? { "arrow.down.circle" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        ctx.panel.presentMediaDownloads()
        let urls = self.urls
        let concurrencyLimit = 3
        var nextIndex = 0
        var results: [MediaBatchResult] = []
        await withTaskGroup(of: MediaBatchResult.self) { group in
            for _ in 0..<min(concurrencyLimit, urls.count) {
                let index = nextIndex
                nextIndex += 1
                group.addTask {
                    await downloadMediaBatchItem(urls[index], index: index, ctx: ctx)
                }
            }

            while let result = await group.next() {
                if result.status == .cancelled {
                    group.cancelAll()
                    results.append(result)
                    break
                }
                results.append(result)
                if nextIndex < urls.count {
                    let index = nextIndex
                    nextIndex += 1
                    group.addTask {
                        await downloadMediaBatchItem(urls[index], index: index, ctx: ctx)
                    }
                }
            }
        }
        if results.contains(where: { $0.status == .cancelled }) { return .cancelled }
        let completed = results.filter { $0.status.isCompleted }.count
        let failures = results
            .sorted { $0.index < $1.index }
            .compactMap { result -> String? in
                guard case let .failed(message) = result.status else { return nil }
                let url = urls[result.index]
                return "\(URL(string: url)?.lastPathComponent ?? url): \(message)"
            }
        let message = failures.isEmpty
            ? "Downloaded \(completed) of \(urls.count) media links"
            : "Downloaded \(completed) of \(urls.count); failed: \(failures.joined(separator: "; "))"
        ctx.emit(.status(message))
        return .open(route: .mediaDownloads)
    }

    @MainActor
    private func downloadMediaBatchItem(
        _ url: String,
        index: Int,
        ctx: ActionContext
    ) async -> MediaBatchResult {
        let id = UUID()
        ctx.mediaDownloadManager.start(id: id, sourceURL: url)
        do {
            let result = try await ctx.mediaDownloadService.download(urlString: url, status: { ctx.emit(.status($0)) }, progress: {
                ctx.mediaDownloadManager.update(id: id, progress: $0)
                ctx.emit(.downloadProgress($0))
            })
            ctx.mediaDownloadManager.complete(id: id, message: result)
            return MediaBatchResult(index: index, status: .completed)
        } catch {
            guard isExecutionCancellation(error) else {
                let message = error.localizedDescription
                ctx.mediaDownloadManager.fail(id: id, message: message)
                return MediaBatchResult(index: index, status: .failed(message))
            }
            ctx.mediaDownloadManager.cancel(id: id)
            return MediaBatchResult(index: index, status: .cancelled)
        }
    }
}

struct ChooseMediaDownloadFolderAction: ResultAction, Equatable {
    var icon: String? { "folder.badge.gearshape" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = MediaDownloadDestination.folder
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        MediaDownloadDestination.setFolder(url)
        ctx.emit(.status("Downloads will save to \(url.lastPathComponent)"))
        ctx.diagnostics.log("Media download folder changed: \(url.path)")
        return ctx.finish(.refreshResults(message: "Download folder changed"), feedback: .success("Download folder changed"))
    }
}
