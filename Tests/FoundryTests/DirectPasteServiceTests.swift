import AppKit
import XCTest
@testable import Foundry

@MainActor
final class DirectPasteServiceTests: XCTestCase {
    func testCaptureIgnoresFoundryAndStagesTextWithMarker() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("DirectPasteServiceTests"))
        let target = FakeTarget(processIdentifier: 42)
        let service = DirectPasteService(pasteboard: pasteboard, ownProcessIdentifier: 7) { target }

        service.captureTarget()
        try service.stage(ClipboardPayload.text("hello"))

        XCTAssertEqual(pasteboard.string(forType: .string), "hello")
        XCTAssertEqual(pasteboard.string(forType: DirectPasteService.foundryMarker), "Foundry")
        XCTAssertTrue(service.hasPendingPaste)
    }

    func testCaptureDoesNotKeepOwnProcessAsTarget() {
        let target = FakeTarget(processIdentifier: 7)
        let service = DirectPasteService(ownProcessIdentifier: 7) { target }
        service.captureTarget()
        XCTAssertFalse(service.hasPendingPaste)
        XCTAssertThrowsError(try service.stage(.text("hello"))) { error in
            XCTAssertEqual(error as? DirectPasteError, .missingTarget)
        }
    }

    func testStageFilesAndImages() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("DirectPasteServiceTests.payload"))
        let target = FakeTarget(processIdentifier: 42)
        let service = DirectPasteService(pasteboard: pasteboard) { target }
        service.captureTarget()
        try service.stage(ClipboardPayload.files([URL(fileURLWithPath: "/tmp/example.txt")]))
        XCTAssertNotNil(pasteboard.readObjects(forClasses: [NSURL.self], options: nil))
        XCTAssertThrowsError(try service.stage(ClipboardPayload.image(Data([1, 2, 3])))) { error in
            XCTAssertEqual(error as? DirectPasteError, .stagingFailed)
        }
        let imageService = DirectPasteService(pasteboard: pasteboard) { target }
        imageService.captureTarget()
        try imageService.stage(ClipboardPayload.image(Data([1, 2, 3])))
        XCTAssertEqual(pasteboard.data(forType: .tiff), Data([1, 2, 3]))
    }

    func testSecondStageCannotReplacePendingPaste() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("DirectPasteServiceTests.overlap"))
        pasteboard.clearContents()
        pasteboard.setString("before", forType: .string)
        let target = FakeTarget(processIdentifier: 42)
        let service = DirectPasteService(pasteboard: pasteboard) { target }
        service.captureTarget()
        try service.stage(.text("first"))

        XCTAssertThrowsError(try service.stage(.text("second"))) { error in
            XCTAssertEqual(error as? DirectPasteError, .stagingFailed)
        }
        XCTAssertEqual(pasteboard.string(forType: .string), "first")
    }

    func testDeniedAccessibilityIsExplicitAndDoesNotPrompt() async throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("DirectPasteServiceTests.denied"))
        pasteboard.clearContents()
        pasteboard.setString("before", forType: .string)
        let target = FakeTarget(processIdentifier: 42)
        var events: [DirectPasteEvent] = []
        let service = DirectPasteService(
            pasteboard: pasteboard,
            ownProcessIdentifier: 7,
            targetProvider: { target },
            accessibilityTrusted: { false },
            record: { events.append($0) }
        )

        service.captureTarget()
        try service.stage(.text("hello"))
        do {
            try await service.completePendingPaste(after: .zero)
            XCTFail("Expected permission failure")
        } catch {
            XCTAssertEqual(error as? DirectPasteError, .accessibilityPermission)
            XCTAssertEqual(target.activationCount, 0)
            XCTAssertEqual(events, [.staged, .pasteboardRestored])
            XCTAssertFalse(service.hasPendingPaste)
            XCTAssertEqual(pasteboard.string(forType: .string), "before")
        }
    }

    func testActivationFailureRestoresClipboardAndClearsPending() async throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("DirectPasteServiceTests.activation"))
        pasteboard.setString("before", forType: .string)
        let target = FakeTarget(processIdentifier: 42, activates: false)
        let service = DirectPasteService(pasteboard: pasteboard, targetProvider: { target }, accessibilityTrusted: { true })
        service.captureTarget(); try service.stage(.text("hello"))

        do { try await service.completePendingPaste(after: .zero); XCTFail("Expected activation failure") }
        catch { XCTAssertEqual(error as? DirectPasteError, .activationFailed) }
        XCTAssertFalse(service.hasPendingPaste)
        XCTAssertEqual(pasteboard.string(forType: .string), "before")
    }

    func testEventFailureRestoresClipboardAndClearsPending() async throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("DirectPasteServiceTests.event"))
        pasteboard.setString("before", forType: .string)
        let target = FakeTarget(processIdentifier: 42)
        let service = DirectPasteService(pasteboard: pasteboard, targetProvider: { target }, accessibilityTrusted: { true }, sendPaste: { false })
        service.captureTarget(); try service.stage(.text("hello"))

        do { try await service.completePendingPaste(after: .zero); XCTFail("Expected event failure") }
        catch { XCTAssertEqual(error as? DirectPasteError, .eventFailed) }
        XCTAssertFalse(service.hasPendingPaste)
        XCTAssertEqual(pasteboard.string(forType: .string), "before")
    }

    func testCancelledDelayRestoresClipboardAndClearsPending() async throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("DirectPasteServiceTests.cancel"))
        pasteboard.setString("before", forType: .string)
        let target = FakeTarget(processIdentifier: 42)
        let service = DirectPasteService(pasteboard: pasteboard, targetProvider: { target }, accessibilityTrusted: { true })
        service.captureTarget(); try service.stage(.text("hello"))
        let task = Task { @MainActor in try await service.completePendingPaste(after: .seconds(10)) }
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertEqual(error as? DirectPasteError, .cancelled) }
        XCTAssertFalse(service.hasPendingPaste)
        XCTAssertEqual(pasteboard.string(forType: .string), "before")
    }

    func testPasteEventsPreserveInsertionAndRestorationOrder() async throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("DirectPasteServiceTests.order"))
        pasteboard.setString("before", forType: .string)
        let target = FakeTarget(processIdentifier: 42)
        var events: [DirectPasteEvent] = []
        let service = DirectPasteService(
            pasteboard: pasteboard,
            ownProcessIdentifier: 7,
            targetProvider: { target },
            accessibilityTrusted: { true },
            record: { events.append($0) }
        )

        service.captureTarget()
        try service.stage(.text("hello"), cursorOffset: 2)
        try await service.completePendingPaste(after: .zero)

        XCTAssertEqual(events, [.staged, .targetActivated, .pasted, .cursorMoved(count: 2), .pasteboardRestored])
    }

    private final class FakeTarget: NSObject, DirectPasteTarget {
        let processIdentifier: pid_t
        private(set) var activationCount = 0
        private let activates: Bool
        init(processIdentifier: pid_t, activates: Bool = true) { self.processIdentifier = processIdentifier; self.activates = activates }
        func activate(options: NSApplication.ActivationOptions) -> Bool {
            activationCount += 1
            return activates
        }
    }
}
