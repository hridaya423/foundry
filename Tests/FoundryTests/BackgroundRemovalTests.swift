import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Foundry

@MainActor
final class BackgroundRemovalTests: XCTestCase {
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
