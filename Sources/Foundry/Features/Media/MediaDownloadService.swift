import Foundation
import Security
import FoundryServices

protocol MediaDownloading: Sendable {
    var downloadFolder: URL { get }

    func mediaCapabilities() -> MediaDownloadCapabilities
    func provisionYouTube(
        consent: YouTubeProvisioningConsent,
        progress: (@MainActor @Sendable (MediaDownloadProvisioningProgress) -> Void)?
    ) async throws

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
    func mediaCapabilities() -> MediaDownloadCapabilities {
        MediaDownloadCapabilities(
            direct: .ready(label: "Direct links · ready"),
            cobalt: .ready(label: "Cobalt · sends URL to Cobalt"),
            youtube: .unavailable(label: "YouTube · yt-dlp", reason: "Set up yt-dlp explicitly")
        )
    }

    func provisionYouTube(
        consent _: YouTubeProvisioningConsent,
        progress _: (@MainActor @Sendable (MediaDownloadProvisioningProgress) -> Void)?
    ) async throws {
        throw MediaDownloadError.provisioningUnavailable
    }
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
    struct Dependencies: Sendable {
        let session: URLSession
        let cobaltEndpoint: URL
        let executableLocator: ExecutableLocator
        let processRunner: any ProcessRunning
        let destination: URL
        let artifactFileSystem: any MediaArtifactFileSystem
        let networkPolicy: MediaNetworkPolicy
        let cobaltResponseMaxBytes: Int64
        let cobaltTimeout: TimeInterval
        let trustEvaluator: @Sendable (SecTrust) -> Bool

        init(
            session: URLSession = URLSession(configuration: .ephemeral),
            cobaltEndpoint: URL = URL(string: "https://api.cobalt.tools/")!,
            executableLocator: ExecutableLocator = ExecutableLocator(),
            processRunner: any ProcessRunning = SystemProcessRunner(),
            destination: URL = MediaDownloadDestination.folder,
            artifactFileSystem: any MediaArtifactFileSystem = FileManager.default,
            networkPolicy: MediaNetworkPolicy = MediaNetworkPolicy(),
            cobaltResponseMaxBytes: Int64 = 1_048_576,
            cobaltTimeout: TimeInterval = 20,
            trustEvaluator: @escaping @Sendable (SecTrust) -> Bool = { trust in var error: CFError?; return SecTrustEvaluateWithError(trust, &error) }
        ) {
            self.session = session
            self.cobaltEndpoint = cobaltEndpoint
            self.executableLocator = executableLocator
            self.processRunner = processRunner
            self.destination = destination
            self.artifactFileSystem = artifactFileSystem
            self.networkPolicy = networkPolicy
            self.cobaltResponseMaxBytes = cobaltResponseMaxBytes
            self.cobaltTimeout = cobaltTimeout
            self.trustEvaluator = trustEvaluator
        }
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies = Dependencies()) {
        self.dependencies = dependencies
    }

    var downloadFolder: URL {
        dependencies.destination
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
        guard let url = URL(string: urlString) else { throw MediaDownloadError.invalidURL }
        try dependencies.networkPolicy.validate(url)
        let initialTitle = url.lastPathComponent.isEmpty ? "Media download" : url.lastPathComponent

        do {
            try dependencies.artifactFileSystem.createDirectory(at: downloadFolder)
            emit(.starting(title: initialTitle), progress)

            if MediaDownloadProvider.isDirectMediaFile(url) {
                let file = try await downloadDirectFile(url, status: status, progress: progress)
                return "Downloaded \(file.lastPathComponent)"
            }

            if isYouTube(url) {
                report("Checking yt-dlp", status)
                let executable = try existingYTDLP()
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
            throw error
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
            if shouldRemoveTemporary { try? dependencies.artifactFileSystem.removeItem(at: temporaryURL) }
        }
        let fallbackName = response?.suggestedFilename ?? sourceURL.lastPathComponent
        let name = fallbackName.isEmpty ? "media-\(Int(Date().timeIntervalSince1970)).\(sourceURL.pathExtension)" : fallbackName
        let destination = try dependencies.networkPolicy.reserveDestination(named: name, in: downloadFolder, fileSystem: dependencies.artifactFileSystem)
        defer { dependencies.networkPolicy.releaseDestination(destination) }
        try dependencies.artifactFileSystem.moveItem(at: temporaryURL, to: destination)
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

    private func existingYTDLP() throws -> String {
        if let existing = try dependencies.executableLocator.locate(name: "yt-dlp", candidates: ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"], environment: ProcessInfo.processInfo.environment) { return existing.path }
        throw MediaDownloadError.youtubeDependencyMissing
    }

    func mediaCapabilities() -> MediaDownloadCapabilities {
        let youtube: MediaDownloadCapability = (try? existingYTDLP()) != nil
            ? .ready(label: "YouTube · yt-dlp ready")
            : .unavailable(label: "YouTube · yt-dlp", reason: "Set up yt-dlp explicitly")
        return MediaDownloadCapabilities(
            direct: .ready(label: "Direct links · ready"),
            cobalt: .ready(label: "Cobalt · sends URL to Cobalt"),
            youtube: youtube
        )
    }

    func provisionYouTube(
        consent: YouTubeProvisioningConsent,
        progress: (@MainActor @Sendable (MediaDownloadProvisioningProgress) -> Void)? = nil
    ) async throws {
        guard consent.approvedFormula == "yt-dlp", consent.disclosure == "Homebrew installs the current yt-dlp formula" else {
            throw MediaDownloadError.invalidProvisioningConsent
        }
        emitProvisioning(.init(phase: .checking, message: "Checking Homebrew", fractionCompleted: 0), progress)
        guard let brew = firstExistingPath(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) else {
            throw MediaDownloadError.provisioningUnavailable
        }
        try Task.checkCancellation()
        emitProvisioning(.init(phase: .installing, message: "Installing yt-dlp via Homebrew (current formula)", fractionCompleted: 0.5), progress)
        let result = try await dependencies.processRunner.run(path: brew, arguments: ["install", "yt-dlp"], timeout: 30 * 60, outputLimit: 2 * 1024 * 1024, environment: nil, currentDirectoryURL: nil, onOutput: nil)
        guard result.succeeded else { throw MediaDownloadError.provisioningFailed }
        try Task.checkCancellation()
        guard (try? existingYTDLP()) != nil else { throw MediaDownloadError.provisioningFailed }
        emitProvisioning(.init(phase: .completed, message: "yt-dlp is ready", fractionCompleted: 1), progress)
    }

    private func emitProvisioning(_ value: MediaDownloadProvisioningProgress, _ progress: (@MainActor @Sendable (MediaDownloadProvisioningProgress) -> Void)?) {
        guard let progress else { return }
        Task { @MainActor in progress(value) }
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
        var request = URLRequest(url: dependencies.cobaltEndpoint)
        try dependencies.networkPolicy.validate(dependencies.cobaltEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["url": sourceURL.absoluteString])

        let pinned = try dependencies.networkPolicy.pinnedURL(for: dependencies.cobaltEndpoint)
        request.url = pinned.url
        request.setValue(pinned.host, forHTTPHeaderField: "Host")
        let (data, cobaltResponse) = try await cobaltResponseData(request)
        if let cobaltResponse = cobaltResponse as? HTTPURLResponse, !(200..<300).contains(cobaltResponse.statusCode) {
            throw MediaNetworkPolicyFailure.invalidStatus(cobaltResponse.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MediaDownloadError.cobaltResponseInvalid
        }

        if let error = json["error"] as? [String: Any], let code = error["code"] as? String {
            throw MediaDownloadError.message("cobalt error: \(code)")
        }

        let downloadURLString = json["url"] as? String
            ?? json["tunnel"] as? String
            ?? (json["picker"] as? [[String: Any]])?.compactMap { $0["url"] as? String ?? $0["tunnel"] as? String }.first

        guard let downloadURLString, let downloadURL = URL(string: downloadURLString) else {
            throw MediaDownloadError.cobaltDidNotReturnFile
        }
        try dependencies.networkPolicy.validate(downloadURL)

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
        let (temporaryURL, fileResponse) = try await downloadFile(from: downloadURL, title: sourceURL.host ?? "Media download", progress: progress)
        var shouldRemoveTemporary = true
        defer {
            if shouldRemoveTemporary { try? dependencies.artifactFileSystem.removeItem(at: temporaryURL) }
        }
        let fallbackName = fileResponse?.suggestedFilename ?? "media-\(Int(Date().timeIntervalSince1970))"
        let destination = try dependencies.networkPolicy.reserveDestination(named: fallbackName, in: downloadFolder, fileSystem: dependencies.artifactFileSystem)
        defer { dependencies.networkPolicy.releaseDestination(destination) }
        try dependencies.artifactFileSystem.moveItem(at: temporaryURL, to: destination)
        shouldRemoveTemporary = false
        return destination
    }

    private func runYTDLP(
        _ path: String,
        url: URL,
        progress: (@MainActor @Sendable (MediaDownloadProgress) -> Void)?
    ) async throws {
        let parser = YTDLPProgressParser()
        let staging = try dependencies.artifactFileSystem.temporaryDirectory(prefix: "foundry-ytdlp")
        defer { try? dependencies.artifactFileSystem.removeItem(at: staging) }
        let result = try await dependencies.processRunner.run(
            path: path,
            arguments: ["--newline", "-P", staging.path, "-o", "%(title).200B [%(id)s].%(ext)s", url.absoluteString],
            timeout: 30 * 60,
            outputLimit: 8 * 1024 * 1024,
            environment: nil,
            currentDirectoryURL: nil,
            onOutput: { output in
                guard let update = parser.parse(output.line) else { return }
                Task { @MainActor in progress?(update) }
            }
        )
        guard result.succeeded else {
            throw MediaDownloadError.message(result.stderr.isEmpty ? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let outputs = try dependencies.artifactFileSystem.regularFiles(in: staging)
        guard outputs.isEmpty == false else { throw MediaDownloadError.message("yt-dlp produced no media file") }
        for output in outputs {
            try dependencies.networkPolicy.validateStagedMedia(at: output, fileSystem: dependencies.artifactFileSystem)
        }
        for output in outputs {
            let destination = try dependencies.networkPolicy.reserveDestination(named: output.lastPathComponent, in: downloadFolder, fileSystem: dependencies.artifactFileSystem)
            defer { dependencies.networkPolicy.releaseDestination(destination) }
            try dependencies.artifactFileSystem.moveItem(at: output, to: destination)
        }
    }

    private func downloadFile(
        from sourceURL: URL,
        title: String,
        progress: (@MainActor @Sendable (MediaDownloadProgress) -> Void)?
    ) async throws -> (URL, URLResponse?) {
        let delegate = MediaDownloadDelegate(title: title, progress: progress, policy: dependencies.networkPolicy, fileSystem: dependencies.artifactFileSystem, trustEvaluator: dependencies.trustEvaluator)
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
            delegate.start(sourceURL, session: dependencies.session, continuation: continuation)
            }
        } onCancel: {
            delegate.cancel()
        }
        if let response = result.1 as? HTTPURLResponse {
            let prefix = try dependencies.artifactFileSystem.readData(at: result.0).prefix(4096)
            let bytes = try dependencies.artifactFileSystem.fileSize(at: result.0)
            try dependencies.networkPolicy.validate(response: response, prefix: Data(prefix), receivedBytes: bytes)
        } else {
            throw MediaNetworkPolicyFailure.invalidStatus(0)
        }
        return result
    }

    private func cobaltResponseData(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask {
                let (bytes, response) = try await self.dependencies.session.bytes(for: request)
                var body = Data()
                for try await chunk in bytes {
                    body.append(chunk)
                    if Int64(body.count) > self.dependencies.cobaltResponseMaxBytes {
                        throw MediaNetworkPolicyFailure.responseTooLarge
                    }
                }
                return (body, response)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(self.dependencies.cobaltTimeout))
                throw MediaNetworkPolicyFailure.truncatedBody
            }
            guard let result = try await group.next() else { throw MediaDownloadError.cobaltResponseInvalid }
            group.cancelAll()
            return result
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
        paths.first { (try? dependencies.executableLocator.locate(name: URL(fileURLWithPath: $0).lastPathComponent, candidates: [$0], environment: [:])) != nil }
    }

}

private final class MediaDownloadDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let title: String
    private let progress: (@MainActor @Sendable (MediaDownloadProgress) -> Void)?
    private let policy: MediaNetworkPolicy
    private let fileSystem: any MediaArtifactFileSystem
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<(URL, URLResponse?), Error>?
    private var temporaryURL: URL?
    private var response: URLResponse?
    private var pendingError: Error?
    private var startedAt = Date()
    private var lastReportedAt = Date.distantPast
    private var didFinish = false
    private var redirectCount = 0
    private var certificateHost: String?
    private let trustEvaluator: @Sendable (SecTrust) -> Bool

    init(title: String, progress: (@MainActor @Sendable (MediaDownloadProgress) -> Void)?, policy: MediaNetworkPolicy, fileSystem: any MediaArtifactFileSystem, trustEvaluator: @escaping @Sendable (SecTrust) -> Bool = { trust in var error: CFError?; return SecTrustEvaluateWithError(trust, &error) }) {
        self.title = title
        self.progress = progress
        self.policy = policy
        self.fileSystem = fileSystem
        self.trustEvaluator = trustEvaluator
    }

    func urlSession(_: URLSession, task _: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @Sendable @escaping (URLRequest?) -> Void) {
        do {
            lock.lock()
            redirectCount += 1
            let count = redirectCount
            lock.unlock()
            guard let url = request.url else { throw MediaNetworkPolicyFailure.blockedDestination }
            try policy.validateRedirect(to: url, count: count)
            let pinned = try policy.pinnedURL(for: url)
            lock.lock()
            certificateHost = url.host
            lock.unlock()
            var pinnedRequest = request
            pinnedRequest.url = pinned.url
            pinnedRequest.setValue(pinned.host, forHTTPHeaderField: "Host")
            completionHandler(pinnedRequest)
        } catch {
            completionHandler(nil)
            cancel()
            lock.lock()
            pendingError = error
            lock.unlock()
        }
        _ = response
    }

    func start(_ sourceURL: URL, session: URLSession, continuation: CheckedContinuation<(URL, URLResponse?), Error>) {
        let pinned: (url: URL, host: String)
        do {
            pinned = try policy.pinnedURL(for: sourceURL)
        } catch {
            continuation.resume(throwing: error)
            return
        }
        lock.lock()
        self.continuation = continuation
        startedAt = Date()
        let delegateSession = URLSession(configuration: session.configuration, delegate: self, delegateQueue: nil)
        self.session = delegateSession
        certificateHost = sourceURL.host
        var request = URLRequest(url: pinned.url)
        request.setValue(pinned.host, forHTTPHeaderField: "Host")
        let task = delegateSession.downloadTask(with: request)
        self.task = task
        lock.unlock()
        task.resume()
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @Sendable @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let host = challenge.protectionSpace.host.isEmpty ? nil : challenge.protectionSpace.host else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        lock.lock()
        let expectedHost = certificateHost ?? host
        lock.unlock()
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, expectedHost as CFString))
        guard trustEvaluator(trust) else {
            lock.lock()
            pendingError = MediaNetworkPolicyFailure.blockedDestination
            lock.unlock()
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
        _ = session
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
        if totalBytesWritten > policy.maxBytes {
            lock.lock()
            pendingError = MediaNetworkPolicyFailure.responseTooLarge
            lock.unlock()
            downloadTask.cancel()
            return
        }
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
            try fileSystem.moveItem(at: location, to: stagingURL)
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
            if let temporaryURL { try? fileSystem.removeItem(at: temporaryURL) }
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

enum MediaDownloadError: LocalizedError, Equatable {
    case invalidURL
    case youtubeDependencyMissing
    case invalidProvisioningConsent
    case provisioningUnavailable
    case provisioningFailed
    case cobaltResponseInvalid
    case cobaltDidNotReturnFile
    case retryable(String)
    case message(String)

    var isRetryable: Bool {
        switch self {
        case .retryable, .cobaltResponseInvalid, .cobaltDidNotReturnFile, .provisioningFailed: true
        default: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid media URL"
        case .youtubeDependencyMissing: "yt-dlp is not installed; set it up explicitly before downloading YouTube media"
        case .invalidProvisioningConsent: "Exact yt-dlp provisioning consent is required"
        case .provisioningUnavailable: "yt-dlp provisioning is unavailable"
        case .provisioningFailed: "yt-dlp provisioning failed"
        case .cobaltResponseInvalid: "Cobalt returned an invalid response"
        case .cobaltDidNotReturnFile: "Cobalt did not return a downloadable file"
        case let .retryable(message): message
        case let .message(message): message
        }
    }
}
