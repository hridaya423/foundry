import XCTest
import FoundryDomain
import FoundryServices
@testable import Foundry

final class DateMathTests: XCTestCase {
    // Friday 2026-09-11, 10:00 in New York
    private let now = ISO8601DateFormatter().date(from: "2026-09-11T14:00:00Z")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func answer(_ query: String) -> DateMath.Answer? {
        DateMath.answer(for: query, now: now, calendar: calendar)
    }

    func testAnOffsetFromTodayGivesADate() {
        let cases = [
            "30 days from now": "Oct 11, 2026", "in 2 weeks": "Sep 25, 2026", "3 months ago": "Jun 11, 2026", "today + 2 weeks": "Sep 25, 2026",
            "a week from today": "Sep 18, 2026", "1 year from now": "Sep 11, 2027", "90 days ago": "Jun 13, 2026", "today - 1 day": "Sep 10, 2026",
            "What is 30 days from now?": "Oct 11, 2026", "tomorrow plus 3 days": "Sep 15, 2026"
        ]
        for (query, expected) in cases {
            XCTAssertEqual(answer(query)?.to.value, expected, query)
        }
        let thirty = answer("30 days from now")
        XCTAssertEqual(thirty?.from, DateMath.Side(value: "30 days", caption: "from today"))
        XCTAssertEqual(thirty?.to.caption, "Sunday")
        XCTAssertEqual(thirty?.isoText, "2026-10-11")
        XCTAssertEqual(answer("3 months ago")?.from, DateMath.Side(value: "3 months", caption: "ago"))
        XCTAssertEqual(answer("3 months ago")?.to.caption, "Thursday")
    }

    func testAnOffsetFromANamedDate() {
        XCTAssertEqual(answer("2 weeks after christmas")?.to.value, "Jan 8, 2027")
        XCTAssertEqual(answer("2 weeks after christmas")?.from, DateMath.Side(value: "2 weeks", caption: "after Dec 25, 2026"))
        XCTAssertEqual(answer("10 days before dec 25")?.to.value, "Dec 15, 2026")
        XCTAssertEqual(answer("2027-01-01 + 30 days")?.to.value, "Jan 31, 2027")
    }

    func testCountingToAndFromADate() {
        let christmas = answer("days until christmas")
        XCTAssertEqual(christmas?.to, DateMath.Side(value: "105 days", caption: "from today"))
        XCTAssertEqual(christmas?.from, DateMath.Side(value: "Dec 25, 2026", caption: "Friday"))
        XCTAssertEqual(christmas?.copyText, "105")
        XCTAssertNil(christmas?.isoText)

        XCTAssertEqual(answer("how many days until christmas?")?.to.value, "105 days")
        XCTAssertEqual(answer("weeks until christmas")?.to.value, "15 weeks")
        XCTAssertEqual(answer("weeks until 2027-01-01")?.to.value, "16 weeks")
        XCTAssertEqual(answer("weeks until dec 27")?.to.value, "15 weeks 2 days")
        XCTAssertEqual(answer("days till 2027-01-01")?.to.value, "112 days")
        XCTAssertEqual(answer("months until christmas")?.to.value, "3 months 14 days")
        XCTAssertEqual(answer("days since jan 1")?.to, DateMath.Side(value: "253 days", caption: "ago"))
        XCTAssertEqual(answer("days since jan 1")?.from.value, "Jan 1, 2026")
        XCTAssertEqual(answer("days between jan 1 and mar 1")?.to, DateMath.Side(value: "59 days", caption: "to Mar 1, 2026"))
        XCTAssertEqual(answer("days until tomorrow")?.to.value, "1 day")
    }

    func testAPassedDateRollsToItsNextOccurrence() {
        XCTAssertEqual(answer("days until jan 1")?.from.value, "Jan 1, 2027")
        XCTAssertEqual(answer("days until halloween")?.to.value, "50 days")
        XCTAssertEqual(answer("days since christmas")?.from.value, "Dec 25, 2025")
        XCTAssertEqual(answer("days until friday")?.to.value, "7 days")
        XCTAssertEqual(answer("days until 25 december 2030")?.from.value, "Dec 25, 2030")
    }

    func testOtherQueriesAreNotDateMaths() {
        for query in ["30 days", "days", "christmas", "from now", "30 from now", "3 hours in minutes", "days until", "days until potato",
                      "2 weeks in days", "time in tokyo", "in 5", "feb 30 + 1 day"] {
            XCTAssertNil(answer(query), query)
        }
    }

    func testProviderOffersTheDateAsAnAnswer() async {
        let provider = TimeConversionProvider(now: { ISO8601DateFormatter().date(from: "2026-09-11T14:00:00Z")! },
            localZone: { TimeZone(identifier: "America/New_York")! })
        let results = await provider.search(CommandSearchRequest(query: "days until christmas"))
        XCTAssertEqual(results.map(\.title), ["105 days"])
        XCTAssertEqual(results.first?.payload.isAnswer, true)
        XCTAssertEqual(results.first?.primaryAction.behavior as? CopyToClipboardAction, CopyToClipboardAction("105"))
        XCTAssertTrue(provider.isActive(for: "30 days from now"))
    }
}
