import Foundation
import XCTest
@testable import Foundry

@MainActor
final class FileConversionTests: XCTestCase {
    func testCapabilityAssessmentIsDynamicAndKeepsTargetsVisible() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-Conversion-\(UUID().uuidString)")
        let state = FileConversionState(
            assess: { target in
                target.family == .mediaFFmpeg ? .setupRequired(FileConversionService.setupPlan(for: target)) : .ready
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
            assess: { .setupRequired(FileConversionService.setupPlan(for: $0)) },
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
            assess: { .setupRequired(FileConversionService.setupPlan(for: $0)) },
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
