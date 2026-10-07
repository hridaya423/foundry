import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Foundry
import FoundryServices

@MainActor
final class FileConversionTests: XCTestCase {
    func testCapabilityAssessmentIsDynamicAndKeepsTargetsVisible() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-Conversion-\(UUID().uuidString)")
        let state = FileConversionState(
            assess: { target, _ in
                target.route.engines.contains(.ffmpeg) ? .setupRequired(testSetupPlan) : .ready
            }
        )
        state.setSource(url: folder.appendingPathComponent("movie.mov"))

        XCTAssertTrue(state.availableTargets.contains { $0.route.engines.contains(.ffmpeg) })
        await state.refreshCapabilities()
        XCTAssertTrue(state.availableTargets.allSatisfy { state.capability(for: $0) != nil })
        XCTAssertTrue(state.capability(for: state.availableTargets.first { $0.route.engines.contains(.ffmpeg) }!)!.isSetupRequired)
    }

    func testRefusingSetupDoesNotProvisionOrConvert() async {
        let recorder = FileConversionRecorder()
        let state = FileConversionState(
            assess: { _, _ in .setupRequired(testSetupPlan) },
            provision: { _, _ in await recorder.recordProvision() },
            convert: { _, _, _, _ in
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
            assess: { _, _ in .setupRequired(testSetupPlan) },
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

    func testResetDuringProvisioningDoesNotStartConversionWithClearedSources() async {
        let gate = ConversionGate()
        let recorder = FileConversionRecorder()
        let state = FileConversionState(
            assess: { _, _ in .setupRequired(testSetupPlan) },
            provision: { _, _ in
                await recorder.recordProvision()
                await gate.wait()
            },
            convert: { _, _, _, _ in
                await recorder.recordConversion()
                return .success(URL(fileURLWithPath: "/tmp/unexpected-output"))
            }
        )
        state.setSource(url: URL(fileURLWithPath: "/tmp/movie.mov"))
        await state.refreshCapabilities()
        state.convert()
        let provisioning = Task { await state.installToolAndConvert() }

        while state.phase != .provisioning { await Task.yield() }
        state.reset()
        await gate.release()
        await provisioning.value

        XCTAssertTrue(state.sourceURLs.isEmpty)
        let conversions = await recorder.conversions()
        XCTAssertEqual(conversions, 0)
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

    func testMixedSourcesOfferOnlySharedOutputs() {
        // png→txt→doc chains via Vision OCR mean png+txt share document
        // outputs too; only image-only and audio/video outputs are excluded.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-Conversion-\(UUID().uuidString)")
        let image = folder.appendingPathComponent("image.png")
        let text = folder.appendingPathComponent("notes.txt")
        let state = FileConversionState()

        state.setSources(urls: [image, text])

        let exts = Set(state.availableTargets.map(\.outputExtension))
        XCTAssertTrue(exts.contains("pdf"))
        XCTAssertTrue(exts.contains("zip"))
        // Shared document outputs exist (png→txt OCR → docx chains); image
        // outputs are legitimately shared via pdf→image rasterization, but
        // audio/video targets must never appear for a text+image batch.
        XCTAssertFalse(exts.contains("mp3"))
        XCTAssertFalse(exts.contains("mp4"))
        XCTAssertEqual(state.status, "")
    }

    func testMissingConverterUsesConcreteHomebrewSetupPlan() async {
        let target = FileConversionTarget(id: "mp4", title: "MP4", outputExtension: "mp4", category: .video, engine: .ffmpeg)
        let capability = await FileConversionService.assess(target, locator: ExecutableLocator(fileInfo: { path in path == "/opt/homebrew/bin/brew" }), environment: [:])

        guard case let .setupRequired(plan) = capability else {
            return XCTFail("expected setup to be required")
        }
        XCTAssertEqual(plan.commands, [ExactCommand(executable: "/opt/homebrew/bin/brew", arguments: ["install", "ffmpeg"])])
    }

    func testMissingHomebrewMakesConverterUnavailable() async {
        let target = FileConversionTarget(id: "mp4", title: "MP4", outputExtension: "mp4", category: .video, engine: .ffmpeg)
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
            assess: { _, _ in await assessment.value() },
            convert: { _, _, _, _ in .failure(FileConversionError.unavailable("conversion failed")) }
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
            assess: { _, _ in .ready },
            convert: { _, _, _, _ in .success(folder.appendingPathComponent("movie.mp4")) },
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
            assess: { _, _ in .ready },
            convert: { source, _, _, _ in
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
            assess: { _, _ in .ready },
            convert: { _, _, _, _ in await gate.wait(); return .success(output) }
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

    func testAddSourcesMergesAndDedupes() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-Conversion-\(UUID().uuidString)")
        let first = folder.appendingPathComponent("a.png")
        let second = folder.appendingPathComponent("b.png")
        let state = FileConversionState()

        state.setSource(url: first)
        state.addSources(urls: [second, first])

        XCTAssertEqual(state.sourceURLs, [first, second])
    }

    func testRemoveSourceRecomputesSharedTargets() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-Conversion-\(UUID().uuidString)")
        let image = folder.appendingPathComponent("a.png")
        let text = folder.appendingPathComponent("b.txt")
        let state = FileConversionState()
        state.setSources(urls: [image, text])
        let sharedExts = Set(state.availableTargets.map(\.outputExtension))
        XCTAssertFalse(sharedExts.contains("mp3"))

        state.removeSource(url: text)

        XCTAssertEqual(state.sourceURLs, [image])
        let imageExts = Set(state.availableTargets.map(\.outputExtension))
        XCTAssertTrue(imageExts.contains("jpg"))
        XCTAssertTrue(imageExts.contains("heic"))
    }

    func testRemoveLastSourceClearsBatch() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-Conversion-\(UUID().uuidString)")
        let image = folder.appendingPathComponent("a.png")
        let state = FileConversionState()
        state.setSource(url: image)

        state.removeSource(url: image)

        XCTAssertTrue(state.sourceURLs.isEmpty)
        XCTAssertTrue(state.availableTargets.isEmpty)
        XCTAssertTrue(state.outputURLs.isEmpty)
    }

    private func waitForConversionToFinish(_ state: FileConversionState) async throws {
        for _ in 0..<100 where state.isConverting {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(state.isConverting)
    }
}

// MARK: - Router and engine coverage (service boundary)

final class ConversionGraphTests: XCTestCase {
    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }

    func testNativeSingleHopPreferredForImages() {
        let route = ConversionGraph.route(from: "jpg", to: "png")
        XCTAssertEqual(route?.hopCount, 1)
        XCTAssertEqual(route?.producingEngine, .imageIO)
        XCTAssertEqual(route?.engineSummary, "Built in")
    }

    func testVideoToMP4PrefersAVFoundation() {
        let route = ConversionGraph.route(from: "mov", to: "mp4")
        XCTAssertEqual(route?.hopCount, 1)
        XCTAssertEqual(route?.producingEngine, .avFoundation)
    }

    func testAudioExtractionFromVideoIsNative() {
        let route = ConversionGraph.route(from: "mp4", to: "m4a")
        XCTAssertEqual(route?.hopCount, 1)
        XCTAssertEqual(route?.producingEngine, .avFoundation)
    }

    func testPDFToImageIsNativeWithPDFKit() {
        let route = ConversionGraph.route(from: "pdf", to: "png")
        XCTAssertEqual(route?.hopCount, 1)
        XCTAssertEqual(route?.producingEngine, .pdfKit)
    }

    func testMarkdownToPDFRoutesThroughTwoExternalEngines() {
        let route = ConversionGraph.route(from: "md", to: "pdf")
        XCTAssertNotNil(route)
        XCTAssertEqual(route?.hopCount, 2)
        XCTAssertEqual(route?.engines.first, .pandoc)
        XCTAssertEqual(route?.engines.last, .soffice)
        XCTAssertTrue(route?.engineSummary.contains("Pandoc") ?? false)
    }

    func testNoRouteExceedsThreeHops() {
        let reachable = ConversionGraph.routes(from: "epub")
        for (_, route) in reachable {
            XCTAssertLessThanOrEqual(route.hopCount, 3, "route to \(route.edges.last?.output ?? "?") exceeded cap")
        }
    }

    func testOCRAndArchiveTargetsExist() {
        let pngTargets = FileConversionService.availableTargets(for: url("a.png"))
        XCTAssertTrue(pngTargets.contains { $0.outputExtension == "txt" && $0.route.engines.contains(.vision) })
        XCTAssertTrue(pngTargets.contains { $0.outputExtension == "zip" })
        XCTAssertTrue(pngTargets.contains { $0.outputExtension == "pdf" })

        let zipTargets = FileConversionService.availableTargets(for: url("a.zip"))
        XCTAssertTrue(zipTargets.contains { $0.outputExtension == ConversionGraph.extractExt })
    }

    func testNewFormatCoverage() {
        // csv → json native
        XCTAssertEqual(ConversionGraph.route(from: "csv", to: "json")?.producingEngine, .structuredData)
        // plist ↔ json native
        XCTAssertEqual(ConversionGraph.route(from: "plist", to: "json")?.producingEngine, .plutil)
        // avif native write (verified on ImageIO)
        XCTAssertEqual(ConversionGraph.route(from: "png", to: "avif")?.producingEngine, .imageIO)
        // webp write stays on ImageMagick (sips fails on it)
        XCTAssertEqual(ConversionGraph.route(from: "png", to: "webp")?.producingEngine, .imageMagick)
        // svg read natively
        XCTAssertEqual(ConversionGraph.route(from: "svg", to: "png")?.producingEngine, .imageIO)
        // subtitles via ffmpeg
        XCTAssertEqual(ConversionGraph.route(from: "vtt", to: "srt")?.producingEngine, .ffmpeg)
        // xlsx → csv via soffice
        XCTAssertEqual(ConversionGraph.route(from: "xlsx", to: "csv")?.producingEngine, .soffice)
    }

    func testCompoundArchiveExtension() {
        XCTAssertEqual(ConversionGraph.normalizedExtension(of: url("backup.tar.gz")), "tar.gz")
        XCTAssertEqual(ConversionGraph.normalizedExtension(of: url("photo.PNG")), "png")
    }

    func testApplicableOptionsMatchOutputAndEngine() {
        // jpg output via ImageIO: quality + resize controls.
        let jpg = FileConversionService.availableTargets(for: url("a.png"))
            .first { $0.outputExtension == "jpg" }
        XCTAssertEqual(jpg?.applicableOptions, [.quality, .maxPixelSize])

        // pdf→png renders through PDFKit: DPI + page selection, no quality/resize.
        let pdfPNG = FileConversionService.availableTargets(for: url("a.pdf"))
            .first { $0.outputExtension == "png" }
        XCTAssertEqual(pdfPNG?.applicableOptions, [.dpiAndPages])

        // wav→mp3 routes through ffmpeg: bitrate control only.
        let mp3 = FileConversionService.availableTargets(for: url("a.wav"))
            .first { $0.outputExtension == "mp3" }
        XCTAssertEqual(mp3?.applicableOptions, [.audioBitrate])

        // csv→json has no tunables.
        let json = FileConversionService.availableTargets(for: url("a.csv"))
            .first { $0.outputExtension == "json" }
        XCTAssertEqual(json?.applicableOptions, [])
    }
}

final class ConversionExecutorTests: XCTestCase {
    private var folder: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("Foundry-ConvExec-\(UUID().uuidString)")

    override func setUp() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Renders a tiny PNG via ImageIO for use as a conversion source.
    private func makePNG(_ name: String = "pixel.png") throws -> URL {
        let url = folder.appendingPathComponent(name)
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.3, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return url
    }

    func testImageIOConversionHonorsQualityAndResize() async throws {
        let source = try makePNG()
        let jpgTarget = FileConversionService.availableTargets(for: source).first { $0.outputExtension == "jpg" }!
        let result = await FileConversionService.convert(
            sourceURL: source, target: jpgTarget, outputFolderURL: folder,
            options: ConversionOptions(quality: 0.5, maxPixelSize: 2)
        )
        guard case let .success(out) = result else {
            return XCTFail("conversion failed: \(result)")
        }
        XCTAssertEqual(out.pathExtension, "jpg")
        // Resize option applied: longest edge should be 2px.
        if let src = CGImageSourceCreateWithURL(out as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 2)
        } else {
            XCTFail("output not a readable image")
        }
    }

    func testCSVToJSONRoundTrip() async throws {
        let csv = folder.appendingPathComponent("data.csv")
        try "name,age\n\"Ada, Lovelace\",36\nBob,28\n".write(to: csv, atomically: true, encoding: .utf8)
        let target = FileConversionService.availableTargets(for: csv).first { $0.outputExtension == "json" }!
        guard case let .success(jsonURL) = await FileConversionService.convert(sourceURL: csv, target: target, outputFolderURL: folder) else {
            return XCTFail("csv→json failed")
        }
        let objects = try JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL)) as? [[String: String]]
        XCTAssertEqual(objects?.count, 2)
        XCTAssertEqual(objects?.first?["name"], "Ada, Lovelace")
        XCTAssertEqual(objects?.first?["age"], "36")

        // And back to CSV.
        let backTarget = FileConversionService.availableTargets(for: jsonURL).first { $0.outputExtension == "csv" }!
        guard case let .success(csvURL) = await FileConversionService.convert(sourceURL: jsonURL, target: backTarget, outputFolderURL: folder) else {
            return XCTFail("json→csv failed")
        }
        let text = try String(contentsOf: csvURL, encoding: .utf8)
        XCTAssertTrue(text.contains("\"Ada, Lovelace\""), "comma-containing field should be quoted")
    }

    func testZipAndExtractRoundTrip() async throws {
        let source = folder.appendingPathComponent("note.txt")
        try "hello".write(to: source, atomically: true, encoding: .utf8)
        let zipTarget = FileConversionService.availableTargets(for: source).first { $0.outputExtension == "zip" }!
        guard case let .success(zipURL) = await FileConversionService.convert(sourceURL: source, target: zipTarget, outputFolderURL: folder) else {
            return XCTFail("zip failed")
        }
        let extractTarget = FileConversionService.availableTargets(for: zipURL).first { $0.outputExtension == ConversionGraph.extractExt }!
        guard case let .success(extractedDir) = await FileConversionService.convert(sourceURL: zipURL, target: extractTarget, outputFolderURL: folder) else {
            return XCTFail("extract failed")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedDir.appendingPathComponent("note.txt").path))
        XCTAssertEqual(try String(contentsOf: extractedDir.appendingPathComponent("note.txt"), encoding: .utf8), "hello")
    }

    func testPlistJSONRoundTrip() async throws {
        let json = folder.appendingPathComponent("config.json")
        try "{\"key\": \"value\", \"n\": 3}".write(to: json, atomically: true, encoding: .utf8)
        let plistTarget = FileConversionService.availableTargets(for: json).first { $0.outputExtension == "plist" }!
        guard case let .success(plistURL) = await FileConversionService.convert(sourceURL: json, target: plistTarget, outputFolderURL: folder) else {
            return XCTFail("json→plist failed")
        }
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as? [String: Any]
        XCTAssertEqual(plist?["key"] as? String, "value")
        XCTAssertEqual(plist?["n"] as? Int, 3)
    }

    func testTxtToMarkdownRoutesViaTextutilThenPandoc() {
        // txt→md has no direct edge: textutil can't write md, pandoc doesn't
        // read txt. The router must hop txt→html(textutil)→md(pandoc).
        let route = ConversionGraph.route(from: "txt", to: "md")
        XCTAssertEqual(route?.hopCount, 2)
        XCTAssertEqual(route?.engines, [.textutil, .pandoc])
    }

    func testUnknownInputHasOnlyArchiveTargets() {
        let targets = FileConversionService.availableTargets(for: URL(fileURLWithPath: "/tmp/mystery.xyzzy"))
        XCTAssertEqual(Set(targets.map(\.outputExtension)), ["zip", "tar.gz"])
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
