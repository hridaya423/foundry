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
    func testColumnsCycleAndPersist() throws {
        let localState = LocalStateStore()
        let state = EmojiPickerState(localState: localState)
        XCTAssertEqual(state.columns, 12)
        state.cycleColumns()
        XCTAssertEqual(state.columns, 14)
        state.cycleColumns()
        XCTAssertEqual(state.columns, 10)
        XCTAssertEqual(EmojiPickerState(localState: localState).columns, 10)
        localState.set(\.emojiColumns, 7)
        XCTAssertEqual(EmojiPickerState(localState: localState).columns, 12, "invalid stored value falls back")
    }

    func testCommandDigitsPickASkinTone() {
        let localState = LocalStateStore()
        let state = EmojiPickerState(localState: localState)
        let panel: any PanelFeature = state
        let config = ConfigService(diagnostics: DiagnosticsService(),
            url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-emoji-\(UUID().uuidString).json"))
        let host = CommandPanelState(registry: CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: DiagnosticsService()),
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
