import Combine
import Foundation
import FoundryServices
import Observation

enum MediaDownloadPhase: String, Sendable, Equatable {
    case preparing
    case resolving
    case downloading
    case completed
    case failed
    case cancelled
}

enum MediaDownloadCapability: Equatable, Sendable {
    case ready(label: String)
    case unavailable(label: String, reason: String)
}

extension MediaDownloadCapability {
    var label: String {
        switch self {
        case let .ready(label), let .unavailable(label, _): label
        }
    }
}

struct MediaDownloadCapabilities: Equatable, Sendable {
    let direct: MediaDownloadCapability
    let cobalt: MediaDownloadCapability
    let youtube: MediaDownloadCapability
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
    var outputURLs: [URL] = []

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
    var status: MediaDownloadStatus
    var progress: MediaDownloadProgress
    var failure: OperationFailure?
}

@MainActor
@Observable
final class MediaDownloadManager {
    private(set) var items: [MediaDownloadItem] = []
    private(set) var capabilities = MediaDownloadCapabilities(
        direct: .ready(label: "Direct links · ready"),
        cobalt: .unavailable(label: "Cobalt · unavailable", reason: "The hosted API requires authorization; yt-dlp is used instead"),
        youtube: .ready(label: "YouTube · yt-dlp automatic setup")
    )
    private var itemIndices: [UUID: Int] = [:]

    var activeCount: Int {
        items.reduce(into: 0) { count, item in
            if item.status == .active { count += 1 }
        }
    }

    func setCapabilities(_ capabilities: MediaDownloadCapabilities) {
        self.capabilities = capabilities
    }

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
            status: .active,
            progress: .starting(title: title),
            failure: nil
        )
        items.removeAll { $0.id == id }
        items.insert(item, at: 0)
        rebuildItemIndices()
    }

    func update(id: UUID, progress: MediaDownloadProgress) {
        guard let index = itemIndices[id] else { return }
        guard items[index].status == .active else { return }
        var displayProgress = progress
        if progress.title.hasPrefix("/") {
            displayProgress.title = URL(fileURLWithPath: progress.title).lastPathComponent
        }
        items[index].progress = displayProgress
        items[index].failure = nil
    }

    func complete(id: UUID, message: String) {
        guard let index = itemIndices[id] else { return }
        items[index].status = .completed
        items[index].progress.phase = .completed
        items[index].progress.message = message
        items[index].failure = nil
    }

    func fail(id: UUID, message: String) {
        guard let index = itemIndices[id] else { return }
        items[index].status = .failed
        items[index].progress.phase = .failed
        items[index].progress.message = message
        items[index].failure = OperationFailure(message: message)
    }

    func cancel(id: UUID) {
        guard let index = itemIndices[id] else { return }
        items[index].status = .cancelled
        items[index].progress.phase = .cancelled
        items[index].progress.message = "Download cancelled"
        items[index].failure = OperationFailure(message: "Download cancelled")
    }

    func clearFinished() {
        items.removeAll { $0.status != .active }
        rebuildItemIndices()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id && $0.status != .active }
        rebuildItemIndices()
    }

    private func rebuildItemIndices() {
        itemIndices = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
    }
}
