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
        while state.aiModelsLoading { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertTrue(state.aiAvailableModels.isEmpty)
        XCTAssertEqual(state.aiProfileStatus, "Could not load models. Provider request failed: offline")
    }

    @MainActor
    func testModelRefreshEmptyResultReportsNoModels() async throws {
        let state = makeState(fetcher: { _ in .loaded([]) })
        state.selectedAIProfileID = AIProviderProfile.ollamaID

        state.refreshAIModels()
        while state.aiModelsLoading { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertTrue(state.aiAvailableModels.isEmpty)
        XCTAssertEqual(state.aiProfileStatus, "This endpoint reported no models.")
    }

    @MainActor
    func testModelRefreshSuccessListsModels() async throws {
        let models = [AIModel(id: "b-model", displayName: "b-model"), AIModel(id: "a-model", displayName: "a-model")]
        let state = makeState(fetcher: { _ in .loaded(models) })
        state.selectedAIProfileID = AIProviderProfile.ollamaID

        state.refreshAIModels()
        while state.aiModelsLoading { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertEqual(state.aiAvailableModels, models)
        XCTAssertEqual(state.aiProfileStatus, "Found 2 models.")
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
