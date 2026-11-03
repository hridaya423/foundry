import os
import Foundation
import XCTest
@testable import Foundry

final class LibraryPersistenceTests: XCTestCase {
    func testFileSnippetStoreRoundTripsThroughAnInjectedURL() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("foundry-snippets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FileSnippetStore(url: url)
        let snippet = StoredSnippet(title: "Example", content: "echo hello", keyword: "ex")

        if case .failure = store.save([snippet]) {
            XCTFail("Expected snippet save to succeed")
        }
        XCTAssertEqual(store.load(), [snippet])
    }

    func testCorruptSnippetDataFallsBackWithoutReplacingTheFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("foundry-snippets-corrupt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data("not json".utf8)
        try data.write(to: url)

        let store = FileSnippetStore(url: url)

        XCTAssertTrue(store.load().isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    @MainActor func testSnippetKeywordIsTrimmedBeforeSaving() {
        let store = InMemorySnippetStore()
        let state = SnippetState(store: store)
        state.load()
        state.newSnippet()
        state.updateSelected(title: "Example", content: "body", keyword: "  ex  ", tags: [])
        XCTAssertEqual(state.selectedItem?.keyword, "ex")
    }

    @MainActor func testResetFlushesPendingSnippetEditsBeforeReloading() {
        let store = InMemorySnippetStore()
        let state = SnippetState(store: store)
        state.load()
        state.newSnippet()
        state.updateSelected(title: "Example", content: "latest", keyword: "ex", tags: [])

        state.reset()

        XCTAssertEqual(state.items.first?.content, "latest")
        XCTAssertEqual(store.snippets.first?.content, "latest")
    }

    @MainActor func testReloadInvalidatesVisibleSnippetCache() {
        let store = InMemorySnippetStore()
        let state = SnippetState(store: store)
        state.load()
        _ = state.visibleItems

        let replacement = StoredSnippet(title: "Reloaded")
        store.snippets = [replacement]
        state.load()

        XCTAssertEqual(state.visibleItems, [replacement])
    }

    @MainActor func testRemovingSelectedSnippetRepairsCachedSelection() {
        let store = InMemorySnippetStore()
        store.snippets = [StoredSnippet(title: "First"), StoredSnippet(title: "Second")]
        let state = SnippetState(store: store)
        state.load()
        state.select(id: state.visibleItems[0].id)

        state.removeSelected()

        XCTAssertEqual(state.selectedID, state.visibleItems.first?.id)
    }

    func testLegacySnippetFileWithoutUsageFieldsStillDecodes() throws {
        let legacy = """
        [{"id":"a","title":"Sig","content":"Best,\\nH","keyword":"sig","tags":[],"isPinned":false,"updatedAt":0}]
        """.data(using: .utf8)!

        let snippets = try JSONDecoder().decode([StoredSnippet].self, from: legacy)

        XCTAssertEqual(snippets.count, 1)
        XCTAssertEqual(snippets[0].useCount, 0)
        XCTAssertNil(snippets[0].lastUsedAt)
    }

    @MainActor func testCopyingSnippetRecordsUsage() {
        let store = InMemorySnippetStore()
        store.snippets = [StoredSnippet(title: "Sig", content: "body")]
        let state = SnippetState(store: store)
        state.load()

        state.copySelected()

        XCTAssertEqual(state.items.first?.useCount, 1)
        XCTAssertNotNil(state.items.first?.lastUsedAt)
    }

    func testSnippetExpansionConfigKeepsCustomDelimitersAndDropsInvalid() {
        var config = SnippetExpansionConfig()
        config.delimiters = [" ", ";", "", " ", "toolong!"]

        let normalized = config.normalized

        XCTAssertEqual(normalized.delimiters, [" ", ";"])
    }

    func testSnippetExpansionConfigDefaultsDelimitersWhenAbsent() throws {
        let decoded = try JSONDecoder().decode(SnippetExpansionConfig.self, from: Data("{\"isEnabled\":true}".utf8))
        XCTAssertEqual(decoded.delimiters, SnippetExpansionConfig.defaultDelimiters)
    }
}

private final class InMemorySnippetStore: SnippetStore, Sendable {
    let url = URL(fileURLWithPath: "/tmp/in-memory-snippets.json")
    private let storage = OSAllocatedUnfairLock<[StoredSnippet]>(initialState: [])
    var snippets: [StoredSnippet] {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
    func load() -> [StoredSnippet] { snippets }
    @discardableResult func save(_ snippets: [StoredSnippet]) -> Result<Void, Error> { self.snippets = snippets; return .success(()) }
}
