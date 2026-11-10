import Foundation
import XCTest
@testable import Foundry
import FoundryServices

final class AISettingsStateTests: XCTestCase {
    @MainActor
    func testModelRefreshFailureReportsStatusInsteadOfSilentEmpty() async throws {
        let state = makeState(fetcher: { _ in .failed("Provider request failed: offline") })
        state.selectedAIProfileID = AIProviderProfile.ollamaID

        state.refreshAIModels()
        await waitUntil { state.aiModelsLoading == false }

        XCTAssertTrue(state.aiAvailableModels.isEmpty)
        XCTAssertEqual(state.aiProfileStatus, "Could not load models. Provider request failed: offline")
    }

    @MainActor
    func testModelRefreshEmptyResultReportsNoModels() async throws {
        let state = makeState(fetcher: { _ in .loaded([]) })
        state.selectedAIProfileID = AIProviderProfile.ollamaID

        state.refreshAIModels()
        await waitUntil { state.aiModelsLoading == false }

        XCTAssertTrue(state.aiAvailableModels.isEmpty)
        XCTAssertEqual(state.aiProfileStatus, "This endpoint reported no models.")
    }

    @MainActor
    func testModelRefreshSuccessListsModels() async throws {
        let models = [AIModel(id: "b-model", displayName: "b-model"), AIModel(id: "a-model", displayName: "a-model")]
        let state = makeState(fetcher: { _ in .loaded(models) })
        state.selectedAIProfileID = AIProviderProfile.ollamaID

        state.refreshAIModels()
        await waitUntil { state.aiModelsLoading == false }

        XCTAssertEqual(state.aiAvailableModels, models)
        XCTAssertEqual(state.aiProfileStatus, "Found 2 models.")
    }

    @MainActor
    func testModelsForAProfileNoLongerSelectedAreDropped() async throws {
        let release = AsyncStream<Void>.makeStream()
        let state = makeState(fetcher: { profile in
            if profile.id == AIProviderProfile.ollamaID { for await _ in release.stream { break } }
            return .loaded([AIModel(id: "stale", displayName: "stale")])
        })
        state.selectedAIProfileID = AIProviderProfile.ollamaID
        state.refreshAIModels()

        state.selectedAIProfileID = AIProviderProfile.appleID
        state.refreshAIModels()
        release.continuation.yield()
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertFalse(state.aiAvailableModels.contains { $0.id == "stale" })
        XCTAssertFalse(state.aiModelsLoading)
    }

    @MainActor
    private func makeState(
        fetcher: @escaping @Sendable (AIProviderProfile) async -> AIModelListResult
    ) -> AISettingsState {
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = ConfigService(diagnostics: DiagnosticsService(), url: configURL)
        return AISettingsState(
            config: config,
            diagnostics: DiagnosticsService(),
            modelListFetcher: fetcher
        )
    }
}
