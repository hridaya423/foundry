import XCTest
@testable import Foundry

@MainActor
final class SnippetStateTests: XCTestCase {
    private func makeState(_ snippets: [StoredSnippet]) -> SnippetState {
        let state = SnippetState(store: InMemorySnippetStore(snippets: snippets))
        state.load()
        return state
    }

    func testTagFilterNarrowsVisibleItems() {
        let state = makeState([
            StoredSnippet(id: "a", title: "Addr", content: "123 Main", tags: ["personal"]),
            StoredSnippet(id: "b", title: "Sig", content: "— Me", tags: ["work"]),
            StoredSnippet(id: "c", title: "Both", content: "x", tags: ["personal", "work"]),
        ])
        XCTAssertEqual(state.allTags, ["personal", "work"])

        state.selectedTag = "personal"
        XCTAssertEqual(Set(state.visibleItems.map(\.id)), ["a", "c"])

        state.selectedTag = "work"
        XCTAssertEqual(Set(state.visibleItems.map(\.id)), ["b", "c"])

        state.selectedTag = nil
        XCTAssertEqual(state.visibleItems.count, 3)
    }

    func testTagFilterCombinesWithQuery() {
        let state = makeState([
            StoredSnippet(id: "a", title: "Home", content: "needle personal", tags: ["personal"]),
            StoredSnippet(id: "b", title: "Work", content: "needle work", tags: ["work"]),
        ])
        state.selectedTag = "work"
        state.query = "needle"
        XCTAssertEqual(state.visibleItems.map(\.id), ["b"])
    }

    func testSortModes() {
        let old = Date(timeIntervalSince1970: 100)
        let new = Date(timeIntervalSince1970: 200)
        let state = makeState([
            StoredSnippet(id: "a", title: "Zebra", content: "x", updatedAt: new, useCount: 1),
            StoredSnippet(id: "b", title: "Apple", content: "x", updatedAt: old, useCount: 9),
            StoredSnippet(id: "c", title: "Mango", content: "x", isPinned: true, updatedAt: old, useCount: 0),
        ])

        state.sortMode = .recent
        XCTAssertEqual(state.visibleItems.map(\.id), ["c", "a", "b"], "pinned first, then updatedAt desc")

        state.sortMode = .title
        XCTAssertEqual(state.visibleItems.map(\.id), ["c", "b", "a"], "pinned first, then alphabetical")

        state.sortMode = .mostUsed
        XCTAssertEqual(state.visibleItems.map(\.id), ["c", "b", "a"], "pinned first, then useCount desc")
    }

    func testCSVExportEscapesAndIncludesUsage() {
        let used = Date(timeIntervalSince1970: 1_700_000_000)
        let state = makeState([
            StoredSnippet(id: "a", title: "T,with\"quotes", content: "multi\nline", keyword: "tt", useCount: 4, lastUsedAt: used),
        ])
        let csv = state.csvExport()
        XCTAssertTrue(csv.hasPrefix("name,keyword,text,uses,last_used\n"))
        XCTAssertTrue(csv.contains("\"T,with\"\"quotes\",\"tt\",\"multi\nline\",\"4\""), "CSV fields are quoted and escaped")
        XCTAssertTrue(csv.hasSuffix("\n"))
    }
}

private final class InMemorySnippetStore: SnippetStore, @unchecked Sendable {
    let url = URL(fileURLWithPath: "/tmp/foundry-snippet-state-tests.json")
    var snippets: [StoredSnippet]
    init(snippets: [StoredSnippet]) { self.snippets = snippets }
    func load() -> [StoredSnippet] { snippets }
    @discardableResult func save(_ snippets: [StoredSnippet]) -> Result<Void, Error> {
        self.snippets = snippets
        return .success(())
    }
}
