import Combine
import Foundation

enum MediaDownloadPhase: String, Sendable, Equatable {
    case preparing
    case resolving
    case downloading
    case completed
    case failed
    case cancelled
}

struct MediaDownloadProgress: Sendable, Equatable {
    var phase: MediaDownloadPhase
    var title: String
    var message: String
    var bytesReceived: Int64
    var totalBytes: Int64?
    var fractionCompletedOverride: Double?
    var speedBytesPerSecond: Double?
    var estimatedTimeRemaining: TimeInterval?
    var currentItem: Int?
    var totalItems: Int?

    var fractionCompleted: Double? {
        if let fractionCompletedOverride {
            return min(max(fractionCompletedOverride, 0), 1)
        }
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(max(Double(bytesReceived) / Double(totalBytes), 0), 1)
    }

    static func starting(title: String) -> MediaDownloadProgress {
        MediaDownloadProgress(
            phase: .preparing,
            title: title,
            message: "Preparing download",
            bytesReceived: 0,
            totalBytes: nil,
            fractionCompletedOverride: nil,
            speedBytesPerSecond: nil,
            estimatedTimeRemaining: nil,
            currentItem: nil,
            totalItems: nil
        )
    }
}

enum MediaDownloadStatus: String, Sendable, Equatable {
    case active
    case completed
    case failed
    case cancelled
}

struct MediaDownloadItem: Identifiable, Sendable, Equatable {
    let id: UUID
    let sourceURL: String
    let startedAt: Date
    var status: MediaDownloadStatus
    var progress: MediaDownloadProgress
    var resultMessage: String?
}

@MainActor
final class MediaDownloadManager: ObservableObject {
    @Published private(set) var items: [MediaDownloadItem] = []

    var activeCount: Int {
        items.reduce(into: 0) { count, item in
            if item.status == .active { count += 1 }
        }
    }

    var hasItems: Bool { items.isEmpty == false }

    func start(id: UUID, sourceURL: String) {
        let title: String
        if let candidate = URL(string: sourceURL)?.lastPathComponent, candidate.isEmpty == false {
            title = candidate
        } else {
            title = "Media download"
        }
        let item = MediaDownloadItem(
            id: id,
            sourceURL: sourceURL,
            startedAt: Date(),
            status: .active,
            progress: .starting(title: title),
            resultMessage: nil
        )
        items.removeAll { $0.id == id }
        items.insert(item, at: 0)
    }

    func update(id: UUID, progress: MediaDownloadProgress) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].status == .active else { return }
        var displayProgress = progress
        if progress.title.hasPrefix("/") {
            displayProgress.title = URL(fileURLWithPath: progress.title).lastPathComponent
        }
        items[index].progress = displayProgress
        items[index].resultMessage = nil
    }

    func complete(id: UUID, message: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .completed
        items[index].progress.phase = .completed
        items[index].progress.message = message
        items[index].resultMessage = message
    }

    func fail(id: UUID, message: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .failed
        items[index].progress.phase = .failed
        items[index].progress.message = message
        items[index].resultMessage = message
    }

    func cancel(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .cancelled
        items[index].progress.phase = .cancelled
        items[index].progress.message = "Download cancelled"
        items[index].resultMessage = "Download cancelled"
    }

    func clearFinished() {
        items.removeAll { $0.status != .active }
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id && $0.status != .active }
    }
}
