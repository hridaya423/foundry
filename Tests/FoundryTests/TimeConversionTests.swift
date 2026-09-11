import XCTest
@testable import Foundry
import FoundryDomain

final class TimeConversionTests: XCTestCase {
    // Friday 2026-09-11 14:00 UTC = 10:00 AM EDT = 7:00 AM PDT = 11:00 PM JST
    private let now = ISO8601DateFormatter().date(from: "2026-09-11T14:00:00Z")!
    private let ny = TimeZone(identifier: "America/New_York")!
    private let la = TimeZone(identifier: "America/Los_Angeles")!

    private func convert(_ query: String, local: TimeZone? = nil) -> [TimeConversionEngine.Conversion] {
        TimeConversionEngine.conversions(for: query, now: now, local: local ?? ny)
    }

    // MARK: - Current time

    func testNowReturnsLocalUTCAndUnixRows() {
        let rows = convert("now")
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].title, "10:00 AM")
        XCTAssertTrue(rows[0].subtitle.contains("Your time"))
        XCTAssertEqual(rows[1].title, "2:00 PM")
        XCTAssertEqual(rows[2].title, String(Int(now.timeIntervalSince1970)))
    }

    func testNowInTokyo() {
        let rows = convert("now in tokyo")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].title, "11:00 PM")
        XCTAssertTrue(rows[0].subtitle.contains("Tokyo (JST)"))
        XCTAssertTrue(rows[0].subtitle.contains("13h ahead of you"))
    }

    func testNowInSanFranciscoAlias() {
        let rows = convert("now in sf")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].title, "7:00 AM")
        XCTAssertTrue(rows[0].subtitle.contains("PDT"))
        XCTAssertTrue(rows[0].subtitle.contains("3h behind you"))
    }

    func testWhatTimeIsItInBerlin() {
        let rows = convert("what time is it in berlin")
        XCTAssertEqual(rows.first?.title, "4:00 PM")
        XCTAssertTrue(rows[0].subtitle.contains("CEST"))
    }

    func testZoneTimeSuffix() {
        XCTAssertEqual(convert("london time").first?.title, "3:00 PM")
    }

    // MARK: - Conversions

    func testConversionToLocalAndUTC() {
        let rows = convert("12pm est")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].title, "12:00 PM")
        XCTAssertEqual(rows[0].subtitle, "12:00 PM EDT → Your time (EDT)")
        XCTAssertEqual(rows[0].copyText, "12:00 PM EDT")
        XCTAssertEqual(rows[0].copyLine, "12:00 PM EDT → 12:00 PM EDT")
        XCTAssertEqual(rows[0].isoText, "2026-09-11T16:00:00Z")
        XCTAssertEqual(rows[1].title, "4:00 PM")
    }

    func testConversionToOtherLocalZone() {
        let rows = convert("12pm est", local: la)
        XCTAssertEqual(rows[0].title, "9:00 AM")
        XCTAssertTrue(rows[0].subtitle.contains("Eastern Time"))
        XCTAssertTrue(rows[0].subtitle.contains("Your time (PDT)"))
    }

    func testExplicitMultiTarget() {
        let rows = convert("12pm est to pst and ist")
        XCTAssertEqual(rows.map(\.title), ["9:00 AM", "9:30 PM"])
        XCTAssertTrue(rows[1].subtitle.contains("India (IST)"))
    }

    func testExplicitTargetsSkipUnresolvableZones() {
        let rows = convert("12pm est to xqz and london")
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].subtitle.contains("London"))
    }

    func testAllUnresolvableTargetsReturnNothing() {
        XCTAssertTrue(convert("12pm est to xqz").isEmpty)
    }

    func testTwentyFourHourInput() {
        XCTAssertEqual(convert("15:30 london").first?.title, "10:30 AM")
    }

    func testNoonAndMidnight() {
        XCTAssertEqual(convert("noon tokyo").first?.title, "11:00 PM")
        XCTAssertEqual(convert("midnight london").first?.title, "7:00 PM")
    }

    func testTomorrowModifier() {
        // now is Friday; 12pm tomorrow in NY is Saturday -> weekday prefix shows the shift
        let rows = convert("12pm est tomorrow")
        XCTAssertEqual(rows.first?.title, "Sat 12:00 PM")
        XCTAssertEqual(rows.first?.isoText, "2026-09-12T16:00:00Z")
    }

    func testWeekdayModifierPicksNextOccurrenceInSourceZone() {
        // Friday 11pm in Tokyo: this Friday's 9am already passed -> next Friday Sep 18 9am JST
        let rows = convert("9am tokyo friday")
        XCTAssertEqual(rows.first?.isoText, "2026-09-18T00:00:00Z")
        XCTAssertEqual(rows.first?.title, "Thu 8:00 PM")
        XCTAssertTrue(rows[0].subtitle.contains("Fri 9:00 AM JST in Tokyo"))
    }

    func testYesterdayModifier() {
        let rows = convert("3pm london yesterday")
        XCTAssertEqual(rows.first?.isoText, "2026-09-10T14:00:00Z")
    }

    // MARK: - DST boundaries

    func testUSForwardEuropeNotGapIsFourHours() {
        // Mar 20 2026: US on EDT (-4), London still GMT (+0) -> 4h gap, not the usual 5h
        let march = ISO8601DateFormatter().date(from: "2026-03-20T14:00:00Z")!
        let rows = TimeConversionEngine.conversions(for: "12pm est to london", now: march, local: ny)
        XCTAssertEqual(rows.first?.title, "4:00 PM")
        XCTAssertTrue(rows[0].subtitle.contains("EDT"))
    }

    func testSpringForwardNonexistentWallTimeStillResolves() {
        // Mar 8 2026 2:30 AM does not exist in New York; .nextTime skips the gap
        let before = ISO8601DateFormatter().date(from: "2026-03-07T20:00:00Z")!
        let rows = TimeConversionEngine.conversions(for: "2:30am est sunday", now: before, local: ny)
        XCTAssertFalse(rows.isEmpty)
    }

    func testWinterAbbreviationIsHonest() {
        // January: New York really is EST, and the label should say so
        let january = ISO8601DateFormatter().date(from: "2026-01-15T14:00:00Z")!
        let rows = TimeConversionEngine.conversions(for: "now in nyc", now: january, local: ny)
        XCTAssertTrue(rows[0].subtitle.contains("(EST)"))
    }

    // MARK: - Quiet on non-matches

    func testNonTimeQueriesReturnNothing() {
        for query in ["hello", "2+2", "12pm", "now in atlantis", "12pm xqz", "download https://x.com/v.mp4"] {
            XCTAssertTrue(convert(query).isEmpty, "expected no results for \(query)")
        }
    }

    // MARK: - Provider wiring

    func testProviderProducesCopyableResults() async {
        let now = self.now
        let la = self.la
        let provider = TimeConversionProvider(now: { now }, localZone: { la })
        let results = await provider.search(CommandSearchRequest(query: "12pm est"))
        XCTAssertEqual(results.first?.title, "9:00 AM")
        XCTAssertEqual(results.first?.primaryAction.kind, .copyToClipboard("9:00 AM PDT"))
        XCTAssertTrue(provider.isActive(for: "now in sf"))
        XCTAssertFalse(provider.isActive(for: "hello"))
    }
}
