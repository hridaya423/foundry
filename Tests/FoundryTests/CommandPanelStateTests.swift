import XCTest
@testable import Foundry
import FoundryDomain
import FoundryServices

@MainActor
final class CommandPanelStateTests: XCTestCase {
    func testMediaURLBecomesSelectedWhenImmediateResultsAlsoMatch() async throws {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(
            diagnostics: diagnostics,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-panel-media-selection-\(UUID().uuidString).json")
        )
        let registry = CommandRegistry(
            providers: [URLCollisionProvider(), MediaDownloadProvider()],
            usageRanking: UsageRankingStore(diagnostics: diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        let state = CommandPanelState(
            registry: registry,
            actionRunner: ActionRunner(diagnostics: diagnostics),
            diagnostics: diagnostics,
            config: config
        )

        state.query = "http://127.0.0.1:8765/video.mp4"
        for _ in 0..<40 where state.selectedResult?.route != .mediaDownload {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(state.selectedResult?.route, .mediaDownload)
        state.shutdown()
    }

    func testClosingPanelDetachesFromABackgroundDownloadWithoutCancellingIt() async throws {
        let media = DelayedMediaDownloadService()
        let diagnostics = DiagnosticsService()
        let config = ConfigService(
            diagnostics: diagnostics,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-panel-state-\(UUID().uuidString).json")
        )
        let registry = CommandRegistry(
            providers: [],
            usageRanking: UsageRankingStore(diagnostics: diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
        let state = CommandPanelState(
            registry: registry,
            actionRunner: ActionRunner(diagnostics: diagnostics, mediaDownloadService: media),
            diagnostics: diagnostics,
            config: config
        )
        state.results = [CommandResult(
            id: "test.background-download",
            title: "Download",
            subtitle: nil,
            icon: CommandIcon(fallback: "D"),
            primaryAction: CommandAction(
                id: "test.background-download.perform",
                title: "Download",
                kind: .downloadMedia(url: "https://example.com/file.mp4")
            ),
            secondaryActions: []
        )]
        state.selectedResultID = "test.background-download"

        let execution = Task { await state.executeSelectedResult() }
        try await Task.sleep(for: .milliseconds(20))
        state.panelWillClose()

        let shouldDismiss = await execution.value
        let completed = await media.didComplete()

        XCTAssertFalse(shouldDismiss)
        XCTAssertTrue(completed)
        state.shutdown()
    }

    private actor DelayedMediaDownloadService: MediaDownloading {
        nonisolated let downloadFolder = URL(fileURLWithPath: "/tmp")
        private var completed = false

        func download(
            urlString: String,
            status: (@MainActor @Sendable (String) -> Void)?
        ) async throws -> String {
            try await Task.sleep(for: .milliseconds(100))
            completed = true
            return "Downloaded file.mp4"
        }

        func didComplete() -> Bool {
            completed
        }
    }
}

private struct URLCollisionProvider: CommandProvider {
    let id = "test.url-collision"
    var searchPolicy: CommandProviderSearchPolicy { CommandProviderSearchPolicy(tier: .immediate) }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        guard request.query.contains("127") else { return [] }
        return [CommandResult(
            id: "test.kill-port",
            title: "Kill Port 127",
            subtitle: "Unrelated immediate result",
            icon: CommandIcon(fallback: "P"),
            primaryAction: CommandAction(id: "test.kill-port.perform", title: "Run", kind: .log("collision")),
            secondaryActions: []
        )]
    }
}
