import XCTest
@testable import Foundry

final class ClipboardHistoryStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("clip-store-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func store() -> ClipboardHistoryStore {
        ClipboardHistoryStore(directory: root.appendingPathComponent("data"), legacyURL: root.appendingPathComponent("clipboard-history.json"))
    }

    private let image = Data((0..<256).map { UInt8($0) })

    func testRoundTripKeepsOrderPayloadsAndMetadata() throws {
        let items = [
            ClipboardHistoryItem(payload: .text("hello"), sourceBundleIdentifier: "com.apple.Notes"),
            ClipboardHistoryItem(payload: .image(image), createdAt: Date(timeIntervalSinceReferenceDate: 1_000)),
            ClipboardHistoryItem(payload: .files([URL(fileURLWithPath: "/tmp/a b.txt")]), isPinned: true)
        ]
        try store().save(items)
        let reader = store()
        let loaded = try reader.load().map { item in
            var hydrated = item
            if case let .image(data) = item.payload, data.isEmpty, let bytes = try reader.imageData(signature: item.signature) {
                XCTAssertEqual(item.storedByteCount, bytes.count)
                hydrated.payload = .image(bytes)
                hydrated.storedByteCount = nil
            }
            return hydrated
        }
        XCTAssertEqual(loaded, items)
    }

    func testSaveIsIncrementalUpdatesPinsAndDropsOrphanedImages() throws {
        let store = store()
        let text = ClipboardHistoryItem(payload: .text("keep"))
        let picture = ClipboardHistoryItem(payload: .image(image))
        try store.save([picture, text])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.imagesURL.path), [picture.signature])

        var pinned = text
        pinned.isPinned = true
        try store.save([pinned])
        XCTAssertEqual(try store.load(), [pinned])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.imagesURL.path), [])
    }

    func testImagesStayOnDiskUntilShownButCountTowardTheSizeLimit() throws {
        let store = store()
        let images = (0..<30).map { ClipboardHistoryItem(payload: .image(Data(repeating: UInt8($0), count: 64))) }
        try store.save(images)

        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 30)
        for (index, item) in loaded.enumerated() {
            guard case let .image(data) = item.payload else { return XCTFail("expected image at \(index)") }
            XCTAssertTrue(data.isEmpty, "image \(index) should stay on disk")
            XCTAssertEqual(item.memoryCost, 64)
            XCTAssertEqual(try store.imageData(signature: item.signature), Data(repeating: UInt8(index), count: 64))
        }
        XCTAssertEqual(ClipboardHistoryPolicy(maxBytes: 64 * 10).bounded(loaded).count, 10)
        try store.save(loaded)
        for (index, item) in try store.load().enumerated() {
            XCTAssertEqual(try store.imageData(signature: item.signature), Data(repeating: UInt8(index), count: 64))
        }
    }

    func testLegacyArchiveMigratesOnceAndLeavesNoPlaintextCopy() throws {
        let legacy = root.appendingPathComponent("clipboard-history.json")
        let leftover = legacy.appendingPathExtension("migrated")
        let items = [ClipboardHistoryItem(payload: .text("from 1.0")), ClipboardHistoryItem(payload: .text("second"))]
        try ClipboardHistoryPersistence(url: legacy).save(items)
        try Data("old plaintext".utf8).write(to: leftover)

        XCTAssertEqual(try store().load(), items)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))

        try store().save([])
        try ClipboardHistoryPersistence(url: legacy).save(items)
        XCTAssertEqual(try store().load(), items, "an empty database re-imports only while a legacy file is present")
    }

    func testCorruptLegacyArchiveIsLeftIntact() throws {
        let legacy = root.appendingPathComponent("clipboard-history.json")
        try Data("not json".utf8).write(to: legacy)
        XCTAssertThrowsError(try store().load())
        XCTAssertEqual(try Data(contentsOf: legacy), Data("not json".utf8))
    }

    func testDatabaseAndImagesAreOwnerOnly() throws {
        let store = store()
        try store.save([ClipboardHistoryItem(payload: .image(image))])
        let permissions = { (url: URL) in (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue }
        XCTAssertEqual(try permissions(store.databaseURL), 0o600)
        XCTAssertEqual(try permissions(store.imagesURL), 0o700)
    }
}
