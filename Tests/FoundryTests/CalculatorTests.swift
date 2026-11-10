import os
import XCTest
@testable import Foundry
import FoundryDomain

final class CalculatorTests: XCTestCase {
    private let rateRequests = OSAllocatedUnfairLock(initialState: 0)
    private lazy var provider = CalculatorProvider(
        rateSource: { [rateRequests] _ in
            rateRequests.withLock { $0 += 1 }
            return [FrankfurterRate(quote: "EUR", rate: 0.5, date: "2026-11-09")]
        },
        rateCache: CurrencyRateCache()
    )

    private func titles(for query: String) async -> [String] {
        await provider.search(CommandSearchRequest(query: query)).map(\.title)
    }

    // MARK: - Arithmetic

    func testRespectsOperatorPrecedence() async {
        let first = await titles(for: "2+3*4")
        let second = await titles(for: "(2+3)*4")
        XCTAssertEqual(first, ["14"])
        XCTAssertEqual(second, ["20"])
    }

    func testImplicitMultiplicationAndConstants() async {
        let implicit = await titles(for: "2(3+4)")
        let pi = await titles(for: "2*pi")
        XCTAssertEqual(implicit, ["14"])
        XCTAssertTrue(pi.first?.hasPrefix("6.28") == true)
    }

    func testPercentPostfixAndModulo() async {
        let percent = await titles(for: "50%")
        let modulo = await titles(for: "10%3")
        XCTAssertEqual(percent, ["0.5"])
        XCTAssertEqual(modulo, ["1"])
    }

    func testPowerFactorialAndFunctions() async {
        let power = await titles(for: "2^10")
        let factorial = await titles(for: "5!")
        let sqrt = await titles(for: "sqrt(144)")
        let log = await titles(for: "log(100)")
        XCTAssertEqual(power, ["1024"])
        XCTAssertEqual(factorial, ["120"])
        XCTAssertEqual(sqrt, ["12"])
        XCTAssertEqual(log, ["2"])
    }

    func testExplicitPrefixesEvaluatePlainExpressions() async {
        let equals = await titles(for: "=7*6")
        let calc = await titles(for: "calc 7*6")
        XCTAssertEqual(equals, ["42"])
        XCTAssertEqual(calc, ["42"])
    }

    func testUnaryAndScientificNotation() async {
        let unary = await titles(for: "-3+5")
        let scientific = await titles(for: "1.5e3*2")
        XCTAssertEqual(unary, ["2"])
        XCTAssertEqual(scientific, ["3000"])
    }

    func testEquationSolving() async {
        let results = await provider.search(CommandSearchRequest(query: "x+3=7"))
        XCTAssertEqual(results.first?.title, "x = 4")
    }

    // MARK: - Unit conversion

    func testUnitConversionsProduceResults() async {
        let temperature = await titles(for: "100 f")
        let distance = await titles(for: "5 km")
        let mass = await titles(for: "1 kg")
        XCTAssertEqual(temperature, ["37.78 °C", "310.93 K"])
        XCTAssertEqual(distance, ["5000 m", "3.11 mi"])
        XCTAssertEqual(mass.first, "2.2 lb")
    }

    func testConversionToANamedUnit() async {
        let cases = [
            "5 km to miles": "3.11 mi", "72 f to c": "22.22 °C", "3 hours in minutes": "180 min", "1gb in mb": "1000 MB",
            "100 kg in lb": "220.46 lb", "1 cup to ml": "236.59 ml", "5 in to cm": "12.7 cm", "30 cm in in": "11.81 in",
            "-40 °F to °C": "-40 °C", "convert 2 miles to km": "3.22 km", "16 px to pt": "12 pt", "2 pt to ml": "946.35 ml",
            "30 mpg to l/100km": "7.84 L/100km", "90 minutes in hours": "1.5 hr", "1.5 Kilometers As Feet": "4921.26 ft"
        ]
        for (query, expected) in cases {
            let result = await titles(for: query)
            XCTAssertEqual(result, [expected], query)
        }
    }

    func testSeveralUnitsOfOneKindAddUp() async {
        let cases = [
            "5 ft 10 in to cm": "177.8 cm", "5'10 in cm": "177.8 cm", "5'10\" to m": "1.78 m", "6' in cm": "182.88 cm",
            "1 hr 30 min in minutes": "90 min", "2 lb 3 oz to g": "992.23 g", "1h 30m 15s in seconds": "5415 sec", "5ft 10in in in": "70 in"
        ]
        for (query, expected) in cases {
            let result = await titles(for: query)
            XCTAssertEqual(result, [expected], query)
        }
        let bare = await titles(for: "5 ft 10 in")
        XCTAssertEqual(bare, ["1.78 m", "70 in"])
        let mixed = await titles(for: "5 ft 10 kg to cm")
        XCTAssertEqual(mixed, [])
        let subtitle = await provider.search(CommandSearchRequest(query: "5'10 in cm")).first?.subtitle
        XCTAssertEqual(subtitle, "5 ft 10 in")
    }

    func testSmallConversionsKeepTheirDigits() async {
        let millimetres = await titles(for: "5 mm")
        let inch = await titles(for: "1 inch to ft")
        XCTAssertEqual(millimetres, ["0.5 cm", "0.197 in"])
        XCTAssertEqual(inch, ["0.0833 ft"])
    }

    func testUnitsOfDifferentKindsDoNotConvert() async {
        for query in ["5 km to kg", "3 hours in miles", "5 km to", "5 to km"] {
            let result = await titles(for: query)
            XCTAssertEqual(result, [], query)
        }
    }

    func testWordedArithmetic() async {
        let cases = ["15% of 200": "30", "10 mod 3": "1", "1,000 * 3": "3000", "12,500.5 + 1": "12501.5", "6 times 7": "42",
            "10 divided by 4": "2.5", "3 plus 4 minus 2": "5", "3 x 4": "12", "max(1,000)": "1"]
        for (query, expected) in cases {
            let result = await titles(for: query)
            XCTAssertEqual(result, [expected], query)
        }
    }

    // MARK: - Copy output

    func testPrimaryActionCopiesTheFormattedResult() async {
        let results = await provider.search(CommandSearchRequest(query: "2+2"))
        XCTAssertEqual(results.first?.primaryAction.behavior as? CopyToClipboardAction, CopyToClipboardAction("4"))
    }

    // MARK: - Quiet on invalid or non-math input

    func testMalformedInputReturnsNothing() async {
        for query in ["2+*3", "(3+2", "abc", "abc(", "hello world", ""] {
            let results = await provider.search(CommandSearchRequest(query: query))
            XCTAssertTrue(results.isEmpty, "expected no results for \(query)")
        }
    }

    func testNonFiniteAndZeroDivisionReturnNothing() async {
        for query in ["1/0", "0/0", "sqrt(-1)", "ln(0)"] {
            let results = await provider.search(CommandSearchRequest(query: query))
            XCTAssertTrue(results.isEmpty, "expected no results for \(query)")
        }
    }

    func testTwoToThe63DoesNotTrap() async {
        let titles = await titles(for: "2^63")
        XCTAssertEqual(titles.count, 1)
        XCTAssertFalse(titles.first?.isEmpty ?? true)
    }

    func testHugeUnitConversionDoesNotTrap() async {
        let titles = await titles(for: "99999999999999999999 km")
        XCTAssertFalse(titles.isEmpty)
    }

    func testCommaGroupsThousandsInUnitConversions() async {
        let thousands = await titles(for: "1,000 km")
        let millions = await titles(for: "1,234,567 m")
        let decimalComma = await titles(for: "1,5 km")
        XCTAssertEqual(thousands, ["1000000 m", "621.37 mi"])
        XCTAssertEqual(millions.first, "1234.57 km")
        XCTAssertEqual(decimalComma, ["1500 m", "0.932 mi"])
        XCTAssertEqual(rateRequests.withLock { $0 }, 0)
    }

    func testUnitsAreTriedBeforeCurrencyAndUnknownWordsNeverReachTheRateSource() async {
        let unknown = await titles(for: "5 abc")
        let unitFirst = await titles(for: "5 kg")
        XCTAssertTrue(unknown.isEmpty)
        XCTAssertEqual(unitFirst.first, "11.02 lb")
        XCTAssertEqual(rateRequests.withLock { $0 }, 0)
    }

    func testKnownCurrencyCodesStillFetchRates() async {
        let results = await titles(for: "2,000 usd to eur")
        XCTAssertEqual(results, ["€1000 Euro"])
        XCTAssertEqual(rateRequests.withLock { $0 }, 1)
    }

    func testUnaryMinusBindsLooserThanPower() async {
        let negativeSquare = await titles(for: "-2^2")
        let parenthesised = await titles(for: "(-2)^2")
        let negativeExponent = await titles(for: "2^-1")
        XCTAssertEqual(negativeSquare, ["-4"])
        XCTAssertEqual(parenthesised, ["4"])
        XCTAssertEqual(negativeExponent, ["0.5"])
    }

    func testPercentAfterPlusOrMinusIsRelativeToTheLeftOperand() async {
        let plus = await titles(for: "100 + 10%")
        let minus = await titles(for: "100 - 10%")
        let alone = await titles(for: "50%")
        let modulo = await titles(for: "10%3")
        XCTAssertEqual(plus, ["110"])
        XCTAssertEqual(minus, ["90"])
        XCTAssertEqual(alone, ["0.5"])
        XCTAssertEqual(modulo, ["1"])
    }
}
