import XCTest
@testable import Foundry

final class CalculatorProviderTests: XCTestCase {
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
        let suite = UserDefaults(suiteName: "foundry.tests.calculator-history")!
        suite.removePersistentDomain(forName: "foundry.tests.calculator-history")
        let store = CalculatorHistoryStore(defaults: suite)

        for i in 1...12 { store.record(expression: "\(i)+0", result: "\(i)") }
        store.record(expression: "10+0", result: "10")

        let entries = store.entries
        XCTAssertEqual(entries.count, 10)
        XCTAssertEqual(entries.first, .init(expression: "10+0", result: "10"))
        XCTAssertEqual(entries.map(\.result), ["10", "12", "11", "9", "8", "7", "6", "5", "4", "3"])
        suite.removePersistentDomain(forName: "foundry.tests.calculator-history")
    }
}
