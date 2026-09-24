import XCTest
@testable import Foundry

@MainActor
final class EmojiPickerStateTests: XCTestCase {
    func testRecentsFallBackToSuggestionsThenPersistMostRecentFirst() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let state = EmojiPickerState(defaults: defaults)
        XCTAssertFalse(state.hasRecents)
        XCTAssertFalse(state.recents.isEmpty, "suggestions shown before anything is copied")

        state.recordRecent("🎉")
        state.recordRecent("🔥")
        state.recordRecent("🎉")
        XCTAssertEqual(state.recentValues, ["🎉", "🔥"], "deduped, most recent first")

        let emoji = ["😀","😃","😄","😁","😆","😅","🤣","😂","🙂","🙃","😉","😊","😇","🥰"]
        emoji.forEach(state.recordRecent)
        XCTAssertEqual(state.recentValues.count, 12)
        XCTAssertEqual(EmojiPickerState(defaults: defaults).recentValues, state.recentValues, "persists across instances")
    }
    func testColumnsCycleAndPersist() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let state = EmojiPickerState(defaults: defaults)
        XCTAssertEqual(state.columns, 12)
        state.cycleColumns()
        XCTAssertEqual(state.columns, 14)
        state.cycleColumns()
        XCTAssertEqual(state.columns, 10)
        XCTAssertEqual(EmojiPickerState(defaults: defaults).columns, 10)
        defaults.set(7, forKey: "emoji.columns")
        XCTAssertEqual(EmojiPickerState(defaults: defaults).columns, 12, "invalid stored value falls back")
    }

    func testSkinToneCyclesPersistsAndAppliesOnCopy() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let state = EmojiPickerState(defaults: defaults)
        XCTAssertEqual(state.skinTone, "")
        state.cycleSkinTone()
        state.cycleSkinTone()
        XCTAssertEqual(state.skinTone, "🏼")
        XCTAssertEqual(EmojiPickerState(defaults: defaults).skinTone, "🏼", "persists across instances")

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
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let state = EmojiPickerState(defaults: defaults)
        XCTAssertFalse(state.visibleEmoji.contains { $0.value == "👋🏼" })
        XCTAssertTrue(state.visibleEmoji.contains { $0.value == "👋" })
        state.query = "medium-light skin"
        XCTAssertTrue(state.visibleEmoji.contains { $0.value == "👋🏼" })
    }

}
