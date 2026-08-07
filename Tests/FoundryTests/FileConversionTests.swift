import Foundation
import XCTest
@testable import Foundry

@MainActor
final class FileConversionTests: XCTestCase {
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
