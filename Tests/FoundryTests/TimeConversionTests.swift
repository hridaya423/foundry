import XCTest
@testable import Foundry
import FoundryDomain
import FoundryServices

final class TimeConversionTests: XCTestCase {
    // Friday 2026-09-11 14:00 UTC = 10:00 AM EDT = 7:00 AM PDT = 11:00 PM JST
    private let now = ISO8601DateFormatter().date(from: "2026-09-11T14:00:00Z")!
    private let ny = TimeZone(identifier: "America/New_York")!
    private let la = TimeZone(identifier: "America/Los_Angeles")!

    private func convert(_ query: String, local: TimeZone? = nil) -> [TimeConversionEngine.Conversion] {
        TimeConversionEngine.conversions(for: query, now: now, local: local ?? ny)
    }

    // MARK: - Current time

    func testNowReturnsUTCAndUnixRowsFromLocalTime() {
        let rows = convert("now")
        XCTAssertEqual(rows.map(\.title), ["2:00 PM", String(Int(now.timeIntervalSince1970))])
        XCTAssertEqual(rows[0].source, TimeConversionEngine.Reading(time: "10:00 AM", place: "Your time", abbreviation: "EDT", day: nil))
        XCTAssertEqual(rows[0].target.caption, "UTC")
    }

    func testFillerWordsAroundAPlaceStillAnswer() {
        for query in ["time in SF now", "time in sf", "sf time", "time sf", "sf now", "what's the time in sf?", "What time is it in SF right now",
                      "current time in sf", "sf time now"] {
            XCTAssertEqual(convert(query).map(\.title), ["7:00 AM"], query)
        }
        XCTAssertEqual(convert("what's the time").first?.title, "2:00 PM")
        XCTAssertEqual(convert("utc").map(\.title), ["2:00 PM"])
    }

    func testZoneToZoneConvertsTheCurrentTime() {
        let rows = convert("est to ist")
        XCTAssertEqual(rows.map(\.title), ["7:30 PM"])
        XCTAssertEqual(rows[0].source.time, "10:00 AM")
        XCTAssertEqual(rows[0].copyLine, "10:00 AM EDT → 7:30 PM IST")
    }

    func testZoneBeforeTheClockAndDayWordsAnywhere() {
        XCTAssertEqual(convert("tokyo 9am", local: la).first?.isoText, "2026-09-11T00:00:00Z")
        XCTAssertEqual(convert("9am tomorrow tokyo", local: la).first?.isoText, "2026-09-12T00:00:00Z")
        XCTAssertEqual(convert("tomorrow 9am in tokyo", local: la).first?.isoText, "2026-09-12T00:00:00Z")
        XCTAssertEqual(convert("3pm pst to my time").map(\.title), ["6:00 PM"])
    }

    func testATimeIsReadOnTheSourceZonesCurrentDay() {
        // 9 AM in New York has passed at 10 AM; the answer stays on today instead of jumping to tomorrow.
        let rows = convert("9am est to london")
        XCTAssertEqual(rows.first?.isoText, "2026-09-11T13:00:00Z")
        XCTAssertNil(rows.first?.target.day)
    }

    func testTargetOnAnotherDayIsLabelled() {
        XCTAssertEqual(convert("3pm pst in ist").first?.target.day, "next day")
        XCTAssertEqual(convert("time in auckland").first?.target.day, "tomorrow")
    }

    func testALocalZoneOnUTCGetsOneDefaultRow() {
        let london = TimeZone(identifier: "Europe/London")!
        let winter = ISO8601DateFormatter().date(from: "2026-11-10T14:00:00Z")!
        let rows = TimeConversionEngine.conversions(for: "9am pst", now: winter, local: london)
        XCTAssertEqual(rows.map(\.title), ["5:00 PM"])
        XCTAssertEqual(rows.first?.target.place, "Your time")
        XCTAssertEqual(TimeConversionEngine.conversions(for: "now", now: winter, local: london).first?.target.caption, "UTC")
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
        let rows = convert("12pm est", local: la)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].title, "9:00 AM")
        XCTAssertEqual(rows[0].subtitle, "12:00 PM EDT in Eastern Time → Your time (PDT)")
        XCTAssertEqual(rows[0].copyText, "9:00 AM PDT")
        XCTAssertEqual(rows[0].copyLine, "12:00 PM EDT → 9:00 AM PDT")
        XCTAssertEqual(rows[0].isoText, "2026-09-11T16:00:00Z")
        XCTAssertEqual(rows[1].title, "4:00 PM")
        XCTAssertEqual(convert("12pm est").map(\.title), ["4:00 PM"], "the user's own zone is not offered as a target for itself")
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
        let rows = convert("12pm est tomorrow", local: la)
        XCTAssertEqual(rows.first?.title, "9:00 AM")
        XCTAssertEqual(rows.first?.source.day, "Sat")
        XCTAssertEqual(rows.first?.target.day, "Sat")
        XCTAssertEqual(rows.first?.isoText, "2026-09-12T16:00:00Z")
    }

    func testWeekdayModifierPicksNextOccurrenceInSourceZone() {
        // Friday 11pm in Tokyo: this Friday's 9am already passed -> next Friday Sep 18 9am JST
        let rows = convert("9am tokyo friday")
        XCTAssertEqual(rows.first?.isoText, "2026-09-18T00:00:00Z")
        XCTAssertEqual(rows.first?.title, "8:00 PM")
        XCTAssertEqual(rows.first?.target.day, "Thu")
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
        XCTAssertEqual(results.first?.primaryAction.behavior as? CopyToClipboardAction, CopyToClipboardAction("9:00 AM PDT"))
        XCTAssertTrue(provider.isActive(for: "now in sf"))
        XCTAssertFalse(provider.isActive(for: "hello"))
    }

    func testDefaultRegistrySearchReturnsTimeConversion() async {
        let diagnostics = DiagnosticsService()
        let configURL = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-time-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: configURL) }
        let config = ConfigService(diagnostics: diagnostics, url: configURL)
        let registry = CommandRegistry.defaultRegistry(config: config, diagnostics: diagnostics, usageRanking: .scratch(diagnostics))
        let results = await registry.fullResults(matching: "12pm est")
        XCTAssertTrue(results.contains { $0.id.hasPrefix("time.") })
    }

    func testClockWithZoneAndTimeSuffixConverts() {
        let withSuffix = convert("9am pacific time").map(\.title)
        XCTAssertFalse(withSuffix.isEmpty)
        XCTAssertEqual(withSuffix, convert("9am pacific").map(\.title))
    }
}
