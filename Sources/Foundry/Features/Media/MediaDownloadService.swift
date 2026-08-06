import Foundation
import FoundryServices

protocol MediaDownloading: Sendable {
    var downloadFolder: URL { get }

    func download(
        urlString: String,
        status: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> String

    func download(
        urlString: String,
        status: (@MainActor @Sendable (String) -> Void)?,
        progress: (@MainActor @Sendable (MediaDownloadProgress) -> Void)?
    ) async throws -> String
}

extension MediaDownloading {
    func download(
        urlString: String,
        status: (@MainActor @Sendable (String) -> Void)?,
        progress _: (@MainActor @Sendable (MediaDownloadProgress) -> Void)?
    ) async throws -> String {
        try await download(urlString: urlString, status: status)
    }
}

final class MediaDownloadService: MediaDownloading, @unchecked Sendable {
    var downloadFolder: URL {
        MediaDownloadDestination.folder
    }

    func download(
        urlString: String,
        status: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws -> String {
        try await download(urlString: urlString, status: status, progress: nil)
    }

    func download(
        urlString: String,
        status: (@MainActor @Sendable (String) -> Void)? = nil,
        progress: (@MainActor @Sendable (MediaDownloadProgress) -> Void)? = nil
    ) async throws -> String {
        guard let url = URL(string: urlString) else { return "Media download failed: Invalid media URL" }
        let initialTitle = url.lastPathComponent.isEmpty ? "Media download" : url.lastPathComponent

        do {
            try FileManager.default.createDirectory(at: downloadFolder, withIntermediateDirectories: true)
            emit(.starting(title: initialTitle), progress)

            if MediaDownloadProvider.isDirectMediaFile(url) {
                let file = try await downloadDirectFile(url, status: status, progress: progress)
                return "Downloaded \(file.lastPathComponent)"
            }

            if isYouTube(url) {
                report("Preparing yt-dlp", status)
                emit(MediaDownloadProgress(
                    phase: .preparing,
                    title: "YouTube media",
                    message: "Preparing yt-dlp",
                    bytesReceived: 0,
                    totalBytes: nil,
                    fractionCompletedOverride: nil,
                    speedBytesPerSecond: nil,
                    estimatedTimeRemaining: nil,
                    currentItem: nil,
                    totalItems: nil
                ), progress)
                let executable = try installYTDLPIfNeeded()
                let playlistLabel = isPlaylist(url) ? "playlist" : "media"
                report("Downloading \(playlistLabel)", status)
                try await runYTDLP(executable, url: url, progress: progress)
                return "Downloaded YouTube media to \(downloadFolder.path)"
            }

            let file = try await downloadWithCobalt(url, status: status, progress: progress)
            return "Downloaded \(file.lastPathComponent)"
        } catch {
            if Task.isCancelled {
                emit(MediaDownloadProgress(
                    phase: .cancelled,
                    title: initialTitle,
                    message: "Download cancelled",
                    bytesReceived: 0,
                    totalBytes: nil,
                    fractionCompletedOverride: nil,
                    speedBytesPerSecond: nil,
                    estimatedTimeRemaining: nil,
                    currentItem: nil,
                    totalItems: nil
                ), progress)
                throw CancellationError()
            }
            let message = "Media download failed: \(error.localizedDescription)"
            emit(MediaDownloadProgress(
                phase: .failed,
                title: initialTitle,
                message: message,
                bytesReceived: 0,
                totalBytes: nil,
                fractionCompletedOverride: nil,
                speedBytesPerSecond: nil,
                estimatedTimeRemaining: nil,
                currentItem: nil,
                totalItems: nil
            ), progress)
            return message
        }
    }

    private func downloadDirectFile(
        _ sourceURL: URL,
        status: (@MainActor @Sendable (String) -> Void)?,
        progress: (@MainActor @Sendable (MediaDownloadProgress) -> Void)?
    ) async throws -> URL {
        report("Downloading \(sourceURL.lastPathComponent)", status)
        emit(MediaDownloadProgress(
            phase: .downloading,
            title: sourceURL.lastPathComponent,
            message: "Downloading",
            bytesReceived: 0,
            totalBytes: nil,
            fractionCompletedOverride: nil,
            speedBytesPerSecond: nil,
            estimatedTimeRemaining: nil,
            currentItem: nil,
            totalItems: nil
        ), progress)
        let (temporaryURL, response) = try await downloadFile(from: sourceURL, title: sourceURL.lastPathComponent, progress: progress)
        var shouldRemoveTemporary = true
        defer {
            if shouldRemoveTemporary { try? FileManager.default.removeItem(at: temporaryURL) }
        }
        let fallbackName = response?.suggestedFilename ?? sourceURL.lastPathComponent
        let name = fallbackName.isEmpty ? "media-\(Int(Date().timeIntervalSince1970)).\(sourceURL.pathExtension)" : fallbackName
        let destination = uniqueDestination(for: name)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        shouldRemoveTemporary = false
        return destination
    }

    private func isYouTube(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    private func isPlaylist(_ url: URL) -> Bool {
        guard isYouTube(url), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        if url.path == "/playlist" { return true }
        return components.queryItems?.contains { $0.name == "list" && ($0.value?.isEmpty == false) } == true
    }

    private func installYTDLPIfNeeded() throws -> String {
        if let existing = firstExistingPath(["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]) { return existing }
        if let found = try? runAndCapture("/usr/bin/which", ["yt-dlp"]).trimmingCharacters(in: .whitespacesAndNewlines), found.isEmpty == false {
            return found
        }

        guard let brew = firstExistingPath(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) else {
            throw MediaDownloadError.message("yt-dlp is missing and Homebrew was not found")
        }

        try run(brew, ["install", "yt-dlp"])
        if let installed = firstExistingPath(["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]) { return installed }
        throw MediaDownloadError.message("yt-dlp install finished, but yt-dlp was not found")
    }

    private func downloadWithCobalt(
        _ sourceURL: URL,
        status: (@MainActor @Sendable (String) -> Void)?,
        progress: (@MainActor @Sendable (MediaDownloadProgress) -> Void)?
    ) async throws -> URL {
        report("Requesting media link from cobalt", status)
        emit(MediaDownloadProgress(
            phase: .resolving,
            title: sourceURL.host ?? "Media download",
            message: "Requesting media link",
            bytesReceived: 0,
            totalBytes: nil,
            fractionCompletedOverride: nil,
            speedBytesPerSecond: nil,
            estimatedTimeRemaining: nil,
            currentItem: nil,
            totalItems: nil
        ), progress)
        var request = URLRequest(url: URL(string: "https://api.cobalt.tools/")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["url": sourceURL.absoluteString])

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MediaDownloadError.message("invalid cobalt response")
        }

        if let error = json["error"] as? [String: Any], let code = error["code"] as? String {
            throw MediaDownloadError.message("cobalt error: \(code)")
        }

        let downloadURLString = json["url"] as? String
            ?? json["tunnel"] as? String
            ?? (json["picker"] as? [[String: Any]])?.compactMap { $0["url"] as? String ?? $0["tunnel"] as? String }.first

        guard let downloadURLString, let downloadURL = URL(string: downloadURLString) else {
            throw MediaDownloadError.message("cobalt did not return a downloadable file")
        }

        report("Downloading media", status)
        emit(MediaDownloadProgress(
            phase: .downloading,
            title: sourceURL.host ?? "Media download",
            message: "Downloading media",
            bytesReceived: 0,
            totalBytes: nil,
            fractionCompletedOverride: nil,
            speedBytesPerSecond: nil,
            estimatedTimeRemaining: nil,
            currentItem: nil,
            totalItems: nil
        ), progress)
        let (temporaryURL, response) = try await downloadFile(from: downloadURL, title: sourceURL.host ?? "Media download", progress: progress)
        var shouldRemoveTemporary = true
        defer {
            if shouldRemoveTemporary { try? FileManager.default.removeItem(at: temporaryURL) }
        }
        let fallbackName = response?.suggestedFilename ?? "media-\(Int(Date().timeIntervalSince1970))"
        let destination = uniqueDestination(for: fallbackName)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        shouldRemoveTemporary = false
        return destination
    }

    private func runYTDLP(
        _ path: String,
        url: URL,
        progress: (@MainActor @Sendable (MediaDownloadProgress) -> Void)?
    ) async throws {
        let parser = YTDLPProgressParser()
        let result = try await ProcessRunner.run(
            path: path,
            arguments: ["--newline", "-P", downloadFolder.path, "-o", "%(title).200B [%(id)s].%(ext)s", url.absoluteString],
            timeout: 30 * 60,
            outputLimit: 8 * 1024 * 1024,
            onOutput: { output in
                guard let update = parser.parse(output.line) else { return }
                Task { @MainActor in progress?(update) }
            }
        )
        guard result.succeeded else {
            throw MediaDownloadError.message(result.stderr.isEmpty ? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func downloadFile(
        from sourceURL: URL,
        title: String,
        progress: (@MainActor @Sendable (MediaDownloadProgress) -> Void)?
    ) async throws -> (URL, URLResponse?) {
        let delegate = MediaDownloadDelegate(title: title, progress: progress)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.start(sourceURL, continuation: continuation)
            }
        } onCancel: {
            delegate.cancel()
        }
    }

    private func emit(
        _ value: MediaDownloadProgress,
        _ progress: (@MainActor @Sendable (MediaDownloadProgress) -> Void)?
    ) {
        guard let progress else { return }
        Task { @MainActor in progress(value) }
    }

    private func report(_ message: String, _ status: (@MainActor @Sendable (String) -> Void)?) {
        guard let status else { return }
        Task { @MainActor in status(message) }
    }

    private func firstExistingPath(_ paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func run(_ path: String, _ arguments: [String]) throws {
        _ = try runAndCapture(path, arguments)
    }

    private func runAndCapture(_ path: String, _ arguments: [String]) throws -> String {
        guard let result = ProcessRunner.runSynchronously(path: path, arguments: arguments, timeout: 5 * 60, outputLimit: 8 * 1024 * 1024), result.succeeded else {
            throw MediaDownloadError.message("Process failed: \(path)")
        }
        return result.stdout
    }

    private func uniqueDestination(for name: String) -> URL {
        let baseName = safeFilename(name)
        let folder = downloadFolder
        let original = folder.appendingPathComponent(baseName)
        guard FileManager.default.fileExists(atPath: original.path) else { return original }
        let url = URL(fileURLWithPath: baseName)
        let stem = url.deletingPathExtension().lastPathComponent
        let extensionName = url.pathExtension
        for index in 1...10_000 {
            let candidateName = extensionName.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(extensionName)"
            let candidate = folder.appendingPathComponent(candidateName)
            if FileManager.default.fileExists(atPath: candidate.path) == false { return candidate }
        }
        return folder.appendingPathComponent("media-\(UUID().uuidString).\(extensionName)")
    }

    private func safeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "media-\(Int(Date().timeIntervalSince1970))" : cleaned
    }
}

private final class MediaDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let title: String
    private let progress: (@MainActor @Sendable (MediaDownloadProgress) -> Void)?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<(URL, URLResponse?), Error>?
    private var temporaryURL: URL?
    private var response: URLResponse?
    private var pendingError: Error?
    private var startedAt = Date()
    private var lastReportedAt = Date.distantPast
    private var didFinish = false

    init(title: String, progress: (@MainActor @Sendable (MediaDownloadProgress) -> Void)?) {
        self.title = title
        self.progress = progress
    }

    func start(_ sourceURL: URL, continuation: CheckedContinuation<(URL, URLResponse?), Error>) {
        lock.lock()
        self.continuation = continuation
        startedAt = Date()
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.downloadTask(with: sourceURL)
        self.task = task
        lock.unlock()
        task.resume()
    }

    func cancel() {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite totalBytesExpected: Int64
    ) {
        let now = Date()
        lock.lock()
        let shouldReport = now.timeIntervalSince(lastReportedAt) >= 0.1 || totalBytesExpected == totalBytesWritten
        if shouldReport { lastReportedAt = now }
        let elapsed = max(now.timeIntervalSince(startedAt), 0.001)
        lock.unlock()
        guard shouldReport else { return }

        let total = totalBytesExpected > 0 ? totalBytesExpected : nil
        let speed = Double(totalBytesWritten) / elapsed
        let remaining = total.map { max(Double($0 - totalBytesWritten), 0) / max(speed, 0.001) }
        emit(MediaDownloadProgress(
            phase: .downloading,
            title: title,
            message: "Downloading",
            bytesReceived: totalBytesWritten,
            totalBytes: total,
            fractionCompletedOverride: nil,
            speedBytesPerSecond: speed,
            estimatedTimeRemaining: remaining,
            currentItem: nil,
            totalItems: nil
        ))
        lock.lock()
        response = downloadTask.response
        lock.unlock()
        _ = bytesWritten
    }

    func urlSession(_: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let stagingURL = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-download-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: stagingURL)
            lock.lock()
            temporaryURL = stagingURL
            response = downloadTask.response
            lock.unlock()
        } catch {
            lock.lock()
            pendingError = error
            lock.unlock()
        }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard didFinish == false else {
            lock.unlock()
            return
        }
        didFinish = true
        let continuation = self.continuation
        self.continuation = nil
        let temporaryURL = self.temporaryURL
        let response = self.response
        let pendingError = self.pendingError
        let session = self.session
        lock.unlock()

        let resultError = pendingError ?? error
        if let resultError {
            if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
            continuation?.resume(throwing: resultError)
        } else if let temporaryURL {
            continuation?.resume(returning: (temporaryURL, response))
        } else {
            continuation?.resume(throwing: MediaDownloadError.message("download completed without a file"))
        }
        session?.finishTasksAndInvalidate()
    }

    private func emit(_ value: MediaDownloadProgress) {
        guard let progress else { return }
        Task { @MainActor in progress(value) }
    }
}

final class YTDLPProgressParser: @unchecked Sendable {
    private let lock = NSLock()
    private var title = "YouTube media"
    private var currentItem: Int?
    private var totalItems: Int?

    func parse(_ line: String) -> MediaDownloadProgress? {
        lock.lock()
        defer { lock.unlock() }

        if let itemMatch = Self.match(#"Downloading item\s+(\d+)\s+of\s+(\d+)"#, in: line) {
            currentItem = Int(itemMatch[0])
            totalItems = Int(itemMatch[1])
            return makeProgress(message: "Downloading item \(itemMatch[0]) of \(itemMatch[1])")
        }

        if let destinationRange = line.range(of: "Destination:") {
            let nextTitle = line[destinationRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if nextTitle.isEmpty == false { title = Self.displayName(nextTitle) }
            return makeProgress(message: "Downloading \(title)")
        }

        if let merged = Self.match(#"Merging formats into\s+[\"'](.+)[\"']"#, in: line)?.first {
            title = Self.displayName(merged)
            return makeProgress(message: "Finishing \(title)")
        }

        if let existing = Self.match(#"\[download\]\s+(.+)\s+has already been downloaded"#, in: line)?.first {
            title = Self.displayName(existing)
            return makeProgress(message: "Already downloaded")
        }

        guard let percent = Self.match(#"(\d+(?:\.\d+)?)%"#, in: line).flatMap({ Double($0[0]) }) else { return nil }
        let parsedTotalBytes = Self.match(#"of\s+(?:~\s*)?([0-9]+(?:\.[0-9]+)?\s*(?:B|KiB|MiB|GiB|TiB))"#, in: line).flatMap { Self.byteValue($0[0]) }
        let totalBytes = parsedTotalBytes.map(Int64.init)
        let bytesReceived = parsedTotalBytes.map { Int64($0 * percent / 100) } ?? 0
        let speed = Self.match(#"at\s+([0-9]+(?:\.[0-9]+)?\s*(?:B|KiB|MiB|GiB|TiB))/s"#, in: line).flatMap { Self.byteValue($0[0]) }
        let eta = Self.match(#"ETA\s+([0-9:]+)"#, in: line).flatMap { Self.duration($0[0]) }
        return MediaDownloadProgress(
            phase: .downloading,
            title: title,
            message: "Downloading",
            bytesReceived: bytesReceived,
            totalBytes: totalBytes,
            fractionCompletedOverride: min(max(percent / 100, 0), 1),
            speedBytesPerSecond: speed,
            estimatedTimeRemaining: eta,
            currentItem: currentItem,
            totalItems: totalItems
        )
    }

    private func makeProgress(message: String) -> MediaDownloadProgress {
        MediaDownloadProgress(
            phase: .downloading,
            title: title,
            message: message,
            bytesReceived: 0,
            totalBytes: nil,
            fractionCompletedOverride: nil,
            speedBytesPerSecond: nil,
            estimatedTimeRemaining: nil,
            currentItem: currentItem,
            totalItems: totalItems
        )
    }

    private static func match(_ pattern: String, in value: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return String(value[range])
        }
    }

    private static func byteValue(_ value: String) -> Double? {
        let pattern = #"^\s*([0-9]+(?:\.[0-9]+)?)\s*(B|KiB|MiB|GiB|TiB)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
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

private enum MediaDownloadError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message): message
        }
    }
}
