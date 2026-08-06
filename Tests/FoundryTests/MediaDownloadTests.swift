import Foundation
import XCTest
@testable import Foundry
import FoundryServices

final class MediaDownloadTests: XCTestCase {
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
