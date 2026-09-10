import Foundation
import Security
import FoundryServices

protocol MediaDownloading: Sendable {
    var downloadFolder: URL { get }

    func mediaCapabilities() -> MediaDownloadCapabilities

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
            cobalt: .unavailable(label: "Cobalt · unavailable", reason: "The hosted API requires authorization; yt-dlp is used instead"),
            youtube: .ready(label: "YouTube · yt-dlp automatic setup")
        )
    }


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
        let cobaltAuthorization: String?
        let executableLocator: ExecutableLocator
        let processRunner: any ProcessRunning
        let destination: URL?
        let artifactFileSystem: any MediaArtifactFileSystem
        let networkPolicy: MediaNetworkPolicy
        let cobaltResponseMaxBytes: Int64
        let cobaltTimeout: TimeInterval
        let trustEvaluator: @Sendable (SecTrust) -> Bool

        init(
            session: URLSession = URLSession(configuration: .ephemeral),
            cobaltEndpoint: URL? = nil,
            cobaltAuthorization: String? = nil,
            executableLocator: ExecutableLocator = ExecutableLocator(),
            processRunner: any ProcessRunning = SystemProcessRunner(),
            destination: URL? = nil,
            artifactFileSystem: any MediaArtifactFileSystem = FileManager.default,
            networkPolicy: MediaNetworkPolicy = MediaNetworkPolicy(),
            cobaltResponseMaxBytes: Int64 = 1_048_576,
            cobaltTimeout: TimeInterval = 20,
            trustEvaluator: @escaping @Sendable (SecTrust) -> Bool = { trust in var error: CFError?; return SecTrustEvaluateWithError(trust, &error) }
        ) {
            self.session = session
            self.cobaltEndpoint = cobaltEndpoint
                ?? ProcessInfo.processInfo.environment["FOUNDRY_COBALT_ENDPOINT"].flatMap(URL.init)
                ?? URL(string: "https://api.cobalt.tools/")!
            self.cobaltAuthorization = cobaltAuthorization
                ?? ProcessInfo.processInfo.environment["FOUNDRY_COBALT_AUTHORIZATION"]
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
    private let ytDLPInstallGate = YTDLPInstallGate()

    init(dependencies: Dependencies = Dependencies()) {
        self.dependencies = dependencies
    }

    var downloadFolder: URL {
        dependencies.destination ?? MediaDownloadDestination.folder
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
        let initialTitle = url.lastPathComponent.isEmpty ? "Media download" : url.lastPathComponent

        do {
            let folder = downloadFolder
            try dependencies.artifactFileSystem.createDirectory(at: folder)
            emit(.starting(title: initialTitle), progress)
            let files: [URL]
            let message: String

            if MediaDownloadProvider.isDirectMediaFile(url) {
                try dependencies.networkPolicy.validate(url)
                let file = try await downloadDirectFile(url, downloadFolder: folder, status: status, progress: progress)
                files = [file]
                message = "Downloaded \(file.lastPathComponent)"
            } else if isYouTube(url) {
                report("Preparing yt-dlp", status)
                let executable = try await installYTDLPIfNeeded()
                report(isPlaylist(url) ? "Downloading playlist" : "Downloading media", status)
                files = try await runYTDLP(executable, url: url, downloadFolder: folder, progress: progress)
                message = "Downloaded YouTube media to \(folder.path)"
            } else {
                try dependencies.networkPolicy.validate(url)
                if cobaltIsConfigured {
                    do {
                        let file = try await downloadWithCobalt(url, downloadFolder: folder, status: status, progress: progress)
                        files = [file]
                        message = "Downloaded \(file.lastPathComponent)"
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        report("Cobalt unavailable, trying yt-dlp", status)
                        let executable = try await installYTDLPIfNeeded()
                        report("Downloading media", status)
                        files = try await runYTDLP(executable, url: url, downloadFolder: folder, progress: progress)
                        message = "Downloaded media with yt-dlp"
                    }
                } else {
                    report("Preparing yt-dlp", status)
                    let executable = try await installYTDLPIfNeeded()
                    report("Downloading media", status)
                    files = try await runYTDLP(executable, url: url, downloadFolder: folder, progress: progress)
                    message = "Downloaded media with yt-dlp"
                }
            }
            var completed = MediaDownloadProgress.starting(title: files.count == 1 ? files[0].lastPathComponent : "\(files.count) media files")
            completed.phase = .completed
            completed.message = message
            completed.outputURLs = files
            await MainActor.run { [completed] in progress?(completed) }
            return message
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
        downloadFolder: URL,
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
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased() else { return false }
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
        let youtube: MediaDownloadCapability
        if (try? existingYTDLP()) != nil {
            youtube = .ready(label: "YouTube · yt-dlp ready")
        } else if firstExistingPath(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) != nil {
            youtube = .ready(label: "YouTube · yt-dlp installs automatically")
        } else {
            youtube = .unavailable(label: "YouTube · yt-dlp", reason: "Homebrew is required for automatic setup")
        }
        return MediaDownloadCapabilities(
            direct: .ready(label: "Direct links · ready"),
            cobalt: cobaltIsConfigured
                ? .ready(label: "Cobalt · configured")
                : .unavailable(label: "Cobalt · unavailable", reason: "The hosted API requires authorization; yt-dlp is used instead"),
            youtube: youtube
        )
    }

    private var cobaltIsConfigured: Bool {
        if let authorization = dependencies.cobaltAuthorization?.trimmingCharacters(in: .whitespacesAndNewlines), authorization.isEmpty == false {
            return true
        }
        return dependencies.cobaltEndpoint.host?.lowercased() != "api.cobalt.tools"
    }

    private func installYTDLPIfNeeded() async throws -> String {
        if let executable = try? existingYTDLP() { return executable }
        guard let brew = firstExistingPath(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) else { throw MediaDownloadError.youtubeDependencyMissing }
        return try await ytDLPInstallGate.install {
            try Task.checkCancellation()
            let result = try await self.dependencies.processRunner.run(path: brew, arguments: ["install", "yt-dlp"], timeout: 30 * 60, outputLimit: 2 * 1024 * 1024, environment: nil, currentDirectoryURL: nil, onOutput: nil)
            guard result.succeeded else { throw MediaDownloadError.message(result.stderr.isEmpty ? "Homebrew could not install yt-dlp" : result.stderr) }
            try Task.checkCancellation()
            return try self.existingYTDLP()
        }
    }

    private func downloadWithCobalt(
        _ sourceURL: URL,
        downloadFolder: URL,
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
        if let authorization = dependencies.cobaltAuthorization?.trimmingCharacters(in: .whitespacesAndNewlines), authorization.isEmpty == false {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["url": sourceURL.absoluteString])

        let (data, cobaltResponse) = try await cobaltResponseData(request)
        if let cobaltResponse = cobaltResponse as? HTTPURLResponse, !(200..<300).contains(cobaltResponse.statusCode) {
            throw MediaNetworkPolicyFailure.invalidStatus(cobaltResponse.statusCode)
        }
        let response = try CobaltMediaResponse.parse(data: data)
        let downloadURL = response.url
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
        let fallbackName = fileResponse?.suggestedFilename ?? response.filename ?? "media-\(Int(Date().timeIntervalSince1970))"
        let destination = try dependencies.networkPolicy.reserveDestination(named: fallbackName, in: downloadFolder, fileSystem: dependencies.artifactFileSystem)
        defer { dependencies.networkPolicy.releaseDestination(destination) }
        try dependencies.artifactFileSystem.moveItem(at: temporaryURL, to: destination)
        shouldRemoveTemporary = false
        return destination
    }

    private func runYTDLP(
        _ path: String,
        url: URL,
        downloadFolder: URL,
        progress: (@MainActor @Sendable (MediaDownloadProgress) -> Void)?
    ) async throws -> [URL] {
        let parser = YTDLPProgressParser()
        let progressThrottle = MediaProgressThrottle()
        let staging = try dependencies.artifactFileSystem.temporaryDirectory(prefix: "foundry-ytdlp")
        defer { try? dependencies.artifactFileSystem.removeItem(at: staging) }
        let result = try await dependencies.processRunner.run(
            path: path,
            arguments: ["--newline", "--extractor-args", "youtube:player_client=android,web", "-f", "bv*[vcodec^=avc1][height<=1080]+ba[ext=m4a]/b[ext=mp4]/b", "--merge-output-format", "mp4", "-P", staging.path, "-o", "%(title).200B [%(id)s].%(ext)s", url.absoluteString],
            timeout: 30 * 60,
            outputLimit: 8 * 1024 * 1024,
            environment: nil,
            currentDirectoryURL: nil,
            onOutput: { output in
                guard let update = parser.parse(output.line) else { return }
                guard progressThrottle.shouldReport(update) else { return }
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
        var files: [URL] = []
        for output in outputs {
            let destination = try dependencies.networkPolicy.reserveDestination(named: output.lastPathComponent, in: downloadFolder, fileSystem: dependencies.artifactFileSystem)
            defer { dependencies.networkPolicy.releaseDestination(destination) }
            try dependencies.artifactFileSystem.moveItem(at: output, to: destination)
            files.append(destination)
        }
        return files
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
                let delegate = CobaltResponseDelegate(policy: self.dependencies.networkPolicy, maxBytes: self.dependencies.cobaltResponseMaxBytes, trustEvaluator: self.dependencies.trustEvaluator)
                return try await delegate.start(request, session: self.dependencies.session)
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

struct CobaltMediaResponse: Equatable, Sendable {
    let url: URL
    let filename: String?

    static func parse(data: Data) throws -> CobaltMediaResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MediaDownloadError.cobaltResponseInvalid
        }

        if let status = json["status"] as? String, status == "error" {
            let code = (json["error"] as? [String: Any])?["code"] as? String ?? "unknown"
            throw MediaDownloadError.message("cobalt error: \(code)")
        }

        let pickerURL = (json["picker"] as? [[String: Any]])?.compactMap { item in
            item["url"] as? String ?? item["tunnel"] as? String
        }.first
        let tunnelURL = (json["tunnel"] as? [String])?.first
        let urlString = json["url"] as? String
            ?? json["tunnel"] as? String
            ?? tunnelURL
            ?? pickerURL
        guard let urlString, let url = URL(string: urlString) else {
            throw MediaDownloadError.cobaltDidNotReturnFile
        }

        let outputFilename = (json["output"] as? [String: Any])?["filename"] as? String
        return CobaltMediaResponse(
            url: url,
            filename: json["filename"] as? String ?? outputFilename
        )
    }
}

private final class CobaltResponseDelegate: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let policy: MediaNetworkPolicy
    private let maxBytes: Int64
    private let trustEvaluator: @Sendable (SecTrust) -> Bool
    private var body = Data()
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var response: URLResponse?
    private var pendingError: Error?
    private var redirectCount = 0
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var cancelled = false

    init(policy: MediaNetworkPolicy, maxBytes: Int64, trustEvaluator: @escaping @Sendable (SecTrust) -> Bool) {
        self.policy = policy
        self.maxBytes = maxBytes
        self.trustEvaluator = trustEvaluator
    }

    func start(_ request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !cancelled else {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let delegateSession = URLSession(configuration: session.configuration, delegate: self, delegateQueue: nil)
                self.session = delegateSession
                let task = delegateSession.dataTask(with: request)
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let continuation = self.continuation
        self.continuation = nil
        let task = self.task
        self.task = nil
        let session = self.session
        self.session = nil
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
        continuation?.resume(throwing: CancellationError())
    }

    func urlSession(_: URLSession, task _: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @Sendable @escaping (URLRequest?) -> Void) {
        do {
            guard let url = request.url else { throw MediaNetworkPolicyFailure.blockedDestination }
            lock.lock()
            redirectCount += 1
            let count = redirectCount
            lock.unlock()
            try policy.validateRedirect(from: response.url, to: url, count: count)
            completionHandler(request)
        } catch {
            lock.lock()
            pendingError = error
            lock.unlock()
            completionHandler(nil)
        }
    }

    func urlSession(_: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @Sendable @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let host = challenge.protectionSpace.host.isEmpty ? nil : challenge.protectionSpace.host else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        guard trustEvaluator(trust) else {
            lock.lock()
            pendingError = MediaNetworkPolicyFailure.blockedDestination
            lock.unlock()
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @Sendable @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        self.response = response
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        body.append(data)
        let tooLarge = Int64(body.count) > maxBytes
        let task = self.task
        lock.unlock()
        if tooLarge {
            lock.lock()
            pendingError = MediaNetworkPolicyFailure.responseTooLarge
            lock.unlock()
            task?.cancel()
        }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let result = (continuation, body, response, pendingError ?? error)
        continuation = nil
        let session = self.session
        lock.unlock()
        if let error = result.3 {
            result.0?.resume(throwing: error)
        } else if let response = result.2 {
            result.0?.resume(returning: (result.1, response))
        } else {
            result.0?.resume(throwing: MediaDownloadError.cobaltResponseInvalid)
        }
        session?.finishTasksAndInvalidate()
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
            try policy.validateRedirect(from: response.url, to: url, count: count)
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
            cancel(with: error)
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
        guard didFinish == false else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
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

    func cancel(with error: Error = CancellationError()) {
        lock.lock()
        guard didFinish == false else {
            lock.unlock()
            return
        }
        didFinish = true
        pendingError = error
        let continuation = self.continuation
        self.continuation = nil
        let task = self.task
        self.task = nil
        let session = self.session
        self.session = nil
        let temporaryURL = self.temporaryURL
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
        if let temporaryURL { try? fileSystem.removeItem(at: temporaryURL) }
        continuation?.resume(throwing: error)
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
    private static let itemRegex = try! NSRegularExpression(pattern: #"Downloading item\s+(\d+)\s+of\s+(\d+)"#, options: [.caseInsensitive])
    private static let mergingRegex = try! NSRegularExpression(pattern: #"Merging formats into\s+[\"'](.+)[\"']"#, options: [.caseInsensitive])
    private static let downloadedRegex = try! NSRegularExpression(pattern: #"\[download\]\s+(.+)\s+has already been downloaded"#, options: [.caseInsensitive])
    private static let progressRegex = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)%(?:.*?of\s+(?:~\s*)?([0-9]+(?:\.[0-9]+)?\s*(?:B|KiB|MiB|GiB|TiB)))?(?:.*?at\s+([0-9]+(?:\.[0-9]+)?\s*(?:B|KiB|MiB|GiB|TiB))/s)?(?:.*?ETA\s+([0-9:]+))?"#, options: [.caseInsensitive])
    private static let totalBytesRegex = try! NSRegularExpression(pattern: #"of\s+(?:~\s*)?([0-9]+(?:\.[0-9]+)?\s*(?:B|KiB|MiB|GiB|TiB))"#, options: [.caseInsensitive])
    private static let speedRegex = try! NSRegularExpression(pattern: #"at\s+([0-9]+(?:\.[0-9]+)?\s*(?:B|KiB|MiB|GiB|TiB))/s"#, options: [.caseInsensitive])
    private static let etaRegex = try! NSRegularExpression(pattern: #"ETA\s+([0-9:]+)"#, options: [.caseInsensitive])
    private static let byteValueRegex = try! NSRegularExpression(pattern: #"^\s*([0-9]+(?:\.[0-9]+)?)\s*(B|KiB|MiB|GiB|TiB)\s*$"#, options: [.caseInsensitive])
    private let lock = NSLock()
    private var title = "YouTube media"
    private var currentItem: Int?
    private var totalItems: Int?

    func parse(_ line: String) -> MediaDownloadProgress? {
        lock.lock()
        defer { lock.unlock() }

        if let itemMatch = Self.match(Self.itemRegex, in: line) {
            currentItem = Int(itemMatch[0])
            totalItems = Int(itemMatch[1])
            return makeProgress(message: "Downloading item \(itemMatch[0]) of \(itemMatch[1])")
        }

        if let destinationRange = line.range(of: "Destination:") {
            let nextTitle = line[destinationRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if nextTitle.isEmpty == false { title = Self.displayName(nextTitle) }
            return makeProgress(message: "Downloading \(title)")
        }

        if let merged = Self.match(Self.mergingRegex, in: line)?.first {
            title = Self.displayName(merged)
            return makeProgress(message: "Finishing \(title)")
        }

        if let existing = Self.match(Self.downloadedRegex, in: line)?.first {
            title = Self.displayName(existing)
            return makeProgress(message: "Already downloaded")
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

final class MediaProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private let clock = ContinuousClock()
    private var lastReportedAt: ContinuousClock.Instant?

    func shouldReport(_ progress: MediaDownloadProgress) -> Bool {
        let now = clock.now
        lock.lock()
        defer { lock.unlock() }
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

private actor YTDLPInstallGate {
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
        case .invalidURL: "Invalid media URL"
        case .youtubeDependencyMissing: "yt-dlp is missing and Homebrew was not found"
        case .cobaltResponseInvalid: "Cobalt returned an invalid response"
        case .cobaltDidNotReturnFile: "Cobalt did not return a downloadable file"
        case let .retryable(message): message
        case let .message(message): message
        }
    }
}
