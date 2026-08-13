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
}

private final class InMemorySnippetStore: SnippetStore, @unchecked Sendable {
    let url = URL(fileURLWithPath: "/tmp/in-memory-snippets.json")
    var snippets: [StoredSnippet] = []
    func load() -> [StoredSnippet] { snippets }
    @discardableResult func save(_ snippets: [StoredSnippet]) -> Result<Void, Error> { self.snippets = snippets; return .success(()) }
}
