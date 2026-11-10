import os
import SwiftUI
import XCTest
@testable import Foundry

final class ClipboardHistoryTests: XCTestCase {
    func testPayloadsAndMetadataRoundTrip() throws {
        let values = [
            ClipboardHistoryItem(payload: .text("hello"), createdAt: Date(timeIntervalSince1970: 10), sourceBundleIdentifier: "com.example", isPinned: true),
            ClipboardHistoryItem(payload: .files([URL(fileURLWithPath: "/tmp/a")]), createdAt: Date(timeIntervalSince1970: 11)),
            ClipboardHistoryItem(payload: .image(Data([1, 2, 3])), createdAt: Date(timeIntervalSince1970: 12))
        ]
        let decoded = try JSONDecoder().decode([ClipboardHistoryItem].self, from: JSONEncoder().encode(values))
        XCTAssertEqual(decoded, values)
        XCTAssertEqual(values[0].signature, ClipboardHistoryItem(payload: .text("hello")).signature)
    }

    func testPollingBacksOffOnlyWhileTheUserIsIdle() {
        XCTAssertEqual(ClipboardHistoryState.pollInterval(secondsSinceInput: 0), 0.7)
        XCTAssertEqual(ClipboardHistoryState.pollInterval(secondsSinceInput: 59), 0.7)
        XCTAssertEqual(ClipboardHistoryState.pollInterval(secondsSinceInput: 60), 5)
    }

    @MainActor
    func testMonitoringOnlyRunsBetweenStartAndStop() {
        let state = ClipboardHistoryState(pasteboard: TestPasteboardClient(), persistence: nil)
        XCTAssertFalse(state.isMonitoring)

        state.start()
        XCTAssertTrue(state.isMonitoring)
        state.start()
        XCTAssertTrue(state.isMonitoring, "start is idempotent")

        state.stop()
        XCTAssertFalse(state.isMonitoring)
    }

    @MainActor
    func testSelectedImageIsDecodedForThePreview() throws {
        let image = NSImage(size: NSSize(width: 40, height: 20), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let pasteboard = TestClipboardPasteboard()
        let clipboard = ClipboardHistoryState(pasteboard: pasteboard, persistence: nil, configuration: .default)
        pasteboard.snapshotValue = PasteboardSnapshot(types: [.tiff], payload: .image(try XCTUnwrap(image.tiffRepresentation)), sourceBundleIdentifier: nil)
        pasteboard.changeCountValue += 1
        clipboard.captureIfChanged()
        let signature = try XCTUnwrap(clipboard.selectedItem?.signature)
        ClipboardImagePreview.releaseCachedImages()

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 736, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ClipboardHistoryView(state: clipboard))
        RunLoop.main.run(until: Date().addingTimeInterval(1))

        XCTAssertNotNil(ClipboardImagePreview.imageCache.object(forKey: signature as NSString))
    }

    @MainActor
    func testResolvedPayloadHydratesLazilyLoadedImages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("clip-lazy-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ClipboardHistoryStore(directory: root.appendingPathComponent("data"), legacyURL: root.appendingPathComponent("legacy.json"))
        let images = (0..<26).map { ClipboardHistoryItem(payload: .image(Data(repeating: UInt8($0), count: 32))) }
        try store.save(images)

        let state = ClipboardHistoryState(pasteboard: TestPasteboardClient(), persistence: store)
        let tail = state.items[25]
        guard case let .image(staged) = tail.payload else { return XCTFail("expected image") }
        XCTAssertTrue(staged.isEmpty)

        guard case let .image(resolved) = state.resolvedPayload(for: tail.id) else { return XCTFail("expected image") }
        XCTAssertEqual(resolved, Data(repeating: 25, count: 32))
        guard case let .image(cached) = state.items[25].payload else { return XCTFail("expected image") }
        XCTAssertFalse(cached.isEmpty, "hydration caches back into items")
    }

    func testPersistedClipboardAgeIsNotAlwaysNow() {
        let now = Date(timeIntervalSince1970: 10_000)
        let recent = ClipboardHistoryItem(payload: .text("recent"), createdAt: now)
        let old = ClipboardHistoryItem(payload: .text("old"), createdAt: now.addingTimeInterval(-7_200))

        XCTAssertEqual(recent.timeLabel(relativeTo: now), "now")
        XCTAssertNotEqual(old.timeLabel(relativeTo: now), "now")
    }

    func testPersistenceIsAtomicAndCorruptArchiveIsPreserved() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ClipboardHistoryPersistence(url: url)
        let item = ClipboardHistoryItem(payload: .text("saved"))
        try store.save([item])
        XCTAssertEqual(try store.load(), [item])
        try Data("not json".utf8).write(to: url)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: url), Data("not json".utf8))
    }

    func testPolicyPreservesNewestFirstInputWhileDeduplicating() {
        let policy = ClipboardHistoryPolicy(maxItems: 3, maxBytes: 6)
        let now = Date()
        let oldPinned = ClipboardHistoryItem(payload: .text("1234"), createdAt: now, isPinned: true)
        let newest = ClipboardHistoryItem(payload: .text("12"), createdAt: now)
        let duplicate = ClipboardHistoryItem(payload: .text("12"), createdAt: now)
        XCTAssertEqual(policy.bounded([duplicate, newest, oldPinned]).map(\.signature), [duplicate.signature, oldPinned.signature])
    }

    func testPolicyDropsUnpinnedItemsPastTheAgeLimit() {
        let now = Date()
        let policy = ClipboardHistoryPolicy(maxItems: 10, maxBytes: 1_000_000, maxAge: 90 * 86_400)
        let fresh = ClipboardHistoryItem(payload: .text("fresh"), createdAt: now)
        let stale = ClipboardHistoryItem(payload: .text("stale"), createdAt: now.addingTimeInterval(-91 * 86_400))
        let oldPinned = ClipboardHistoryItem(payload: .text("old pinned"), createdAt: now.addingTimeInterval(-400 * 86_400), isPinned: true)
        XCTAssertEqual(policy.bounded([fresh, stale, oldPinned], relativeTo: now).map(\.signature), [fresh.signature, oldPinned.signature])
    }

    func testPinnedItemsSurviveTheItemCountLimit() {
        let policy = ClipboardHistoryPolicy(maxItems: 2, maxBytes: 1_000)
        let pinned = ClipboardHistoryItem(payload: .text("pinned"), isPinned: true)
        let items = [ClipboardHistoryItem(payload: .text("a")), ClipboardHistoryItem(payload: .text("b")), ClipboardHistoryItem(payload: .text("c")), pinned]
        XCTAssertEqual(policy.bounded(items).map(\.id), [items[0].id, pinned.id])
    }

    @MainActor
    func testCopyMergedWithPreviousConcatenatesNewerThenSelected() {
        let pasteboard = TestPasteboardClient()
        let state = ClipboardHistoryState(pasteboard: pasteboard, persistence: nil)
        for payload in [ClipboardPayload.text("older"), .text("newest")] {
            pasteboard.snapshotValue = PasteboardSnapshot(types: [.string], payload: payload, sourceBundleIdentifier: nil)
            pasteboard.changeCountValue += 1
            state.captureIfChanged()
        }
        // items are newest-first; select the older entry, merge with the newer one above it
        let olderID = state.items.last!.id
        state.select(id: olderID)
        XCTAssertTrue(state.copyMergedWithPreviousSelected())
        guard case let .text(merged) = pasteboard.written.last else {
            XCTFail("expected a merged text payload")
            return
        }
        XCTAssertEqual(merged, "newest\n\nolder")
    }

    @MainActor
    func testCopyMergedWithPreviousFailsForNonTextAndTopRow() {
        let pasteboard = TestPasteboardClient()
        let state = ClipboardHistoryState(pasteboard: pasteboard, persistence: nil)
        pasteboard.snapshotValue = PasteboardSnapshot(types: [.string], payload: .text("only"), sourceBundleIdentifier: nil)
        pasteboard.changeCountValue += 1
        state.captureIfChanged()
        state.select(id: state.items.first!.id)
        XCTAssertFalse(state.copyMergedWithPreviousSelected(), "top row has no previous entry to merge with")
        XCTAssertTrue(pasteboard.written.isEmpty)
    }

    @MainActor
    func testSearchFindsSourceAppsAndTheCountNamesWhatIsShown() {
        let pasteboard = TestPasteboardClient()
        let state = ClipboardHistoryState(pasteboard: pasteboard, persistence: nil)
        for (text, source) in [("from the browser", "com.apple.Safari"), ("from the editor", "com.apple.dt.Xcode")] {
            pasteboard.snapshotValue = PasteboardSnapshot(types: [.string], payload: .text(text), sourceBundleIdentifier: source)
            pasteboard.changeCountValue += 1
            state.captureIfChanged()
        }
        XCTAssertEqual(state.countLabel, "2 items")

        state.query = "safari"

        XCTAssertEqual(state.visibleItems.map(\.title), ["from the browser"])
        XCTAssertEqual(state.countLabel, "1 of 2 items")
        state.select(id: state.visibleItems[0].id)
        XCTAssertTrue(state.canMergeSelectedWithPrevious, "the row above is text, so the two can merge")
    }

    @MainActor
    func testKindFiltersFullTextSearchAndPinnedFirst() {
        let pasteboard = TestPasteboardClient()
        let state = ClipboardHistoryState(pasteboard: pasteboard, persistence: nil)
        for payload in [ClipboardPayload.text("first line\nneedle on line two"), .text("https://example.com/path"), .image(Data([1, 2])), .files([URL(fileURLWithPath: "/tmp/x")])] {
            pasteboard.snapshotValue = PasteboardSnapshot(types: [.string], payload: payload, sourceBundleIdentifier: "com.example")
            pasteboard.changeCountValue += 1
            state.captureIfChanged()
        }
        XCTAssertEqual(state.visibleItems.count, 4)

        state.kindFilter = .links
        XCTAssertEqual(state.visibleItems.map(\.title), ["https://example.com/path"])
        state.kindFilter = .text
        XCTAssertEqual(state.visibleItems.map(\.title), ["first line"])
        state.kindFilter = .images
        XCTAssertEqual(state.visibleItems.map(\.kindLabel), ["Image"])
        state.kindFilter = .all

        state.query = "needle"
        XCTAssertEqual(state.visibleItems.map(\.title), ["first line"], "search reaches past the first line")
        state.query = ""

        let oldest = state.visibleItems.last!.id
        state.select(id: oldest)
        state.togglePinSelected()
        XCTAssertEqual(state.visibleItems.first?.id, oldest)
        XCTAssertTrue(state.visibleItems.first!.isPinned)
    }

    func testSystemPasteboardCapturesImageOnlyPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipboardHistoryTests.image"))
        pasteboard.clearContents()
        let data = Data([1, 2, 3])
        pasteboard.setData(data, forType: .tiff)

        let snapshot = SystemPasteboardClient(pasteboard).snapshot()

        XCTAssertEqual(snapshot?.payload, .image(data))
    }

    func testCopiedWebLinkIsTextAndCopiedFileIsAFile() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipboardHistoryTests.link"))
        defer { pasteboard.releaseGlobally() }
        let link = try XCTUnwrap(URL(string: "https://example.com/page"))
        pasteboard.clearContents()
        pasteboard.writeObjects([link as NSURL])
        XCTAssertEqual(SystemPasteboardClient(pasteboard).snapshot()?.payload, .text("https://example.com/page"))

        let file = URL(fileURLWithPath: "/tmp/report.pdf")
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        XCTAssertEqual(SystemPasteboardClient(pasteboard).snapshot()?.payload, .files([file]))
    }

    func testHostilePasteboardTypesAreRejectedAndChangesConsumed() async {
        let pasteboard = TestPasteboardClient()
        let state = await MainActor.run { ClipboardHistoryState(pasteboard: pasteboard, persistence: nil) }
        await MainActor.run { state.start() }
        pasteboard.snapshotValue = PasteboardSnapshot(types: [NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], payload: .text("secret"), sourceBundleIdentifier: "com.passwordmanager")
        pasteboard.changeCountValue += 1
        await MainActor.run { state.captureIfChanged() }
        let emptyAfterSecret = await MainActor.run { state.items.isEmpty }
        XCTAssertTrue(emptyAfterSecret)
        pasteboard.snapshotValue = PasteboardSnapshot(types: [.string], payload: .text("later"), sourceBundleIdentifier: "com.example")
        await MainActor.run { state.captureIfChanged() }
        let emptyAfterLater = await MainActor.run { state.items.isEmpty }
        XCTAssertTrue(emptyAfterLater)
    }

    func testSecretShapedTextNeverEntersHistory() async {
        let pasteboard = TestPasteboardClient()
        let state = await MainActor.run { ClipboardHistoryState(pasteboard: pasteboard, persistence: nil) }
        await MainActor.run { state.start() }
        for (index, text) in ["sk-ant-api03-abcdefghijklmnopqrstuvwxyz012345", "ghp_abcdefghijklmnopqrstuvwxyz0123456789", "plain words here"].enumerated() {
            pasteboard.snapshotValue = PasteboardSnapshot(types: [.string], payload: .text(text), sourceBundleIdentifier: "com.example")
            pasteboard.changeCountValue = index + 1
            await MainActor.run { state.captureIfChanged() }
        }
        let texts = await MainActor.run { state.items.compactMap { if case let .text(value) = $0.payload { value } else { nil } } }
        XCTAssertEqual(texts, ["plain words here"])
        XCTAssertFalse(ClipboardHistoryPolicy.looksLikeSecret("https://example.com/some/long/path/here"))
    }

    func testClipboardCapturesPersistOffMainActorInOrder() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let pasteboard = TestPasteboardClient()
        let persistence = ClipboardHistoryPersistence(url: url)
        let state = await MainActor.run {
            ClipboardHistoryState(pasteboard: pasteboard, persistence: persistence)
        }

        for value in ["first", "second", "third"] {
            pasteboard.snapshotValue = PasteboardSnapshot(types: [.string], payload: .text(value), sourceBundleIdentifier: "com.example")
            pasteboard.changeCountValue += 1
            await MainActor.run { state.captureIfChanged() }
        }
        await state.waitForPersistenceForTesting()

        let saved = try persistence.load()
        XCTAssertEqual(saved.count, 3)
        XCTAssertEqual(saved.compactMap { payload in
            if case let .text(value) = payload.payload { return value }
            return nil
        }, ["third", "second", "first"])
    }

    func testMutationsPersist() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ClipboardHistoryPersistence(url: url)
        var item = ClipboardHistoryItem(payload: .text("x"))
        try store.save([item])
        item.isPinned = true
        try store.save([item])
        XCTAssertTrue(try store.load()[0].isPinned)
    }

    func testPersistenceWriterCoalescesPendingSnapshots() async {
        let persistence = BlockingClipboardPersistence()
        let writer = ClipboardHistoryPersistenceWriter(persistence)
        let first = ClipboardHistoryItem(payload: .text("first"))
        let second = ClipboardHistoryItem(payload: .text("second"))
        let third = ClipboardHistoryItem(payload: .text("third"))

        await writer.schedule([first])
        persistence.waitUntilSaving()
        await writer.schedule([second])
        await writer.schedule([third])
        persistence.allowSave()
        _ = await writer.flush()

        XCTAssertEqual(persistence.savedSnapshots().map { $0.first?.payload }, [.text("first"), .text("third")])
    }

    @MainActor
    func testClipboardShutdownFlushesLatestItems() async {
        let persistence = RecordingClipboardPersistence()
        let pasteboard = TestPasteboardClient()
        let state = ClipboardHistoryState(pasteboard: pasteboard, persistence: persistence)
        pasteboard.snapshotValue = PasteboardSnapshot(types: [.string], payload: .text("latest"), sourceBundleIdentifier: "com.example")
        pasteboard.changeCountValue += 1
        state.captureIfChanged()

        await state.shutdown()

        XCTAssertEqual(persistence.savedSnapshots().last?.first?.payload, .text("latest"))
    }
}

private final class TestPasteboardClient: PasteboardClient, Sendable {
    private struct Box {
        var changeCountValue = 0
        var snapshotValue: PasteboardSnapshot?
        var written: [ClipboardPayload] = []
    }

    private let box = OSAllocatedUnfairLock(uncheckedState: Box())

    var changeCountValue: Int {
        get { box.withLockUnchecked { $0.changeCountValue } }
        set { box.withLockUnchecked { $0.changeCountValue = newValue } }
    }

    var snapshotValue: PasteboardSnapshot? {
        get { box.withLockUnchecked { $0.snapshotValue } }
        set { box.withLockUnchecked { $0.snapshotValue = newValue } }
    }

    var written: [ClipboardPayload] {
        box.withLockUnchecked { $0.written }
    }

    var changeCount: Int { changeCountValue }
    func snapshot() -> PasteboardSnapshot? { snapshotValue }
    func write(_ payload: ClipboardPayload) { box.withLockUnchecked { $0.written.append(payload) } }
}

private final class RecordingClipboardPersistence: Sendable, ClipboardHistoryPersisting {
    private let snapshots = OSAllocatedUnfairLock<[[ClipboardHistoryItem]]>(initialState: [])

    func load() throws -> [ClipboardHistoryItem] { [] }
    func save(_ items: [ClipboardHistoryItem]) throws { snapshots.withLock { $0.append(items) } }
    func imageData(signature _: String) throws -> Data? { nil }
    func savedSnapshots() -> [[ClipboardHistoryItem]] { snapshots.withLock { $0 } }
}

private final class BlockingClipboardPersistence: Sendable, ClipboardHistoryPersisting {
    private let started = DispatchSemaphore(value: 0)
    private let allowed = DispatchSemaphore(value: 0)
    private let recording = RecordingClipboardPersistence()
    private let saveCount = OSAllocatedUnfairLock(initialState: 0)

    func load() throws -> [ClipboardHistoryItem] { [] }

    func save(_ items: [ClipboardHistoryItem]) throws {
        let shouldBlock = saveCount.withLock { count in
            count += 1
            return count == 1
        }
        if shouldBlock {
            started.signal()
            allowed.wait()
        }
        try recording.save(items)
    }

    func imageData(signature _: String) throws -> Data? { nil }
    func waitUntilSaving() { started.wait() }
    func allowSave() { allowed.signal() }
    func savedSnapshots() -> [[ClipboardHistoryItem]] { recording.savedSnapshots() }

    @MainActor
    func testCountsWhatALowerRetentionWouldRemove() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("retention-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ClipboardHistoryPersistence(url: url)
        try store.save((0..<5).map { ClipboardHistoryItem(payload: .text("item \($0)"), createdAt: Date().addingTimeInterval(-Double($0))) })
        let state = ClipboardHistoryState(pasteboard: TestClipboardPasteboard(), persistence: store)
        XCTAssertEqual(state.items.count, 5)
        XCTAssertEqual(state.itemsRemoved(maxItems: 3, maxBytes: state.policy.maxBytes, maxAgeDays: 90), 2)
        XCTAssertEqual(state.itemsRemoved(maxItems: 10, maxBytes: state.policy.maxBytes, maxAgeDays: 90), 0)
    }

}
