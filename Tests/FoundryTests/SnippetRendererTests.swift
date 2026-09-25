import XCTest
@testable import Foundry

final class SnippetRendererTests: XCTestCase {
    func testRendersAllKnownPlaceholdersFromOneInjectedTimestamp() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let context = SnippetRenderContext(
            now: Date(timeIntervalSince1970: 0),
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: calendar,
            clipboard: "copied"
        )

        let rendered = SnippetRenderer.render("{date}|{time}|{clipboard}", context: context)

        XCTAssertEqual(rendered.text, "Jan 1, 1970|12:00 AM|copied")
        XCTAssertEqual(rendered.cursorOffsetFromEnd, 0)
    }

    func testUnknownPlaceholdersRemainAndOnlyTheFirstCursorDeterminesOffset() {
        let rendered = SnippetRenderer.render("a{cursor}bc{cursor}d{unknown}", context: .init(
            now: Date(timeIntervalSince1970: 0),
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: Calendar(identifier: .gregorian),
            clipboard: ""
        ))

        XCTAssertEqual(rendered.text, "abcd{unknown}")
        XCTAssertEqual(rendered.cursorOffsetFromEnd, 13)
    }

    private func context() -> SnippetRenderContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return SnippetRenderContext(
            now: Date(timeIntervalSince1970: 0),
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: calendar,
            clipboard: ""
        )
    }

    func testDateFormatPlaceholder() {
        let rendered = SnippetRenderer.render("due {date:yyyy-MM-dd}", context: context())
        XCTAssertEqual(rendered.text, "due 1970-01-01")
    }

    func testArgumentNamesAreExtractedOnceInOrder() {
        XCTAssertEqual(
            SnippetRenderer.argumentNames(in: "Hi {argument name=\"to\"} re: {argument name=\"topic\"} {argument name=\"to\"}"),
            ["to", "topic"]
        )
        XCTAssertTrue(SnippetRenderer.argumentNames(in: "plain {date}").isEmpty)
    }

    func testArgumentsSubstituteAndMissingNamesKeepTheToken() {
        let rendered = SnippetRenderer.render(
            "Hi {argument name=\"to\"}, {argument name=\"topic\"}",
            context: context(),
            arguments: ["to": "Asha"]
        )
        XCTAssertEqual(rendered.text, "Hi Asha, {argument name=\"topic\"}")
    }
}
