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

    func testPolicyDeduplicatesFrontAndEvictsPinsOnlyForHardBound() {
        let policy = ClipboardHistoryPolicy(maxItems: 3, maxBytes: 5)
        let oldPinned = ClipboardHistoryItem(payload: .text("1234"), createdAt: Date(timeIntervalSince1970: 1), isPinned: true)
        let newest = ClipboardHistoryItem(payload: .text("12"), createdAt: Date(timeIntervalSince1970: 2))
        let duplicate = ClipboardHistoryItem(payload: .text("12"), createdAt: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(policy.bounded([oldPinned, newest, duplicate]).map(\.signature), [oldPinned.signature])
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

    func testMutationsPersist() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ClipboardHistoryPersistence(url: url)
        var item = ClipboardHistoryItem(payload: .text("x"))
        try store.save([item])
        item.isPinned = true
        try store.save([item])
        XCTAssertTrue(try store.load()[0].isPinned)
    }
}

private final class TestPasteboardClient: PasteboardClient, @unchecked Sendable {
    var changeCountValue = 0
    var snapshotValue: PasteboardSnapshot?
    var changeCount: Int { changeCountValue }
    func snapshot() -> PasteboardSnapshot? { snapshotValue }
    func write(_ payload: ClipboardPayload) {}
}
