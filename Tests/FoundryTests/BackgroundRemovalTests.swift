import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Foundry

@MainActor
final class BackgroundRemovalTests: XCTestCase {
    func testBEN2AssessmentIsReadOnlyAndDisclosesSetup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-BEN2-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let assessment = BEN2BackgroundRemovalService.assess(root: root, executablePaths: [:])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertEqual(assessment.modelState, .missing)
        XCTAssertEqual(assessment.runtimeState, .missing)
        XCTAssertNotNil(assessment.setupPlan)
        XCTAssertTrue(assessment.setupPlan?.disclosure.contains("223 MB") == true)
        XCTAssertTrue(assessment.setupPlan?.disclosure.contains("Python 3.13") == true)
        XCTAssertTrue(assessment.setupPlan?.disclosure.contains("onnxruntime==1.24.2") == true)
    }

    func testChoosingBEN2DoesNotProvisionIt() throws {
        let state = FileShelfState()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let assessment = BEN2BackgroundRemovalService.assess(root: root, executablePaths: [:])
        XCTAssertEqual(assessment.modelState, .missing)
        XCTAssertFalse(state.isSettingUpBEN2)
    }

    func testBEN2RejectsTamperedRuntimeManifest() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = root.appendingPathComponent("runtime")
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        try Data("python=3.13\nonnxruntime==1.24.2\nnumpy==2.5.1\nPillow==11.3.0\n".utf8)
            .write(to: runtime.appendingPathComponent("runtime-manifest.json"))
        FileManager.default.createFile(atPath: runtime.appendingPathComponent("bin/python").path, contents: Data())

        XCTAssertEqual(BEN2BackgroundRemovalService.assess(root: root, executablePaths: [:]).runtimeState, .invalid)
    }

    func testBundledWorkerRequiresIdentityAndValidatesStillImageLimits() throws {
        let worker = try XCTUnwrap(Bundle.module.url(forResource: "background_removal_worker", withExtension: "py"))
        let source = try String(contentsOf: worker)
        XCTAssertTrue(source.contains("--worker-sha256"))
        XCTAssertTrue(source.contains("MAX_PIXELS"))
        XCTAssertTrue(source.contains("n_frames"))
        XCTAssertTrue(source.contains("result.format != \"PNG\""))
    }

    func testBEN2ProvisioningDoesNotUseUnpinnedPipInstall() throws {
        let source = try String(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "background_removal_worker", withExtension: "py")))
        XCTAssertFalse(source.contains("uv pip install"))
        XCTAssertTrue(BEN2BackgroundRemovalService.assess().setupPlan?.disclosure.contains("SHA-256") == true)
    }
    func testShelfBatchAddReportsDuplicatesAndRejectedURLs() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let urls = ["one.png", "two.png", "three.png"].map { folder.appendingPathComponent($0) }
        let state = FileShelfState()

        let first = state.add(urls: urls)
        let second = state.add(urls: [urls[0], urls[0], URL(string: "https://example.com/file.png")!])

        XCTAssertEqual(first, FileShelfAddResult(addedCount: 3, duplicateCount: 0, rejectedCount: 0))
        XCTAssertEqual(second, FileShelfAddResult(addedCount: 0, duplicateCount: 2, rejectedCount: 1))
        XCTAssertEqual(state.files.count, 3)
        XCTAssertTrue(second.didReceiveFiles)
        XCTAssertTrue(state.compactSummary.contains("three.png"))
    }

    func testVisionServiceSupportsStillImagesButNotTextFiles() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let imageURL = folder.appendingPathComponent("source.png")
        let textURL = folder.appendingPathComponent("notes.txt")
        try writePNG(to: imageURL)
        try Data("not an image".utf8).write(to: textURL)

        let service = VisionBackgroundRemovalService()
        XCTAssertTrue(service.supports(imageURL))
        XCTAssertFalse(service.supports(textURL))
    }

    func testDestinationURLDoesNotOverwriteAnExistingResult() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sourceURL = folder.appendingPathComponent("portrait.jpg")
        let firstURL = VisionBackgroundRemovalService.destinationURL(for: sourceURL)
        FileManager.default.createFile(atPath: firstURL.path, contents: Data())

        let nextURL = VisionBackgroundRemovalService.destinationURL(for: sourceURL)

        XCTAssertEqual(nextURL.lastPathComponent, "portrait - background removed 2.png")
    }

    func testShelfAddsAndSelectsGeneratedOutput() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sourceURL = folder.appendingPathComponent("portrait.png")
        let outputURL = folder.appendingPathComponent("portrait - background removed.png")
        try writePNG(to: sourceURL)
        let state = FileShelfState(backgroundRemovalService: StubBackgroundRemovalService(result: .success(outputURL)))
        state.add(urls: [sourceURL])

        state.removeBackgroundFromSelected()
        try await waitForBackgroundRemovalToFinish(state)

        XCTAssertEqual(state.files.map(\.url), [sourceURL, outputURL])
        XCTAssertEqual(state.selectedID, outputURL.path)
        XCTAssertNil(state.backgroundRemovalError)
    }

    func testShelfPreservesSourceAfterProcessingFailure() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sourceURL = folder.appendingPathComponent("portrait.png")
        try writePNG(to: sourceURL)
        let state = FileShelfState(backgroundRemovalService: StubBackgroundRemovalService(result: .failure(.destinationNotWritable)))
        state.add(urls: [sourceURL])

        state.removeBackgroundFromSelected()
        try await waitForBackgroundRemovalToFinish(state)

        XCTAssertEqual(state.files.map(\.url), [sourceURL])
        XCTAssertEqual(state.backgroundRemovalError, BackgroundRemovalError.destinationNotWritable.localizedDescription)
        XCTAssertTrue(state.backgroundRemovalNeedsDestination)
    }

    func testShelfCanSelectBEN2AsAnAlternateEngine() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sourceURL = folder.appendingPathComponent("portrait.png")
        let outputURL = folder.appendingPathComponent("portrait - ben2.png")
        try writePNG(to: sourceURL)
        let state = FileShelfState(
            backgroundRemovalService: StubBackgroundRemovalService(result: .failure(.noForegroundFound)),
            ben2Service: StubBackgroundRemovalService(result: .success(outputURL))
        )
        state.add(urls: [sourceURL])

        state.removeBackgroundWithBEN2()
        try await waitForBackgroundRemovalToFinish(state)

        XCTAssertEqual(state.files.map(\.url), [sourceURL, outputURL])
        XCTAssertEqual(state.selectedID, outputURL.path)
        XCTAssertNil(state.backgroundRemovalEngine)
    }

    func testShelfSupportsToggleAndRangeSelection() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let urls = ["one.png", "two.png", "three.png"].map { folder.appendingPathComponent($0) }
        let state = FileShelfState()
        state.add(urls: urls)

        state.toggleSelection(id: urls[1].path)
        XCTAssertEqual(state.selectedFiles.map(\.url), [urls[0], urls[1]])

        state.select(id: urls[0].path)
        state.extendSelection(to: urls[2].path)
        XCTAssertEqual(state.selectedFiles.map(\.url), urls)

        state.toggleSelection(id: urls[1].path)
        XCTAssertEqual(state.selectedFiles.map(\.url), [urls[0], urls[2]])

        state.select(id: urls[0].path)
        state.toggleSelection(id: urls[0].path)
        XCTAssertTrue(state.selectedFiles.isEmpty)
    }

    func testShelfRemovesBackgroundFromMultipleSelectedFiles() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sourceURLs = ["one.png", "two.png"].map { folder.appendingPathComponent($0) }
        let outputURLs = ["one - background removed.png", "two - background removed.png"].map { folder.appendingPathComponent($0) }
        let service = MappingBackgroundRemovalService(outputs: Dictionary(uniqueKeysWithValues: zip(sourceURLs, outputURLs)))
        let state = FileShelfState(backgroundRemovalService: service)
        state.add(urls: sourceURLs)
        state.toggleSelection(id: sourceURLs[1].path)

        state.removeBackgroundFromSelected()
        try await waitForBackgroundRemovalToFinish(state)

        XCTAssertEqual(state.files.map(\.url), sourceURLs + outputURLs)
        XCTAssertEqual(state.selectedFiles.map(\.url), outputURLs)
        XCTAssertEqual(state.backgroundRemovalStatus, "Processed 2 files")
        XCTAssertNil(state.backgroundRemovalError)
    }

    func testShelfExposesBEN2AsTheOnlyExperimentalEngine() {
        let state = FileShelfState()

        XCTAssertEqual(state.experimentalEngines, [.ben2])
    }

    func testCancellingShelfProcessingDoesNotAddOutput() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sourceURL = folder.appendingPathComponent("portrait.png")
        let outputURL = folder.appendingPathComponent("portrait - background removed.png")
        try writePNG(to: sourceURL)
        let state = FileShelfState(backgroundRemovalService: SlowBackgroundRemovalService(outputURL: outputURL))
        state.add(urls: [sourceURL])

        state.removeBackgroundFromSelected()
        state.cancelBackgroundRemoval()
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(state.files.map(\.url), [sourceURL])
        XCTAssertNil(state.backgroundRemovalFileID)
        XCTAssertFalse(state.isRemovingBackground)
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-BackgroundRemoval-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func writePNG(to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels: [UInt8] = [
            255, 0, 0, 255,
            0, 255, 0, 255,
            0, 0, 255, 255,
            255, 255, 255, 255
        ]
        guard let image = pixels.withUnsafeMutableBytes({ buffer in
            CGContext(
                data: buffer.baseAddress,
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 8,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        }) else {
            throw NSError(domain: "BackgroundRemovalTests", code: 1)
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "BackgroundRemovalTests", code: 2)
        }
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func waitForBackgroundRemovalToFinish(_ state: FileShelfState) async throws {
        for _ in 0..<100 {
            if state.isRemovingBackground == false { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Background removal did not finish")
    }
}

private struct StubBackgroundRemovalService: BackgroundRemoving {
    let result: Result<URL, BackgroundRemovalError>

    func supports(_ sourceURL: URL) -> Bool {
        sourceURL.pathExtension.lowercased() == "png"
    }

    func removeBackground(from sourceURL: URL, destinationURL: URL?) async throws -> URL {
        try result.get()
    }
}

private struct SlowBackgroundRemovalService: BackgroundRemoving {
    let outputURL: URL

    func supports(_ sourceURL: URL) -> Bool {
        true
    }

    func removeBackground(from sourceURL: URL, destinationURL: URL?) async throws -> URL {
        try await Task.sleep(for: .seconds(1))
        return outputURL
    }
}

private struct MappingBackgroundRemovalService: BackgroundRemoving {
    let outputs: [URL: URL]

    func supports(_ sourceURL: URL) -> Bool {
        outputs[sourceURL] != nil
    }

    func removeBackground(from sourceURL: URL, destinationURL: URL?) async throws -> URL {
        guard let outputURL = outputs[sourceURL] else {
            throw BackgroundRemovalError.unsupportedFile
        }
        return outputURL
    }
}
