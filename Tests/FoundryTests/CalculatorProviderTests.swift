import XCTest
@testable import Foundry

final class CalculatorProviderTests: XCTestCase {
    @MainActor
    func testAnswerCardSplitsEachKindOfAnswer() async {
        let provider = CalculatorProvider(rateSource: { _ in [FrankfurterRate(quote: "EUR", rate: 0.9, date: "2026-11-10")] },
            rateCache: CurrencyRateCache())
        let sum = AnswerCard.content(for: await provider.results(matching: "2+2")[0])
        XCTAssertEqual([sum.left.value, sum.separator, sum.right.value], ["2+2", "=", "4"])

        let currency = AnswerCard.content(for: await provider.results(matching: "10 usd to eur")[0])
        XCTAssertEqual(currency.left, AnswerCard.Side(value: "$10", caption: "US Dollar"))
        XCTAssertEqual(currency.right, AnswerCard.Side(value: "€9", caption: "Euro"))
        XCTAssertEqual(currency.note, "Rate from \(Date(timeIntervalSince1970: 1_794_268_800).formatted(.dateTime.day().month(.abbreviated)))")

        let height = AnswerCard.content(for: await provider.results(matching: "5 ft 10 in to cm")[0])
        XCTAssertEqual(height.left, AnswerCard.Side(value: "5 ft 10 in"))
        XCTAssertEqual(height.right, AnswerCard.Side(value: "177.8", caption: "cm"))

        let now = ISO8601DateFormatter().date(from: "2026-11-10T17:05:00Z")!
        let time = await TimeConversionProvider(now: { now }, localZone: { TimeZone(identifier: "Europe/London")! }).results(matching: "12 pm EST to BST")
        let card = AnswerCard.content(for: time[0])
        XCTAssertEqual(card.left, AnswerCard.Side(value: "12:00 PM", caption: "Eastern Time · EST"))
        XCTAssertEqual(card.right, AnswerCard.Side(value: "5:00 PM", caption: "London · GMT"))
    }

    func testTwoArgumentLogUsesSecondArgumentAsBase() async {
        let provider = CalculatorProvider()
        let result = await provider.results(matching: "log(8, 2)")
        XCTAssertEqual(result.first?.title, "3")
    }

    func testSingleArgumentLogStaysBaseTen() async {
        let provider = CalculatorProvider()
        let result = await provider.results(matching: "log(100)")
        XCTAssertEqual(result.first?.title, "2")
    }

    func testRootUsesSecondArgumentAsDegree() async {
        let provider = CalculatorProvider()
        let result = await provider.results(matching: "root(8, 3)")
        XCTAssertEqual(result.first?.title, "2")
    }

    func testHistoryStoreDeduplicatesAndCapsAtTen() {
        let store = CalculatorHistoryStore(localState: LocalStateStore())

        for i in 1...12 { store.record(expression: "\(i)+0", result: "\(i)") }
        store.record(expression: "10+0", result: "10")

        let entries = store.entries
        XCTAssertEqual(entries.count, 10)
        XCTAssertEqual(entries.first, .init(expression: "10+0", result: "10"))
        XCTAssertEqual(entries.map(\.result), ["10", "12", "11", "9", "8", "7", "6", "5", "4", "3"])
    }
}
