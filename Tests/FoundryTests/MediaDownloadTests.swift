import Foundation
import XCTest
@testable import Foundry
import FoundryDomain
import FoundryServices

final class MediaDownloadTests: XCTestCase {
    func testProgressThrottleAlwaysPublishesSignificantUpdates() {
        let throttle = MediaProgressThrottle()
        let ordinary = MediaDownloadProgress(phase: .downloading, title: "Video", message: "Downloading", bytesReceived: 1, totalBytes: 10, fractionCompletedOverride: nil, speedBytesPerSecond: nil, estimatedTimeRemaining: nil, currentItem: nil, totalItems: nil)
        let significant = MediaDownloadProgress(phase: .downloading, title: "Video", message: "Finishing Video", bytesReceived: 10, totalBytes: 10, fractionCompletedOverride: nil, speedBytesPerSecond: nil, estimatedTimeRemaining: nil, currentItem: nil, totalItems: nil)

        XCTAssertTrue(throttle.shouldReport(ordinary))
        XCTAssertFalse(throttle.shouldReport(ordinary))
        XCTAssertTrue(throttle.shouldReport(significant))
    }

    func testYouTubeDownloadResultDoesNotWaitForOptionalMetadata() async {
        let provider = MediaDownloadProvider()

        let results = await provider.search(CommandSearchRequest(query: "https://www.youtube.com/watch?v=video"))

        XCTAssertEqual(results.first?.route, .mediaDownload)
        XCTAssertEqual(results.first?.subtitle, "https://www.youtube.com/watch?v=video\nwatch · save via YouTube · yt-dlp (automatic setup) to Downloads")
        XCTAssertEqual(results.first?.icon.thumbnailURL, URL(string: "https://i.ytimg.com/vi/video/hqdefault.jpg"))
    }

    func testNonHTTPYouTubeURLDoesNotReachYTDLP() async {
        let service = MediaDownloadService(dependencies: .init(
            executableLocator: ExecutableLocator(fileInfo: { _ in true }),
            processRunner: RejectingProcessRunner(),
            networkPolicy: MediaNetworkPolicy(locator: EmptyMediaNetworkLocator())
        ))

        do {
            _ = try await service.download(urlString: "ftp://youtube.com/watch?v=video")
            XCTFail("Expected the URL policy to reject FTP")
        } catch {
            XCTAssertEqual(error as? MediaNetworkPolicyFailure, .blockedDestination)
        }
    }

    func testYouTubeDownloadIsPassedToYTDLPWithoutFoundryDNSPreflight() async {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destination) }
        let service = MediaDownloadService(dependencies: .init(
            processRunner: RejectingProcessRunner(),
            destination: destination,
            networkPolicy: MediaNetworkPolicy(locator: EmptyMediaNetworkLocator())
        ))

        do {
            _ = try await service.download(urlString: "https://www.youtube.com/watch?v=video")
            XCTFail("Expected yt-dlp execution to stop the test")
        } catch {
            XCTAssertNotEqual(error as? MediaNetworkPolicyFailure, .blockedDestination)
        }
    }

    func testYouTubeDownloadReportsMissingDependencyWhenNeitherYTDLPNorHomebrewExists() async {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destination) }
        let service = MediaDownloadService(dependencies: .init(
            executableLocator: ExecutableLocator(fileInfo: { _ in false }),
            processRunner: RejectingProcessRunner(),
            destination: destination,
            networkPolicy: MediaNetworkPolicy(locator: EmptyMediaNetworkLocator())
        ))

        do {
            _ = try await service.download(urlString: "https://www.youtube.com/watch?v=video")
            XCTFail("Expected missing dependency")
        } catch {
            XCTAssertEqual(error as? MediaDownloadError, .youtubeDependencyMissing)
        }
    }

    func testYouTubeDownloadInstallsYTDLPWithHomebrewWhenMissing() async {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destination) }
        let availability = ExecutableAvailability()
        let runner = AutoInstallingProcessRunner(availability: availability)
        let service = MediaDownloadService(dependencies: .init(
            executableLocator: ExecutableLocator(fileInfo: availability.exists),
            processRunner: runner,
            destination: destination,
            networkPolicy: MediaNetworkPolicy(locator: EmptyMediaNetworkLocator())
        ))

        do {
            _ = try await service.download(urlString: "https://www.youtube.com/watch?v=video")
            XCTFail("Expected the fake yt-dlp execution to stop the test")
        } catch is CancellationError {
            XCTAssertEqual(runner.paths, ["/opt/homebrew/bin/brew", "/opt/homebrew/bin/yt-dlp"])
            XCTAssertTrue(runner.arguments[1].contains("youtube:player_client=android,web"))
            XCTAssertTrue(runner.arguments[1].contains("bv*[vcodec^=avc1][height<=1080]+ba[ext=m4a]/b[ext=mp4]/b"))
            XCTAssertTrue(runner.arguments[1].contains("--merge-output-format"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConcurrentYouTubeDownloadsShareAutomaticYTDLPInstallation() async {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destination) }
        let availability = ExecutableAvailability()
        let runner = AutoInstallingProcessRunner(availability: availability, installDelay: .milliseconds(50))
        let service = MediaDownloadService(dependencies: .init(
            executableLocator: ExecutableLocator(fileInfo: availability.exists),
            processRunner: runner,
            destination: destination,
            networkPolicy: MediaNetworkPolicy(locator: EmptyMediaNetworkLocator())
        ))

        async let first = service.download(urlString: "https://www.youtube.com/watch?v=first")
        async let second = service.download(urlString: "https://www.youtube.com/watch?v=second")
        _ = await (try? first, try? second)

        XCTAssertEqual(runner.paths.filter { $0 == "/opt/homebrew/bin/brew" }.count, 1)
    }

    func testCancellingCobaltDownloadCancelsTheUnderlyingRequest() async throws {
        let started = expectation(description: "Cobalt request started")
        let stopped = expectation(description: "Cobalt request stopped")
        DelayedMediaURLProtocol.onStart = { started.fulfill() }
        DelayedMediaURLProtocol.onStop = { stopped.fulfill() }
        defer { DelayedMediaURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedMediaURLProtocol.self]
        let service = MediaDownloadService(dependencies: .init(
            session: URLSession(configuration: configuration),
            networkPolicy: MediaNetworkPolicy(locator: StaticPublicMediaNetworkLocator()),
            cobaltTimeout: 60
        ))
        let operation = Task {
            try await service.download(urlString: "https://example.com/watch")
        }

        await fulfillment(of: [started], timeout: 1)
        operation.cancel()
        await fulfillment(of: [stopped], timeout: 1)

        do {
            _ = try await operation.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }
    }

    func testCancellingDirectDownloadCancelsTheUnderlyingRequest() async throws {
        let started = expectation(description: "Direct request started")
        let stopped = expectation(description: "Direct request stopped")
        DelayedMediaURLProtocol.onStart = { started.fulfill() }
        DelayedMediaURLProtocol.onStop = { stopped.fulfill() }
        defer { DelayedMediaURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedMediaURLProtocol.self]
        let service = MediaDownloadService(dependencies: .init(
            session: URLSession(configuration: configuration),
            networkPolicy: MediaNetworkPolicy(locator: StaticPublicMediaNetworkLocator())
        ))
        let operation = Task {
            try await service.download(urlString: "https://example.com/video.mp4")
        }

        await fulfillment(of: [started], timeout: 1)
        operation.cancel()
        await fulfillment(of: [stopped], timeout: 1)

        do {
            _ = try await operation.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }
    }

    func testYTDLPParserReportsPlaylistPositionAndByteProgress() {
        let parser = YTDLPProgressParser()

        XCTAssertEqual(parser.parse("[download] Downloading item 3 of 12")?.currentItem, 3)
        let progress = parser.parse("[download] 25.0% of 4.00MiB at 1.00MiB/s ETA 00:03")

        XCTAssertEqual(progress?.totalItems, 12)
        XCTAssertEqual(progress?.fractionCompleted ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(progress?.totalBytes, 4 * 1_048_576)
        XCTAssertEqual(progress?.bytesReceived, 1 * 1_048_576)
        XCTAssertEqual(progress?.speedBytesPerSecond ?? -1, 1 * 1_048_576, accuracy: 0.0001)
        XCTAssertEqual(progress?.estimatedTimeRemaining ?? -1, 3, accuracy: 0.0001)
    }

    func testYTDLPParserExtractsProgressFieldsWhenOutputOrderVaries() {
        let parser = YTDLPProgressParser()

        let progress = parser.parse("[download] ETA 00:03 at 1.00MiB/s 25.0% of 4.00MiB")

        XCTAssertEqual(progress?.fractionCompleted ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(progress?.totalBytes, 4 * 1_048_576)
        XCTAssertEqual(progress?.speedBytesPerSecond ?? -1, 1 * 1_048_576, accuracy: 0.0001)
        XCTAssertEqual(progress?.estimatedTimeRemaining ?? -1, 3, accuracy: 0.0001)
    }

    func testYTDLPParserHandlesLongOutputWorkload() {
        let line = "[download] 42.0% of ~ 10.0MiB at 2.0MiB/s ETA 00:03"
        var parsed = 0
        let parser = YTDLPProgressParser()

        measure {
            for _ in 0..<10_000 {
                if parser.parse(line) != nil { parsed += 1 }
            }
        }

        XCTAssertEqual(parsed, 100_000)
    }

    func testYTDLPParserUsesFilenameInsteadOfAbsoluteDestinationPath() {
        let parser = YTDLPProgressParser()

        let progress = parser.parse(#"[Merger] Merging formats into "/Users/person/Downloads/A useful video.webm""#)

        XCTAssertEqual(progress?.title, "A useful video.webm")
        XCTAssertEqual(progress?.message, "Finishing A useful video.webm")
    }

    func testMediaURLParserAcceptsMultipleLinksAndRemovesDuplicates() {
        let urls = MediaDownloadProvider.mediaURLs(in: """
        https://example.com/one.mp4
        https://example.com/two.mp3 https://example.com/one.mp4
        https://example.com/not-media.txt
        """)

        XCTAssertEqual(urls.map(\.lastPathComponent), ["one.mp4", "two.mp3"])
    }

    func testMediaCapabilitiesReportInstalledYTDLPAsReady() {
        let service = MediaDownloadService(dependencies: .init(
            executableLocator: ExecutableLocator(fileInfo: { $0 == "/opt/homebrew/bin/yt-dlp" })
        ))

        XCTAssertEqual(service.mediaCapabilities().youtube, .ready(label: "YouTube · yt-dlp ready"))
    }

    func testMediaCapabilitiesReportAutomaticSetupWhenHomebrewIsAvailable() {
        let service = MediaDownloadService(dependencies: .init(
            executableLocator: ExecutableLocator(fileInfo: { $0 == "/opt/homebrew/bin/brew" })
        ))

        XCTAssertEqual(service.mediaCapabilities().youtube, .ready(label: "YouTube · yt-dlp installs automatically"))
    }

    @MainActor
    func testDownloadManagerKeepsActiveItemsUntilFinished() {
        let manager = MediaDownloadManager()
        let id = UUID()
        manager.start(id: id, sourceURL: "https://example.com/video.mp4")

        XCTAssertEqual(manager.activeCount, 1)
        manager.update(id: id, progress: MediaDownloadProgress(
            phase: .downloading,
            title: "video.mp4",
            message: "Downloading",
            bytesReceived: 50,
            totalBytes: 100,
            fractionCompletedOverride: nil,
            speedBytesPerSecond: 25,
            estimatedTimeRemaining: 2,
            currentItem: nil,
            totalItems: nil
        ))
        XCTAssertEqual(manager.items.first?.progress.fractionCompleted, 0.5)

        manager.complete(id: id, message: "Downloaded video.mp4")
        XCTAssertEqual(manager.activeCount, 0)
        XCTAssertEqual(manager.items.first?.status, .completed)
        manager.clearFinished()
        XCTAssertTrue(manager.items.isEmpty)
    }

    @MainActor
    func testActionRunnerPublishesStructuredProgressToTheManager() async {
        let manager = MediaDownloadManager()
        let runner = ActionRunner(
            diagnostics: DiagnosticsService(),
            mediaDownloadService: ProgressMediaDownloadService(),
            mediaDownloadManager: manager
        )
        let request = CommandExecutionRequest(
            commandID: "test.media.progress",
            action: CommandAction(
                id: "test.media.progress.perform",
                title: "Download",
                kind: .downloadMedia(url: "https://example.com/video.mp4")
            )
        )

        let outcome = await runner.execute(request) { _ in }

        guard case .stayOpen(message: "Downloaded video.mp4") = outcome else {
            return XCTFail("Expected the media download to complete")
        }
        XCTAssertEqual(manager.items.first?.status, .completed)
        XCTAssertEqual(manager.items.first?.progress.fractionCompleted, 1)
    }

    @MainActor
    func testBatchActionStartsEveryLinkAsAnIndependentDownload() async throws {
        let service = RecordingMediaDownloadService()
        let manager = MediaDownloadManager()
        let runner = ActionRunner(
            diagnostics: DiagnosticsService(),
            mediaDownloadService: service,
            mediaDownloadManager: manager
        )
        let urls = ["https://example.com/one.mp4", "https://example.com/two.mp4"]
        let request = CommandExecutionRequest(
            commandID: "test.media.batch",
            action: CommandAction(id: "test.media.batch.perform", title: "Download All", kind: .downloadMediaBatch(urls: urls))
        )

        let outcome = await runner.execute(request) { _ in }
        XCTAssertEqual(outcome, .open(route: .mediaDownloads))

        for _ in 0..<20 where await service.urls().count < urls.count {
            try await Task.sleep(for: .milliseconds(10))
        }
        let recordedURLs = await service.urls()
        XCTAssertEqual(Set(recordedURLs), Set(urls))
        XCTAssertEqual(manager.items.count, 2)
    }

    func testProcessRunnerPublishesCompleteOutputLinesWithoutDroppingResult() {
        let collector = OutputCollector()
        let result = ProcessRunner.runSynchronously(
            path: "/bin/sh",
            arguments: ["-c", "printf 'out-one\\nout-two\\n'; printf 'err-one\\n' >&2"],
            onOutput: { collector.append($0) }
        )

        XCTAssertEqual(result?.exitCode, 0)
        XCTAssertEqual(result?.stdout, "out-one\nout-two\n")
        XCTAssertEqual(result?.stderr, "err-one\n")
        XCTAssertEqual(collector.lines.count, 3)
        XCTAssertTrue(collector.lines.contains(ProcessOutputLine(stream: .stdout, line: "out-one")))
        XCTAssertTrue(collector.lines.contains(ProcessOutputLine(stream: .stdout, line: "out-two")))
        XCTAssertTrue(collector.lines.contains(ProcessOutputLine(stream: .stderr, line: "err-one")))
    }
}

private struct EmptyMediaNetworkLocator: MediaNetworkAddressLocating {
    func addresses(for _: String) -> [String] { [] }
}

private struct StaticPublicMediaNetworkLocator: MediaNetworkAddressLocating {
    func addresses(for _: String) -> [String] { ["93.184.216.34"] }
}

private final class DelayedMediaURLProtocol: URLProtocol {
    nonisolated(unsafe) static var onStart: (() -> Void)?
    nonisolated(unsafe) static var onStop: (() -> Void)?

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.onStart?() }
    override func stopLoading() { Self.onStop?() }

    static func reset() {
        onStart = nil
        onStop = nil
    }
}

private struct RejectingProcessRunner: ProcessRunning {
    func run(path _: String, arguments _: [String], timeout _: TimeInterval, outputLimit _: Int, environment _: [String: String]?, currentDirectoryURL _: URL?, onOutput _: (@Sendable (ProcessOutputLine) -> Void)?) async throws -> ProcessResult {
        throw CancellationError()
    }
}

private final class ExecutableAvailability: @unchecked Sendable {
    private let lock = NSLock()
    private var ytDLPInstalled = false

    func exists(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return path == "/opt/homebrew/bin/brew" || (path == "/opt/homebrew/bin/yt-dlp" && ytDLPInstalled)
    }

    func installYTDLP() {
        lock.lock()
        ytDLPInstalled = true
        lock.unlock()
    }
}

private final class AutoInstallingProcessRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let availability: ExecutableAvailability
    private let installDelay: Duration
    private var recordedPaths: [String] = []
    private var recordedArguments: [[String]] = []

    init(availability: ExecutableAvailability, installDelay: Duration = .zero) {
        self.availability = availability
        self.installDelay = installDelay
    }

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedPaths
    }

    var arguments: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return recordedArguments
    }

    func run(path: String, arguments: [String], timeout _: TimeInterval, outputLimit _: Int, environment _: [String: String]?, currentDirectoryURL _: URL?, onOutput _: (@Sendable (ProcessOutputLine) -> Void)?) async throws -> ProcessResult {
        record(path, arguments: arguments)
        guard path == "/opt/homebrew/bin/brew" else { throw CancellationError() }
        try await Task.sleep(for: installDelay)
        availability.installYTDLP()
        return try await ProcessRunner.run(path: "/usr/bin/true", arguments: [])
    }

    private func record(_ path: String, arguments: [String]) {
        lock.lock()
        recordedPaths.append(path)
        recordedArguments.append(arguments)
        lock.unlock()
    }
}

private actor ProgressMediaDownloadService: MediaDownloading {
    nonisolated let downloadFolder = URL(fileURLWithPath: "/tmp")

    func download(
        urlString: String,
        status: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> String {
        try await download(urlString: urlString, status: status, progress: nil)
    }

    func download(
        urlString _: String,
        status: (@MainActor @Sendable (String) -> Void)?,
        progress: (@MainActor @Sendable (MediaDownloadProgress) -> Void)?
    ) async throws -> String {
        if let status { await status("Downloading video.mp4") }
        if let progress {
            await progress(MediaDownloadProgress(
                phase: .downloading,
                title: "video.mp4",
                message: "Downloading",
                bytesReceived: 100,
                totalBytes: 100,
                fractionCompletedOverride: nil,
                speedBytesPerSecond: 25,
                estimatedTimeRemaining: 0,
                currentItem: nil,
                totalItems: nil
            ))
        }
        return "Downloaded video.mp4"
    }
}

private actor RecordingMediaDownloadService: MediaDownloading {
    nonisolated let downloadFolder = URL(fileURLWithPath: "/tmp")
    private var recordedURLs: [String] = []

    func download(
        urlString: String,
        status _: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> String {
        recordedURLs.append(urlString)
        return "Downloaded \(URL(string: urlString)?.lastPathComponent ?? "media")"
    }

    func urls() -> [String] { recordedURLs }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ProcessOutputLine] = []

    var lines: [ProcessOutputLine] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ line: ProcessOutputLine) {
        lock.lock()
        storage.append(line)
        lock.unlock()
    }
}
