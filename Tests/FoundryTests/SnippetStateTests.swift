import os
import XCTest
import FoundryDomain
@testable import Foundry
import FoundryServices

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

    func testRootSearchPrimaryActionFollowsPreference() async {
        let provider = LibraryProvider(store: InMemorySnippetStore(snippets: [
            StoredSnippet(id: "a", title: "Addr", content: "123 Main"),
        ]))

        let insertFirst = await provider.search(CommandSearchRequest(query: "Addr", snippetInsertAsPrimary: true))
        XCTAssertEqual(insertFirst.first?.primaryAction.behavior as? PasteSnippetAction, PasteSnippetAction(id: "a"))

        let copyFirst = await provider.search(CommandSearchRequest(query: "Addr", snippetInsertAsPrimary: false))
        XCTAssertEqual(copyFirst.first?.primaryAction.behavior as? CopySnippetAction, CopySnippetAction(id: "a"))
        XCTAssertEqual(copyFirst.first?.secondaryActions.first?.behavior as? PasteSnippetAction, PasteSnippetAction(id: "a"))
    }

    func testSnippetWithArgumentsAsksBeforeCopyAndEditOpensItSelected() {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics,
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-snip-\(UUID().uuidString).json"))
        let state = CommandPanelState(
            registry: CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics,
                configService: config),
            actionRunner: ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics, config: config,
            snippetStore: InMemorySnippetStore(snippets: [
                StoredSnippet(id: "plain", title: "Plain", content: "x"),
                StoredSnippet(id: "ask", title: "Ask", content: "Hi {argument}"),
            ]))

        state.router.open(.snippet(id: "ask", then: .copy))
        XCTAssertEqual(state.snippets.selectedID, "ask")
        XCTAssertEqual(state.pendingSnippetArguments, SnippetArgumentRequest(names: ["Argument"], copyOnly: true))

        state.router.open(.snippet(id: "plain", then: .select))
        XCTAssertEqual(state.snippets.selectedID, "plain")
        XCTAssertNil(state.pendingSnippetArguments)
        state.shutdown()
    }

    func testRootSnippetWithArgumentsRoutesToThePromptAndOffersEdit() async {
        let store = InMemorySnippetStore(snippets: [StoredSnippet(id: "a", title: "Greet", content: "Hi {argument name=\"to\"}")])
        let runner = ActionRunner(diagnostics: DiagnosticsService(), snippetStore: store)
        let insert = CommandAction(id: "i", title: "Insert", behavior: PasteSnippetAction(id: "a"))
        let outcome = await runner.execute(CommandExecutionRequest(commandID: "i", action: insert)) { _ in }
        XCTAssertEqual(outcome, .open(route: .snippet(id: "a", then: .insert)))

        let results = await LibraryProvider(store: store).search(CommandSearchRequest(query: "Greet"))
        let edit = results.first?.secondaryActions.first { $0.behavior is EditSnippetAction }
        XCTAssertEqual(edit?.behavior.shortcut, ActionShortcut(key: "e", modifiers: [.command]))
    }
}

private final class InMemorySnippetStore: SnippetStore, Sendable {
    let url = URL(fileURLWithPath: "/tmp/foundry-snippet-state-tests.json")
    private let storage: OSAllocatedUnfairLock<[StoredSnippet]>
    init(snippets: [StoredSnippet]) { storage = OSAllocatedUnfairLock(initialState: snippets) }
    func load() -> [StoredSnippet] { storage.withLock { $0 } }
    @discardableResult func save(_ snippets: [StoredSnippet]) -> Result<Void, Error> {
        storage.withLock { $0 = snippets }
        return .success(())
    }
}
