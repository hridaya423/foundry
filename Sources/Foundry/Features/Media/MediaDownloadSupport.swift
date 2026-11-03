import Foundation
import FoundryServices
import os

final class YTDLPProgressParser: Sendable {
    private static let itemRegex = try! NSRegularExpression(pattern: #"Downloading item\s+(\d+)\s+of\s+(\d+)"#, options: [.caseInsensitive])
    private static let mergingRegex = try! NSRegularExpression(pattern: #"Merging formats into\s+[\"'](.+)[\"']"#, options: [.caseInsensitive])
    private static let downloadedRegex = try! NSRegularExpression(pattern: #"\[download\]\s+(.+)\s+has already been downloaded"#, options: [.caseInsensitive])
    private static let progressRegex = try! NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)%(?:.*?of\s+(?:~\s*)?([0-9]+(?:\.[0-9]+)?\s*(?:B|KiB|MiB|GiB|TiB)))?"#
            + #"(?:.*?at\s+([0-9]+(?:\.[0-9]+)?\s*(?:B|KiB|MiB|GiB|TiB))/s)?(?:.*?ETA\s+([0-9:]+))?"#,
        options: [.caseInsensitive]
    )
    private static let totalBytesRegex = try! NSRegularExpression(pattern: #"of\s+(?:~\s*)?([0-9]+(?:\.[0-9]+)?\s*(?:B|KiB|MiB|GiB|TiB))"#,
        options: [.caseInsensitive])
    private static let speedRegex = try! NSRegularExpression(pattern: #"at\s+([0-9]+(?:\.[0-9]+)?\s*(?:B|KiB|MiB|GiB|TiB))/s"#, options: [.caseInsensitive])
    private static let etaRegex = try! NSRegularExpression(pattern: #"ETA\s+([0-9:]+)"#, options: [.caseInsensitive])
    private static let byteValueRegex = try! NSRegularExpression(pattern: #"^\s*([0-9]+(?:\.[0-9]+)?)\s*(B|KiB|MiB|GiB|TiB)\s*$"#, options: [.caseInsensitive])
    private struct State {
        var title = "YouTube media"
        var currentItem: Int?
        var totalItems: Int?
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    func parse(_ line: String) -> MediaDownloadProgress? {
        state.withLock { state in

        if let itemMatch = Self.match(Self.itemRegex, in: line) {
            state.currentItem = Int(itemMatch[0])
            state.totalItems = Int(itemMatch[1])
            return makeProgress(state, message: "Downloading item \(itemMatch[0]) of \(itemMatch[1])")
        }

        if let destinationRange = line.range(of: "Destination:") {
            let nextTitle = line[destinationRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if nextTitle.isEmpty == false { state.title = Self.displayName(nextTitle) }
            return makeProgress(state, message: "Downloading \(state.title)")
        }

        if let merged = Self.match(Self.mergingRegex, in: line)?.first {
            state.title = Self.displayName(merged)
            return makeProgress(state, message: "Finishing \(state.title)")
        }

        if let existing = Self.match(Self.downloadedRegex, in: line)?.first {
            state.title = Self.displayName(existing)
            return makeProgress(state, message: "Already downloaded")
        }

        guard let progressMatch = Self.match(Self.progressRegex, in: line),
              let percent = Double(progressMatch[0]) else { return nil }
        let parsedTotalBytes = Self.byteValue(progressMatch[1])
            ?? Self.match(Self.totalBytesRegex, in: line).flatMap { Self.byteValue($0[0]) }
        let totalBytes = parsedTotalBytes.map(Int64.init)
        let bytesReceived = parsedTotalBytes.map { Int64($0 * percent / 100) } ?? 0
        let speed = Self.byteValue(progressMatch[2])
            ?? Self.match(Self.speedRegex, in: line).flatMap { Self.byteValue($0[0]) }
        let eta = Self.duration(progressMatch[3])
            ?? Self.match(Self.etaRegex, in: line).flatMap { Self.duration($0[0]) }
        return MediaDownloadProgress(
            phase: .downloading,
            title: state.title,
            message: "Downloading",
            bytesReceived: bytesReceived,
            totalBytes: totalBytes,
            fractionCompletedOverride: min(max(percent / 100, 0), 1),
            speedBytesPerSecond: speed,
            estimatedTimeRemaining: eta,
            currentItem: state.currentItem,
            totalItems: state.totalItems
        )
        }
    }

    private func makeProgress(_ state: State, message: String) -> MediaDownloadProgress {
        MediaDownloadProgress(
            phase: .downloading,
            title: state.title,
            message: message,
            bytesReceived: 0,
            totalBytes: nil,
            fractionCompletedOverride: nil,
            speedBytesPerSecond: nil,
            estimatedTimeRemaining: nil,
            currentItem: state.currentItem,
            totalItems: state.totalItems
        )
    }

    private static func match(_ regex: NSRegularExpression, in value: String) -> [String]? {
        guard let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: value) else { return "" }
            return String(value[range])
        }
    }

    private static func byteValue(_ value: String) -> Double? {
        guard let match = byteValueRegex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
              let numberRange = Range(match.range(at: 1), in: value),
              let unitRange = Range(match.range(at: 2), in: value),
              let number = Double(value[numberRange]) else { return nil }
        let unit = value[unitRange]
        let multiplier: Double
        switch unit.lowercased() {
        case "b": multiplier = 1
        case "kib": multiplier = 1_024
        case "mib": multiplier = 1_048_576
        case "gib": multiplier = 1_073_741_824
        case "tib": multiplier = 1_099_511_627_776
        default: return nil
        }
        return number * multiplier
    }

    private static func duration(_ value: String) -> TimeInterval? {
        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard parts.count > 0 else { return nil }
        return parts.reversed().enumerated().reduce(0) { total, element in
            total + element.element * pow(60, Double(element.offset))
        }
    }

    private static func displayName(_ value: String) -> String {
        let unquoted = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return unquoted.hasPrefix("/") ? URL(fileURLWithPath: unquoted).lastPathComponent : unquoted
    }
}

final class MediaProgressThrottle: Sendable {
    private let clock = ContinuousClock()
    private let lastReportedAt = OSAllocatedUnfairLock<ContinuousClock.Instant?>(initialState: nil)

    func shouldReport(_ progress: MediaDownloadProgress) -> Bool {
        let now = clock.now
        return lastReportedAt.withLock { lastReportedAt in
            let isSignificant = progress.phase != .downloading
                || progress.message != "Downloading"
                || progress.fractionCompleted == 1
            if isSignificant == false,
               let lastReportedAt,
               lastReportedAt.duration(to: now) < .milliseconds(100) {
                return false
            }
            lastReportedAt = now
            return true
        }
    }
}

actor YTDLPInstallGate {
    private var task: Task<String, Error>?

    func install(_ operation: @escaping @Sendable () async throws -> String) async throws -> String {
        if let task { return try await task.value }
        let task = Task { try await operation() }
        self.task = task
        defer { self.task = nil }
        return try await task.value
    }
}

enum MediaDownloadError: LocalizedError, Equatable {
    case invalidURL
    case youtubeDependencyMissing
    case cobaltResponseInvalid
    case cobaltDidNotReturnFile
    case retryable(String)
    case message(String)

    var isRetryable: Bool {
        switch self {
        case .retryable, .cobaltResponseInvalid, .cobaltDidNotReturnFile: true
        default: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL: "That isn't a link Foundry can download"
        case .youtubeDependencyMissing: "yt-dlp is missing and Homebrew was not found"
        case .cobaltResponseInvalid: "Cobalt returned an invalid response"
        case .cobaltDidNotReturnFile: "Cobalt did not return a downloadable file"
        case let .retryable(message): message
        case let .message(message): message
        }
    }
}
