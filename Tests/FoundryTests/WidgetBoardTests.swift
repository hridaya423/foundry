import XCTest
@testable import Foundry

final class WidgetBoardTests: XCTestCase {
    func testClipboardWidgetSummarisesTheNewestHistoryItem() {
        XCTAssertEqual(HomeAccessoryStrip.clipboardSummary(nil).value, "Empty")
        let text = ClipboardHistoryItem(payload: .text("hello"))
        XCTAssertEqual(HomeAccessoryStrip.clipboardSummary(text).value, "5 chars")
        let files = ClipboardHistoryItem(payload: .files([URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/b")]))
        XCTAssertEqual(HomeAccessoryStrip.clipboardSummary(files).value, "2 files")
    }
}
