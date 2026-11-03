import XCTest
@testable import Foundry
import FoundryServices

@MainActor
final class EmojiPickerStateTests: XCTestCase {
    func testRecentsFallBackToSuggestionsThenPersistMostRecentFirst() throws {
        let localState = LocalStateStore()
        let state = EmojiPickerState(localState: localState)
        XCTAssertFalse(state.hasRecents)
        XCTAssertFalse(state.recents.isEmpty, "suggestions shown before anything is copied")

        state.recordRecent("🎉")
        state.recordRecent("🔥")
        state.recordRecent("🎉")
        XCTAssertEqual(state.recentValues, ["🎉", "🔥"], "deduped, most recent first")

        let emoji = ["😀","😃","😄","😁","😆","😅","🤣","😂","🙂","🙃","😉","😊","😇","🥰"]
        emoji.forEach(state.recordRecent)
        XCTAssertEqual(state.recentValues.count, 12)
        XCTAssertEqual(EmojiPickerState(localState: localState).recentValues, state.recentValues, "persists across instances")
    }
    func testRecentAndAllHaveDistinctIDs() {
        let state = EmojiPickerState(localState: LocalStateStore())
        state.recordRecent("🔥")
        let ids = state.cells.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "🔥 appears in Recent and All with different ids")
        XCTAssertTrue(ids.contains("recent:🔥"))
        XCTAssertTrue(ids.contains("all:🔥"))
    }

    func testWhitespaceQueryCountsAsNoQuery() {
        let state = EmojiPickerState(localState: LocalStateStore())
        state.query = "   "
        XCTAssertFalse(state.hasQuery)
        XCTAssertFalse(state.recentCells.isEmpty)
        state.query = "fire"
        XCTAssertTrue(state.hasQuery)
        XCTAssertTrue(state.recentCells.isEmpty)
    }

    func testArrowsReachRecents() {
        let state = EmojiPickerState(localState: LocalStateStore())
        state.recordRecent("🔥")
        state.reset()
        XCTAssertEqual(state.selectedID, "recent:🔥")
        state.moveRight()
        XCTAssertEqual(state.selectedID, state.resultCells.first?.id)
        state.moveLeft()
        XCTAssertEqual(state.selectedEmoji?.value, "🔥")
    }

    func testCellValueCarriesSkinTone() {
        let state = EmojiPickerState(localState: LocalStateStore())
        state.setSkinTone("🏽")
        let thumbs = state.resultCells.first { $0.item.value == "👍" }!
        XCTAssertEqual(state.toneAppliedValue(thumbs.item), "👍🏽")
        state.select(id: thumbs.id)
        XCTAssertEqual(state.takeSelectedEmoji(), "👍🏽")
    }

    func testCommandDigitsPickASkinTone() {
        let localState = LocalStateStore()
        let state = EmojiPickerState(localState: localState)
        let panel: any PanelFeature = state
        let config = ConfigService(diagnostics: DiagnosticsService(),
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-emoji-\(UUID().uuidString).json"))
        let host = CommandPanelState(registry: CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(DiagnosticsService()),
            diagnostics: DiagnosticsService(), configService: config), actionRunner: ActionRunner(diagnostics: DiagnosticsService()),
            diagnostics: DiagnosticsService(), config: config)
        XCTAssertTrue(panel.handleModeShortcut(ActionShortcut(key: "4", modifiers: [.command]), panel: host) {})
        XCTAssertEqual(state.skinTone, "🏽")
        XCTAssertFalse(panel.handleModeShortcut(ActionShortcut(key: "7", modifiers: [.command]), panel: host) {})
        XCTAssertEqual(EmojiPickerState(localState: localState).skinTone, "🏽")
        host.shutdown()
    }

    func testSkinToneCyclesPersistsAndAppliesOnCopy() throws {
        let localState = LocalStateStore()
        let state = EmojiPickerState(localState: localState)
        XCTAssertEqual(state.skinTone, "")
        state.cycleSkinTone()
        state.cycleSkinTone()
        XCTAssertEqual(state.skinTone, "🏼")
        XCTAssertEqual(EmojiPickerState(localState: localState).skinTone, "🏼", "persists across instances")

        let wave = try XCTUnwrap(state.visibleEmoji.first { $0.value == "👋" })
        XCTAssertEqual(state.toneAppliedValue(wave), "👋🏼")
        state.query = "waving"
        XCTAssertTrue(state.visibleEmoji.contains { $0.value == "👋🏼" },
                      "the produced sequence is a real catalog entry")
        state.query = ""
        let smiley = try XCTUnwrap(state.visibleEmoji.first { $0.value == "😀" })
        XCTAssertEqual(state.toneAppliedValue(smiley), "😀", "no variants → untouched")
    }

    func testBrowseCollapsesVariantsButSearchKeepsThem() throws {
        let state = EmojiPickerState(localState: LocalStateStore())
        XCTAssertFalse(state.visibleEmoji.contains { $0.value == "👋🏼" })
        XCTAssertTrue(state.visibleEmoji.contains { $0.value == "👋" })
        state.query = "medium-light skin"
        XCTAssertTrue(state.visibleEmoji.contains { $0.value == "👋🏼" })
    }

}
