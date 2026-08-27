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
        let oldPinned = ClipboardHistoryItem(payload: .text("1234"), createdAt: Date(timeIntervalSince1970: 1), isPinned: true)
        let newest = ClipboardHistoryItem(payload: .text("12"), createdAt: Date(timeIntervalSince1970: 2))
        let duplicate = ClipboardHistoryItem(payload: .text("12"), createdAt: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(policy.bounded([duplicate, newest, oldPinned]).map(\.signature), [duplicate.signature, oldPinned.signature])
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
        await MainActor.run { state.captureIfChangedForTesting() }
        let emptyAfterSecret = await MainActor.run { state.items.isEmpty }
        XCTAssertTrue(emptyAfterSecret)
        pasteboard.snapshotValue = PasteboardSnapshot(types: [.string], payload: .text("later"), sourceBundleIdentifier: "com.example")
        await MainActor.run { state.captureIfChangedForTesting() }
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
            await MainActor.run { state.captureIfChangedForTesting() }
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
        state.captureIfChangedForTesting()

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
