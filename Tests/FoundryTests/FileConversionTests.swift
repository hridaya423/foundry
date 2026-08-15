import Foundation
import XCTest
@testable import Foundry
import FoundryServices

@MainActor
final class FileConversionTests: XCTestCase {
    func testCapabilityAssessmentIsDynamicAndKeepsTargetsVisible() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-Conversion-\(UUID().uuidString)")
        let state = FileConversionState(
            assess: { target in
                target.family == .mediaFFmpeg ? .setupRequired(testSetupPlan) : .ready
            }
        )
        state.setSource(url: folder.appendingPathComponent("movie.mov"))

        XCTAssertTrue(state.availableTargets.contains { $0.family == .mediaFFmpeg })
        await state.refreshCapabilities()
        XCTAssertTrue(state.availableTargets.allSatisfy { state.capability(for: $0) != nil })
        XCTAssertTrue(state.capability(for: state.availableTargets.first { $0.family == .mediaFFmpeg }!)!.isSetupRequired)
    }

    func testRefusingSetupDoesNotProvisionOrConvert() async {
        let recorder = FileConversionRecorder()
        let state = FileConversionState(
            assess: { _ in .setupRequired(testSetupPlan) },
            provision: { _, _ in await recorder.recordProvision() },
            convert: { _, _, _ in
                await recorder.recordConversion()
                return .failure(FileConversionError.unavailable("unexpected"))
            }
        )
        state.setSource(url: URL(fileURLWithPath: "/tmp/movie.mov"))
        await state.refreshCapabilities()
        state.convert()
        state.cancelDependencySetup()

        let provisions = await recorder.provisions()
        let conversions = await recorder.conversions()
        XCTAssertEqual(provisions, 0)
        XCTAssertEqual(conversions, 0)
    }

    func testProvisioningRequiresTheExactDisplayedPlanFingerprint() async throws {
        let recorder = FileConversionRecorder()
        let state = FileConversionState(
            assess: { _ in .setupRequired(testSetupPlan) },
            provision: { _, fingerprint in await recorder.recordProvision(fingerprint: fingerprint) }
        )
        state.setSource(url: URL(fileURLWithPath: "/tmp/movie.mov"))
        await state.refreshCapabilities()
        state.convert()
        let fingerprint = try XCTUnwrap(state.dependencySetup?.plan.fingerprint)
        await state.installToolAndConvert()

        let approved = await recorder.approvedFingerprint()
        XCTAssertEqual(approved, fingerprint)
    }

    func testMultipleSourcesUseOnlyCommonConversionTargets() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-Conversion-\(UUID().uuidString)")
        let first = folder.appendingPathComponent("first.png")
        let second = folder.appendingPathComponent("second.png")
        let state = FileConversionState()

        state.setSources(urls: [first, second, first])

        XCTAssertEqual(state.sourceURLs, [first, second])
        XCTAssertTrue(state.availableTargets.contains { $0.id == "jpg" })
        XCTAssertEqual(state.selectedTargetID, "jpg")
    }

    func testMixedSourcesWithoutACommonTargetAreNotConvertibleAsABatch() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-Conversion-\(UUID().uuidString)")
        let image = folder.appendingPathComponent("image.png")
        let text = folder.appendingPathComponent("notes.txt")
        let state = FileConversionState()

        state.setSources(urls: [image, text])

        XCTAssertTrue(state.availableTargets.isEmpty)
        XCTAssertNil(state.selectedTargetID)
        XCTAssertEqual(state.status, "No common conversion format for these files")
    }

    func testMissingConverterUsesConcreteHomebrewSetupPlan() async {
        let target = FileConversionTarget(id: "mp4", title: "MP4", outputExtension: "mp4", category: .video, family: .mediaFFmpeg)
        let capability = await FileConversionService.assess(target, locator: ExecutableLocator(fileInfo: { path in path == "/opt/homebrew/bin/brew" }), environment: [:])

        guard case let .setupRequired(plan) = capability else {
            return XCTFail("expected setup to be required")
        }
        XCTAssertEqual(plan.commands, [ExactCommand(executable: "/opt/homebrew/bin/brew", arguments: ["install", "ffmpeg"])])
    }

    func testMissingHomebrewMakesConverterUnavailable() async {
        let target = FileConversionTarget(id: "mp4", title: "MP4", outputExtension: "mp4", category: .video, family: .mediaFFmpeg)
        let capability = await FileConversionService.assess(target, locator: ExecutableLocator(fileInfo: { _ in false }), environment: [:])

        guard case let .unavailable(reason) = capability else {
            return XCTFail("expected converter to be unavailable")
        }
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("homebrew"))
    }

    func testRetryFailedDoesNotOfferSetupWhenReadinessIsUnavailable() async throws {
        let assessment = AssessmentState(.ready)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-Conversion-\(UUID().uuidString)")
        let source = folder.appendingPathComponent("movie.mov")
        let state = FileConversionState(
            assess: { _ in await assessment.value() },
            convert: { _, _, _ in .failure(FileConversionError.unavailable("conversion failed")) }
        )
        state.setSource(url: source)
        await state.refreshCapabilities()
        state.convert()
        try await waitForConversionToFinish(state)

        await assessment.set(.unavailable("readiness assessment failed"))
        state.retryFailed()
        for _ in 0..<100 where state.status.contains("readiness assessment failed") == false {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNil(state.dependencySetup)
        XCTAssertTrue(state.status.contains("readiness assessment failed"))
        XCTAssertFalse(state.status.contains("/opt/homebrew/bin/brew"))
    }

    func testConversionSuccessReachesCommittingAndCompletedOperationPhases() async throws {
        let coordinator = OperationCoordinator()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-Conversion-\(UUID().uuidString)")
        let source = folder.appendingPathComponent("movie.mov")
        let state = FileConversionState(
            assess: { _ in .ready },
            convert: { _, _, _ in .success(folder.appendingPathComponent("movie.mp4")) },
            operations: coordinator
        )
        state.setSource(url: source)
        await state.refreshCapabilities()
        state.convert()
        try await waitForConversionToFinish(state)

        XCTAssertEqual(state.phase, OperationPhase.completed)
        XCTAssertEqual(state.currentOperationSnapshot?.phase, OperationPhase.completed)
    }

    func testRetryRetainsCompletedOutputsAndAggregatesStatus() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-Conversion-\(UUID().uuidString)")
        let first = folder.appendingPathComponent("first.png")
        let second = folder.appendingPathComponent("second.png")
        let firstOutput = folder.appendingPathComponent("first.jpg")
        let secondOutput = folder.appendingPathComponent("second.jpg")
        let attempts = ConversionAttempts()
        let state = FileConversionState(
            assess: { _ in .ready },
            convert: { source, _, _ in
                await attempts.record(source)
                if source == first { return .success(firstOutput) }
                if await attempts.count(for: second) == 1 { return .failure(FileConversionError.unavailable("second failed")) }
                return .success(secondOutput)
            }
        )
        state.setSources(urls: [first, second])
        await state.refreshCapabilities()
        state.convert()
        try await waitForConversionToFinish(state)
        state.retryFailed()
        while state.isConverting == false { await Task.yield() }
        try await waitForConversionToFinish(state)

        XCTAssertEqual(state.outputURLs, [firstOutput, secondOutput])
        XCTAssertEqual(state.itemOutcomes.filter { $0.state == .completed }.count, 2)
        XCTAssertEqual(state.status, "Created 2 files")
    }

    func testCancellationDoesNotGetOverwrittenByLateConversionCompletion() async throws {
        let gate = ConversionGate()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-Conversion-\(UUID().uuidString)")
        let source = folder.appendingPathComponent("movie.mov")
        let output = folder.appendingPathComponent("movie.mp4")
        let state = FileConversionState(
            assess: { _ in .ready },
            convert: { _, _, _ in await gate.wait(); return .success(output) }
        )
        state.setSource(url: source)
        await state.refreshCapabilities()
        state.convert()
        while state.isConverting == false { await Task.yield() }
        state.cancel()
        await gate.release()
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(state.phase, .cancelled)
        XCTAssertTrue(state.outputURLs.isEmpty)
    }

    private func waitForConversionToFinish(_ state: FileConversionState) async throws {
        for _ in 0..<100 where state.isConverting {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(state.isConverting)
    }
}

private let testSetupPlan = SetupPlan(commands: [ExactCommand(executable: "/tmp/brew", arguments: ["install", "ffmpeg"])], artifacts: [], mutationScope: "test", cleanupOwnership: "test", disclosure: "test")

private actor AssessmentState {
    private var state: CapabilityState

    init(_ state: CapabilityState) { self.state = state }
    func set(_ state: CapabilityState) { self.state = state }
    func value() -> CapabilityState { state }
}

private actor FileConversionRecorder {
    private var provisionCount = 0
    private var conversionCount = 0
    private var recordedFingerprint: String?

    func recordProvision(fingerprint: String? = nil) {
        provisionCount += 1
        recordedFingerprint = fingerprint
    }

    func recordConversion() {
        conversionCount += 1
    }

    func provisions() -> Int { provisionCount }

    func conversions() -> Int { conversionCount }

    func approvedFingerprint() -> String? { recordedFingerprint }
}

private actor ConversionAttempts {
    private var values: [URL: Int] = [:]

    func record(_ source: URL) { values[source, default: 0] += 1 }
    func count(for source: URL) -> Int { values[source, default: 0] }
}

private actor ConversionGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
