import XCTest
@testable import Foundry

final class DeveloperToolsProviderTests: XCTestCase {
    func testStaticDeveloperCommandsOpenTheirToolUI() async {
        let commands = [
            (query: "base64", id: "dev.base64", tool: "base64"),
            (query: "format json", id: "dev.json", tool: "json"),
            (query: "change case", id: "dev.case", tool: "case"),
            (query: "unix timestamp", id: "dev.timestamp", tool: "timestamp"),
            (query: "word count", id: "dev.wordcount", tool: "wordCount")
        ]

        for command in commands {
            let results = await DeveloperToolsProvider().results(matching: command.query)
            let result = try? XCTUnwrap(results.first { $0.id == command.id })
            XCTAssertEqual(result?.primaryAction.kind, .openDeveloperTools(tool: command.tool))
        }
    }

    func testBase64EncodeDecodeRoundTrip() {
        let encoded = DeveloperToolsEngine.base64Encode("hello world")
        XCTAssertEqual(encoded, "aGVsbG8gd29ybGQ=")
        XCTAssertEqual(DeveloperToolsEngine.base64Decode(encoded ?? ""), "hello world")
    }

    func testFormatJSONPrettyPrintsAndSortsKeys() {
        let formatted = DeveloperToolsEngine.formatJSON("{\"b\":2,\"a\":1}")
        XCTAssertEqual(formatted, "{\n  \"a\" : 1,\n  \"b\" : 2\n}")
    }

    func testCaseVariantsCoverCommonStyles() {
        let variants = Dictionary(uniqueKeysWithValues: DeveloperToolsEngine.caseVariants(for: "hello world").map { ($0.style, $0.value) })
        XCTAssertEqual(variants["camelCase"], "helloWorld")
        XCTAssertEqual(variants["snake_case"], "hello_world")
        XCTAssertEqual(variants["CONSTANT_CASE"], "HELLO_WORLD")
    }

    func testTimestampConversionsFromUnixSeconds() {
        let conversions = Dictionary(uniqueKeysWithValues: DeveloperToolsEngine.timestampConversions(for: "1712345678").map { ($0.label, $0.value) })
        XCTAssertEqual(conversions["Unix seconds"], "1712345678")
        XCTAssertNotNil(conversions["ISO 8601"])
    }

    func testWordCountTracksWordsAndLines() {
        let stats = DeveloperToolsEngine.wordCount("hello world\nsecond line")
        XCTAssertEqual(stats.words, 4)
        XCTAssertEqual(stats.lines, 2)
        XCTAssertEqual(stats.paragraphs, 1)
    }

    func testBitwiseOperationsParseAndCompute() {
        if case let .and(lhs, rhs)? = DeveloperToolsEngine.bitwiseOperation(from: "and 5 3") {
            XCTAssertEqual(lhs & rhs, 1)
        } else {
            XCTFail("expected AND operation")
        }

        if case let .shiftLeft(lhs, rhs)? = DeveloperToolsEngine.bitwiseOperation(from: "shift left 2 4") {
            XCTAssertEqual(lhs << rhs, 32)
        } else {
            XCTFail("expected shift left operation")
        }
    }

    func testBaseConversionsHandlePrefixedInputs() {
        let hex = Dictionary(uniqueKeysWithValues: DeveloperToolsEngine.baseConversion(from: "0xff")?.map { ($0.label, $0.value) } ?? [])
        XCTAssertEqual(hex["Decimal"], "255")
        XCTAssertEqual(hex["Binary"], "11111111")

        let binary = Dictionary(uniqueKeysWithValues: DeveloperToolsEngine.baseConversion(from: "0b1010")?.map { ($0.label, $0.value) } ?? [])
        XCTAssertEqual(binary["Decimal"], "10")
        XCTAssertEqual(binary["Hex"], "A")
    }

    func testSearchHeuristicsDetectRawBitwiseAndBaseQueries() {
        XCTAssertTrue(DeveloperToolsEngine.looksLikeBitwiseExpression("5 & 3"))
        XCTAssertTrue(DeveloperToolsEngine.looksLikeBitwiseExpression("5 << 1"))
        XCTAssertTrue(DeveloperToolsEngine.looksLikeBitwiseExpression("not 5 8"))

        XCTAssertTrue(DeveloperToolsEngine.looksLikeRadixValue("0xff"))
        XCTAssertTrue(DeveloperToolsEngine.looksLikeRadixValue("0b1010"))
        XCTAssertTrue(DeveloperToolsEngine.looksLikeRadixValue("16 ff"))
    }
}
