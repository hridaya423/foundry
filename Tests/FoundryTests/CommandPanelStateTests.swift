import XCTest
@testable import Foundry
import FoundryDomain
import FoundryServices

@MainActor
final class CommandPanelStateTests: XCTestCase {
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
