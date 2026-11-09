import XCTest
@testable import Foundry
import FoundryDomain

final class CalculatorTests: XCTestCase {
    private let provider = CalculatorProvider()

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
        XCTAssertEqual(temperature, ["37.8 celsius", "310.9 kelvin"])
        XCTAssertEqual(distance, ["5000 m", "3.1 mi"])
        XCTAssertEqual(mass.first, "2.2 lb")
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
        let titles = await titles(for: "99999999999999999999 km to m")
        XCTAssertNotNil(titles)
    }
}
