import os
import XCTest
@testable import Foundry
import FoundryDomain
import FoundryServices
import AppKit

@MainActor
final class ActionRunnerTests: XCTestCase {
    func testKeepAwakeOwnerStopsOnlyTheProcessItLaunched() throws {
        let process = TestKeepAwakeProcess()
        let owner = KeepAwakeProcessOwner()

        XCTAssertTrue(try owner.toggle { process })
        XCTAssertFalse(try owner.toggle { XCTFail("Should reuse the owned process"); return TestKeepAwakeProcess() })
        XCTAssertEqual(process.stopCount, 1)
    }

    func testKeepAwakeOwnerPropagatesLaunchFailure() {
        let owner = KeepAwakeProcessOwner()

        XCTAssertThrowsError(try owner.toggle { throw NSError(domain: "test", code: 1) })
        XCTAssertFalse(owner.isActive)
    }

    func testKeepAwakeOwnerStopsItsProcessDuringShutdown() throws {
        let process = TestKeepAwakeProcess()
        let owner = KeepAwakeProcessOwner()
        _ = try owner.toggle { process }

        owner.stop()

        XCTAssertFalse(owner.isActive)
        XCTAssertEqual(process.stopCount, 1)
    }

    func testKeepAwakeProcessEndsWithItsOwningApplication() {
        XCTAssertEqual(
            NativeKeepAwakeProcess.arguments(parentProcessID: 42),
            ["-dimsu", "-w", "42"]
        )
    }

    func testExecutionReturnsTypedClipboardOutcomeAndFeedbackEvent() async {
        let runner = ActionRunner(diagnostics: DiagnosticsService(), pasteboard: NSPasteboard(name: NSPasteboard.Name("ActionRunnerTests")))
        let request = CommandExecutionRequest(
            commandID: "test.copy",
            action: CommandAction(id: "test.copy.perform", title: "Copy", behavior: CopyToClipboardAction("value"))
        )
        var events: [CommandExecutionEvent] = []

        let outcome = await runner.execute(request) { event in
            events.append(event)
        }

        XCTAssertEqual(outcome, .copied(content: "value"))
        XCTAssertTrue(events.contains { event in
            if case .feedback(.success("Copied value")) = event { return true }
            return false
        })
        XCTAssertEqual(CopyToClipboardAction.copiedMessage(for: String(repeating: "x", count: 40)), "Copied to clipboard")
        XCTAssertEqual(CopyToClipboardAction.copiedMessage(for: "a\nb"), "Copied to clipboard")
    }

    func testCopySnippetRendersAtExecutionUsingInjectedContext() async {
        let store = TestSnippetStore(snippets: [StoredSnippet(id: "one", title: "One", content: "{clipboard}")])
        let runner = ActionRunner(
            diagnostics: DiagnosticsService(),
            snippetStore: store,
            pasteboard: NSPasteboard(name: NSPasteboard.Name("ActionRunnerTests.snippet")),
            snippetContext: { SnippetRenderContext(now: Date(timeIntervalSince1970: 0), locale: Locale(identifier: "en_US_POSIX"), calendar: Calendar(identifier: .gregorian), clipboard: "later") }
        )
        let action = CommandAction(id: "copy", title: "Copy", behavior: CopySnippetAction(id: "one"))

        let outcome = await runner.execute(CommandExecutionRequest(commandID: "copy", action: action)) { _ in }

        XCTAssertEqual(outcome, .copied(content: "later"))
    }

    func testExecutionReturnsProcessFailureWithoutThrowingAcrossTheBoundary() async {
        let runner = ActionRunner(diagnostics: DiagnosticsService())
        let request = CommandExecutionRequest(
            commandID: "test.process",
            action: CommandAction(id: "test.process.perform", title: "Run", behavior: RunProcessAction(path: "/path/that/does/not/exist", arguments: []))
        )

        let outcome = await runner.execute(request) { _ in }

        guard case let .failure(message, retryable) = outcome else {
            return XCTFail("Expected a typed process failure")
        }
        XCTAssertEqual(message, "Failed to run process")
        XCTAssertTrue(retryable)
    }

    func testOpenActionReturnsTypedRouteWithPayload() async {
        let runner = ActionRunner(diagnostics: DiagnosticsService())
        let request = CommandExecutionRequest(
            commandID: "test.translate",
            action: CommandAction(
                id: "test.translate.open",
                title: "Open Translator",
                behavior: OpenTranslatorAction(text: "hello", language: "Spanish")
            )
        )

        let outcome = await runner.execute(request) { _ in }

        XCTAssertEqual(outcome, .open(route: .translator(text: "hello", language: "Spanish")))
        XCTAssertFalse(outcome.shouldDismissPanel)
    }

    func testResetRankingRunsThroughTheExecutorBoundary() async {
        var resetCommandID: String?
        let runner = ActionRunner(
            diagnostics: DiagnosticsService(),
            resetRanking: { resetCommandID = $0 }
        )
        let request = CommandExecutionRequest(
            commandID: "test.command",
            action: CommandAction(
                id: "test.command.reset",
                title: "Reset Ranking",
                behavior: ResetRankingAction(commandID: "test.command")
            )
        )

        let outcome = await runner.execute(request) { _ in }

        XCTAssertEqual(resetCommandID, "test.command")
        XCTAssertEqual(outcome, .stayOpen(message: "Ranking reset"))
    }

    func testDestructiveActionRequiresConfirmation() async {
        let runner = ActionRunner(
            diagnostics: DiagnosticsService(),
            confirmAction: { _, _ in false }
        )
        let request = CommandExecutionRequest(
            commandID: "test.quit",
            action: CommandAction(id: "test.quit.perform", title: "Quit", behavior: QuitAction())
        )

        let outcome = await runner.execute(request) { _ in }

        XCTAssertEqual(outcome, .denied(message: "Action cancelled"))
    }

    func testWindowPermissionKeepsThePanelStateAvailable() async {
        let runner = ActionRunner(
            diagnostics: DiagnosticsService(),
            windowManager: PermissionWindowManager()
        )
        let request = CommandExecutionRequest(
            commandID: "test.window",
            action: CommandAction(id: "test.window.perform", title: "Tile", behavior: TileWindowAction(.leftHalf))
        )

        let outcome = await runner.execute(request) { _ in }

        XCTAssertEqual(outcome, .stayOpen(message: "Accessibility permission required for window control"))
    }

    func testWindowPermissionDoesNotOpenSettingsAcrossRepeatedAttemptsButExplicitURLDoes() async {
        var openedURLs: [URL] = []
        let runner = ActionRunner(
            diagnostics: DiagnosticsService(),
            windowManager: PermissionWindowManager(),
            openURL: { url in
                openedURLs.append(url)
                return true
            }
        )
        let tileRequest = CommandExecutionRequest(
            commandID: "test.window.repeated",
            action: CommandAction(id: "test.window.repeated.perform", title: "Tile", behavior: TileWindowAction(.leftHalf))
        )

        for _ in 0..<3 {
            let outcome = await runner.execute(tileRequest) { _ in }
            XCTAssertEqual(outcome, .stayOpen(message: "Accessibility permission required for window control"))
        }
        XCTAssertTrue(openedURLs.isEmpty)

        let openSettingsRequest = CommandExecutionRequest(
            commandID: "test.accessibility.settings",
            action: CommandAction(
                id: "test.accessibility.settings.open",
                title: "Open Accessibility Settings",
                behavior: OpenURLAction(NativeWindowManager.accessibilitySettingsURL.absoluteString)
            )
        )

        let openSettingsOutcome = await runner.execute(openSettingsRequest) { _ in }
        XCTAssertEqual(openSettingsOutcome, .success(message: "Opened link"))
        XCTAssertEqual(openedURLs, [NativeWindowManager.accessibilitySettingsURL])
    }

    func testCancellationCancelsAProcessExecution() async throws {
        let runner = ActionRunner(diagnostics: DiagnosticsService())
        let cancellationID = UUID()
        let request = CommandExecutionRequest(
            commandID: "test.sleep",
            action: CommandAction(id: "test.sleep.perform", title: "Sleep", behavior: RunProcessAction(path: "/bin/sleep", arguments: ["10"])),
            cancellationID: cancellationID
        )

        let task = Task { await runner.execute(request) { _ in } }
        try await Task.sleep(for: .milliseconds(50))
        runner.cancel(cancellationID)
        let outcome = await task.value

        XCTAssertEqual(outcome, .cancelled)
    }

    func testCallerCancellationCancelsTheOwnedExecution() async throws {
        let runner = ActionRunner(diagnostics: DiagnosticsService())
        let request = CommandExecutionRequest(
            commandID: "test.sleep.caller-cancel",
            action: CommandAction(
                id: "test.sleep.caller-cancel.perform",
                title: "Sleep",
                behavior: RunProcessAction(path: "/bin/sleep", arguments: ["10"])
            )
        )

        let task = Task { await runner.execute(request) { _ in } }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
    }

    func testDuplicateCancellationIDsDoNotReplaceTheOriginalExecution() async throws {
        let runner = ActionRunner(diagnostics: DiagnosticsService())
        let cancellationID = UUID()
        let request = CommandExecutionRequest(
            commandID: "test.sleep.duplicate",
            action: CommandAction(
                id: "test.sleep.duplicate.perform",
                title: "Sleep",
                behavior: RunProcessAction(path: "/bin/sleep", arguments: ["10"])
            ),
            cancellationID: cancellationID
        )

        let first = Task { await runner.execute(request) { _ in } }
        try await Task.sleep(for: .milliseconds(50))
        let duplicate = await runner.execute(request) { _ in }

        guard case let .failure(message, retryable) = duplicate else {
            return XCTFail("Expected duplicate execution to be rejected")
        }
        XCTAssertTrue(message.contains("already running"))
        XCTAssertTrue(retryable)
        runner.cancel(cancellationID)
        let outcome = await first.value
        XCTAssertEqual(outcome, .cancelled)
    }

    func testOpenAppCancellationCompletesBeforeDelayedWorkspaceCallback() async throws {
        var callback: ((NSRunningApplication?, Error?) -> Void)?
        let runner = ActionRunner(
            diagnostics: DiagnosticsService(),
            openApplication: { _, _, completion in callback = completion }
        )
        let request = CommandExecutionRequest(
            commandID: "test.open-app.cancel",
            action: CommandAction(id: "test.open-app.cancel.perform", title: "Open", behavior: OpenAppAction(path: "/Applications/Missing.app", name: "Missing"))
        )
        let task = Task { await runner.execute(request) { _ in } }
        while callback == nil { await Task.yield() }
        task.cancel()

        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
        callback?(nil, nil)
    }

    func testMediaExecutionsHaveIndependentCancellationOwnership() async throws {
        let media = FakeMediaDownloadService()
        let runner = ActionRunner(
            diagnostics: DiagnosticsService(),
            mediaDownloadService: media
        )
        let firstID = UUID()
        let secondID = UUID()
        let firstRequest = CommandExecutionRequest(
            commandID: "test.media.first",
            action: CommandAction(id: "test.media.first.perform", title: "Download", behavior: DownloadMediaAction(url: "https://example.com/first")),
            cancellationID: firstID
        )
        let secondRequest = CommandExecutionRequest(
            commandID: "test.media.second",
            action: CommandAction(id: "test.media.second.perform", title: "Download", behavior: DownloadMediaAction(url: "https://example.com/second")),
            cancellationID: secondID
        )

        let first = Task { await runner.execute(firstRequest) { _ in } }
        await waitUntil { await media.activeCount() == 1 }
        let second = Task { await runner.execute(secondRequest) { _ in } }
        await waitUntil { await media.activeCount() == 2 }
        runner.cancel(secondID)

        let secondOutcome = await second.value
        await media.release("https://example.com/first")
        let firstOutcome = await first.value
        let maxConcurrent = await media.maxConcurrentValue()

        XCTAssertEqual(secondOutcome, .cancelled)
        XCTAssertEqual(firstOutcome, .stayOpen(message: "Downloaded first"))
        XCTAssertEqual(maxConcurrent, 2)
    }

    private actor FakeMediaDownloadService: MediaDownloading {
        private var active = 0
        private var maxConcurrent = 0

        func download(
            urlString: String,
            status: (@MainActor @Sendable (String) -> Void)?
        ) async throws -> String {
            active += 1
            maxConcurrent = max(maxConcurrent, active)
            defer {
                active -= 1
            }

            while released.contains(urlString) == false {
                try await Task.sleep(for: .milliseconds(5))
            }
            return "Downloaded \(URL(string: urlString)?.lastPathComponent ?? "media")"
        }

        private var released: Set<String> = []

        func activeCount() -> Int { active }
        func release(_ urlString: String) { released.insert(urlString) }

        func maxConcurrentValue() -> Int {
            maxConcurrent
        }
    }

    func testCompressFileCreatesZipBesideSource() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Foundry-ActionRunner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("note.txt")
        try "hello".write(to: source, atomically: true, encoding: .utf8)
        let runner = ActionRunner(diagnostics: DiagnosticsService())

        let outcome = await runner.execute(CommandExecutionRequest(
            commandID: "test.file",
            action: CommandAction(id: "test.file.compress", title: "Compress", behavior: CompressFileAction(path: source.path))
        )) { _ in }

        guard case let .fileResults(urls) = outcome, let zip = urls.first else {
            return XCTFail("Expected .fileResults, got \(outcome)")
        }
        XCTAssertEqual(zip.pathExtension, "zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path))
    }

    func testMoveToTrashRequiresConfirmationAndTrashesFile() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Foundry-ActionRunner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("doomed.txt")
        try "bye".write(to: source, atomically: true, encoding: .utf8)
        let runner = ActionRunner(diagnostics: DiagnosticsService(), confirmAction: { _, _ in true })

        let outcome = await runner.execute(CommandExecutionRequest(
            commandID: "test.file",
            action: CommandAction(id: "test.file.trash", title: "Move to Trash", behavior: MoveToTrashAction(path: source.path))
        )) { _ in }

        XCTAssertEqual(outcome, .refreshResults(message: "Moved to Trash"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        try? FileManager.default.removeItem(at: folder)
    }

    func testMoveToTrashDeniedLeavesFileUntouched() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Foundry-ActionRunner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("safe.txt")
        try "hi".write(to: source, atomically: true, encoding: .utf8)
        let runner = ActionRunner(diagnostics: DiagnosticsService(), confirmAction: { _, _ in false })

        let outcome = await runner.execute(CommandExecutionRequest(
            commandID: "test.file",
            action: CommandAction(id: "test.file.trash", title: "Move to Trash", behavior: MoveToTrashAction(path: source.path))
        )) { _ in }

        XCTAssertEqual(outcome, .denied(message: "Action cancelled"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testRevealFileReturnsTypedFileResults() async {
        let runner = ActionRunner(diagnostics: DiagnosticsService())

        let outcome = await runner.execute(CommandExecutionRequest(
            commandID: "test.file",
            action: CommandAction(id: "test.file.reveal", title: "Reveal", behavior: RevealFileAction(path: "/tmp/x.txt"))
        )) { _ in }

        XCTAssertEqual(outcome, .fileResults([URL(fileURLWithPath: "/tmp/x.txt")]))
    }

    func testGenerateQRCodeCopiesImageFromClipboardText() async {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ActionRunnerTests.qr"))
        pasteboard.clearContents()
        pasteboard.setString("https://example.com", forType: .string)
        let runner = ActionRunner(diagnostics: DiagnosticsService(), pasteboard: pasteboard, offerQRSave: { _, _ in })

        let outcome = await runner.execute(CommandExecutionRequest(
            commandID: "test.qr",
            action: CommandAction(id: "test.qr.generate", title: "Generate", behavior: GenerateQRCodeAction())
        )) { _ in }

        XCTAssertEqual(outcome, .copied(content: "https://example.com"))
        XCTAssertNotNil(pasteboard.data(forType: .tiff))
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testGenerateQRCodeFailsOnEmptyClipboard() async {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ActionRunnerTests.qrempty"))
        pasteboard.clearContents()
        let runner = ActionRunner(diagnostics: DiagnosticsService(), pasteboard: pasteboard)

        let outcome = await runner.execute(CommandExecutionRequest(
            commandID: "test.qr",
            action: CommandAction(id: "test.qr.generate", title: "Generate", behavior: GenerateQRCodeAction())
        )) { _ in }

        guard case let .failure(message, _) = outcome else {
            return XCTFail("Expected failure, got \(outcome)")
        }
        XCTAssertTrue(message.contains("Clipboard"))
    }

    /// Real Vision recognition — model load dominates the whole suite
    /// (~30 s cold). Opt in with FOUNDRY_SLOW_TESTS=1.
    func testExtractTextFromImageRunsVisionOCR() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FOUNDRY_SLOW_TESTS"] == "1", "Vision OCR model load is ~30 s")
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Foundry-OCR-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let imageURL = folder.appendingPathComponent("label.png")
        try Self.renderTextImage(text: "HELLO WORLD").write(to: imageURL)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ActionRunnerTests.ocr"))
        let runner = ActionRunner(diagnostics: DiagnosticsService(), pasteboard: pasteboard)

        let outcome = await runner.execute(CommandExecutionRequest(
            commandID: "test.ocr",
            action: CommandAction(id: "test.ocr.run", title: "Extract Text", behavior: ExtractTextFromImageAction(path: imageURL.path))
        )) { _ in }

        guard case let .copied(content) = outcome else {
            return XCTFail("Expected .copied, got \(outcome)")
        }
        XCTAssertTrue(content.uppercased().contains("HELLO"))
        XCTAssertEqual(pasteboard.string(forType: .string), content)
    }

    func testPreviewExtractedTextStagesFileAndQuickLooks() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FOUNDRY_SLOW_TESTS"] == "1", "Vision OCR model load is ~30 s")
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Foundry-OCR-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let imageURL = folder.appendingPathComponent("label.png")
        try Self.renderTextImage(text: "HELLO WORLD").write(to: imageURL)

        let runner = ActionRunner(diagnostics: DiagnosticsService())
        var previewed: URL?
        runner.panel.onQuickLook = { url in previewed = url }

        let outcome = await runner.execute(CommandExecutionRequest(
            commandID: "test.ocr.preview",
            action: CommandAction(id: "test.ocr.preview.run", title: "Preview Extracted Text", behavior: PreviewExtractedTextAction(path: imageURL.path))
        )) { _ in }

        XCTAssertEqual(outcome, .stayOpen(message: nil))
        let previewURL = try XCTUnwrap(previewed)
        defer { try? FileManager.default.removeItem(at: previewURL.deletingLastPathComponent()) }
        let staged = try String(contentsOf: previewURL, encoding: .utf8)
        XCTAssertTrue(staged.uppercased().contains("HELLO"))
    }

    func testExtractTextFromImageFailsOnMissingFile() async {
        let runner = ActionRunner(diagnostics: DiagnosticsService())

        let outcome = await runner.execute(CommandExecutionRequest(
            commandID: "test.ocr",
            action: CommandAction(id: "test.ocr.missing", title: "Extract Text", behavior: ExtractTextFromImageAction(path: "/tmp/does-not-exist-\(UUID().uuidString).png"))
        )) { _ in }

        guard case .failure = outcome else {
            return XCTFail("Expected failure, got \(outcome)")
        }
    }

    func testCelebrateStaysOpen() async {
        let runner = ActionRunner(diagnostics: DiagnosticsService())

        let outcome = await runner.execute(CommandExecutionRequest(
            commandID: "test.party",
            action: CommandAction(id: "test.party.go", title: "Celebrate", behavior: CelebrateAction())
        )) { _ in }

        XCTAssertEqual(outcome, .stayOpen(message: nil))
    }

    func testWiFiQRPayloadFormatsAndEscapes() {
        let wpa = wifiQRPayload(ssid: "Home;Net", password: "p:a,s\"s", security: 0)
        XCTAssertEqual(wpa, "WIFI:T:WPA;S:Home\\;Net;P:p\\:a\\,s\\\"s;;")

        let wep = wifiQRPayload(ssid: "Cafe", password: "1234", security: 1)
        XCTAssertEqual(wep, "WIFI:T:WEP;S:Cafe;P:1234;;")

        let open = wifiQRPayload(ssid: "OpenNet", password: "ignored", security: 2)
        XCTAssertEqual(open, "WIFI:T:nopass;S:OpenNet;;")
    }

    func testColorFormatsCoverHexRGBHSLHSVAndOKLCH() {
        let red = NSColor(red: 1, green: 0, blue: 0, alpha: 1)
        let formats = PickColorAction.colorFormats(for: red)
        let map = Dictionary(uniqueKeysWithValues: formats.map { ($0.label, $0.value) })
        XCTAssertEqual(map["Hex"], "#FF0000")
        XCTAssertEqual(map["RGB"], "rgb(255, 0, 0)")
        XCTAssertEqual(map["HSL"], "hsl(0, 100%, 50%)")
        XCTAssertEqual(map["HSV"], "hsv(0, 100%, 100%)")
        XCTAssertTrue(map["OKLCH"]?.hasPrefix("oklch(") == true)
        XCTAssertTrue(map["NSColor"]?.contains("red: 1.000") == true)

        let translucent = NSColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        let translucentFormats = Dictionary(uniqueKeysWithValues: PickColorAction.colorFormats(for: translucent).map { ($0.label, $0.value) })
        XCTAssertEqual(translucentFormats["RGBA"], "rgba(0, 0, 0, 0.50)")
    }

    nonisolated private static func renderTextImage(text: String) throws -> Data {
        let size = NSSize(width: 300, height: 80)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 36),
            .foregroundColor: NSColor.black
        ]
        NSAttributedString(string: text, attributes: attributes).draw(at: NSPoint(x: 12, y: 22))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ActionRunnerTests", code: 1)
        }
        return png
    }

    private final class TestSnippetStore: SnippetStore, Sendable {
        let url = URL(fileURLWithPath: "/tmp/test-snippets.json")
        private let storage: OSAllocatedUnfairLock<[StoredSnippet]>
        init(snippets: [StoredSnippet]) { storage = OSAllocatedUnfairLock(initialState: snippets) }
        func load() -> [StoredSnippet] { storage.withLock { $0 } }
        @discardableResult func save(_ snippets: [StoredSnippet]) -> Result<Void, Error> { storage.withLock { $0 = snippets }; return .success(()) }
    }

    @MainActor
    private final class PermissionWindowManager: WindowManaging {

        func apply(_ placement: WindowPlacement) async -> WindowOperationResult {
            .needsAccessibilityPermission
        }
    }
}

private final class TestKeepAwakeProcess: KeepAwakeProcessHandle {
    var isRunning = true
    private(set) var stopCount = 0

    func stop() {
        stopCount += 1
        isRunning = false
    }
}
