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

private final class TestPasteboardClient: PasteboardClient, @unchecked Sendable {
    var changeCountValue = 0
    var snapshotValue: PasteboardSnapshot?
    var changeCount: Int { changeCountValue }
    func snapshot() -> PasteboardSnapshot? { snapshotValue }
    func write(_ payload: ClipboardPayload) {}
}

private final class RecordingClipboardPersistence: @unchecked Sendable, ClipboardHistoryPersisting {
    private let lock = NSLock()
    private var snapshots: [[ClipboardHistoryItem]] = []

    func load() throws -> [ClipboardHistoryItem] { [] }
    func save(_ items: [ClipboardHistoryItem]) throws { lock.withLock { snapshots.append(items) } }
    func savedSnapshots() -> [[ClipboardHistoryItem]] { lock.withLock { snapshots } }
}

private final class BlockingClipboardPersistence: @unchecked Sendable, ClipboardHistoryPersisting {
    private let started = DispatchSemaphore(value: 0)
    private let allowed = DispatchSemaphore(value: 0)
    private let recording = RecordingClipboardPersistence()
    private let lock = NSLock()
    private var saveCount = 0

    func load() throws -> [ClipboardHistoryItem] { [] }

    func save(_ items: [ClipboardHistoryItem]) throws {
        let shouldBlock = lock.withLock {
            saveCount += 1
            return saveCount == 1
        }
        if shouldBlock {
            started.signal()
            allowed.wait()
        }
        try recording.save(items)
    }

    func waitUntilSaving() { started.wait() }
    func allowSave() { allowed.signal() }
    func savedSnapshots() -> [[ClipboardHistoryItem]] { recording.savedSnapshots() }
}
