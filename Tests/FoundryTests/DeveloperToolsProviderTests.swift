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
            XCTAssertEqual(result?.primaryAction.behavior as? OpenDeveloperToolsAction, OpenDeveloperToolsAction(tool: command.tool))
        }
    }

    func testBase64EncodeDecodeRoundTrip() {
        let encoded = DeveloperToolsEngine.base64Encode("hello world")
        XCTAssertEqual(encoded, "aGVsbG8gd29ybGQ=")
        XCTAssertEqual(DeveloperToolsEngine.base64Decode(encoded ?? ""), "hello world")
    }

    @MainActor
    func testBase64ToolPreservesWhitespaceWhenEncoding() {
        let state = DeveloperToolsState()
        state.base64Input = " a\n"

        XCTAssertEqual(state.base64Output, "IGEK")
        state.base64Operation = .decode
        state.base64Input = "IGEK"
        XCTAssertEqual(state.base64Output, " a\n")
    }

    @MainActor
    func testTimestampToolExplainsInvalidInput() {
        let state = DeveloperToolsState()
        state.timestampInput = "not a timestamp"

        XCTAssertTrue(state.timestampRows.isEmpty)
        XCTAssertNotNil(state.timestampError)
    }

    @MainActor
    func testInvalidJSONSaysWhereParsingFailedAndShowsAnExample() throws {
        let state = DeveloperToolsState()
        state.jsonInput = "{\"a\": tru}"
        let error = try XCTUnwrap(state.jsonError)
        XCTAssertTrue(error.contains("column"), error)
        XCTAssertTrue(error.contains("Example:"), error)
        XCTAssertNil(DeveloperToolsState.jsonProblem(in: "[1, 2]"))
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
        XCTAssertFalse(DeveloperToolsEngine.looksLikeRadixValue("16 ff"))
    }

    private func values(for query: String) async -> [String: String] {
        let results = await DeveloperToolsProvider().results(matching: query)
        return Dictionary(results.compactMap { result in
            if case let .value(label) = result.payload { return (label, result.title) }
            return nil
        }, uniquingKeysWith: { first, _ in first })
    }

    func testANumberWithAUnitIsNotABaseConversion() async {
        for query in ["25 c to f", "20 f", "36 hello"] {
            let results = await values(for: query)
            XCTAssertEqual(results, [:], query)
        }
        let explicit = await values(for: "base 16 ff")
        XCTAssertEqual(explicit["Decimal"], "255")
    }

    func testANumberConvertsToANamedBase() async {
        let hex = await values(for: "255 to hex")
        let binary = await values(for: "10 in binary")
        let decimal = await values(for: "0xff to decimal")
        XCTAssertEqual(hex, ["Hex": "FF"])
        XCTAssertEqual(binary, ["Binary": "1010"])
        XCTAssertEqual(decimal, ["Decimal": "255"])
    }

    func testHashesOfText() async {
        let md5 = await values(for: "md5 hello")
        let sha1 = await values(for: "sha1 hello")
        let sha256 = await values(for: "sha256 abc")
        let bare = await values(for: "md5")
        XCTAssertEqual(md5, ["MD5": "5d41402abc4b2a76b9719d911017c592"])
        XCTAssertEqual(sha1, ["SHA-1": "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d"])
        XCTAssertEqual(sha256, ["SHA-256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"])
        XCTAssertEqual(bare, [:])
    }

    func testURLEncodingAndDecoding() async {
        let encoded = await values(for: "url encode hello world&x=1")
        let decoded = await values(for: "url decode hello%20world%26x%3D1")
        XCTAssertEqual(encoded, ["URL encoded": "hello%20world%26x%3D1"])
        XCTAssertEqual(decoded, ["URL decoded": "hello world&x=1"])
    }

    func testABareUnixTimestampConverts() async {
        let seconds = await values(for: "1731258000")
        let milliseconds = await values(for: "1731258000000")
        let ordinary = await values(for: "12345")
        XCTAssertEqual(seconds["ISO 8601"], "2024-11-10T17:00:00.000Z")
        XCTAssertEqual(milliseconds["ISO 8601"], "2024-11-10T17:00:00.000Z")
        XCTAssertEqual(ordinary, [:])
    }

    func testColoursConvertBetweenNotations() async {
        let red = await values(for: "#ff0000")
        let short = await values(for: "#0af")
        let rgb = await values(for: "rgb(0, 170, 255)")
        let word = await values(for: "facade")
        XCTAssertEqual(red, ["RGB": "rgb(255, 0, 0)", "HSL": "hsl(0, 100%, 50%)"])
        XCTAssertEqual(short, ["RGB": "rgb(0, 170, 255)", "HSL": "hsl(200, 100%, 50%)"])
        XCTAssertEqual(rgb, ["Hex": "#00AAFF", "HSL": "hsl(200, 100%, 50%)"])
        XCTAssertEqual(word, [:])
    }

    func testGeneratedValuesNameWhatTheyAre() async {
        let base64 = await values(for: "base64 hello")
        let radix = await values(for: "0xff")
        XCTAssertEqual(base64["Encoded"], "aGVsbG8=")
        XCTAssertEqual(radix, ["Binary": "11111111", "Octal": "377", "Decimal": "255", "Hex": "FF"])
    }

    func testHugeTimestampDoesNotTrap() {
        let rows = DeveloperToolsEngine.timestampConversions(for: "9999999999999999999")
        XCTAssertNotNil(rows)
    }

    func testNotWithOversizedWidthClampsTo64() {
        guard case let .not(value, width) = DeveloperToolsEngine.bitwiseOperation(from: "not 5 18446744073709551615") else {
            return XCTFail("expected a not operation")
        }
        XCTAssertEqual(value, 5)
        XCTAssertEqual(width, 64)
    }

    func testShiftQueriesShowTheComputedValue() async {
        let left = await DeveloperToolsProvider().results(matching: "2 << 4")
        let right = await DeveloperToolsProvider().results(matching: "256 >> 4")
        XCTAssertTrue(left.contains { $0.title == "32" })
        XCTAssertTrue(right.contains { $0.title == "16" })
    }

    func testGenerateUUIDCopiesADifferentValueEachSearch() async throws {
        let provider = DeveloperToolsProvider()
        let first = await provider.results(matching: "uuid")
        let second = await provider.results(matching: "uuid")
        let firstAction = try XCTUnwrap(first.first { $0.id == "dev.uuid" }?.primaryAction.behavior as? CopyToClipboardAction)
        let secondAction = try XCTUnwrap(second.first { $0.id == "dev.uuid" }?.primaryAction.behavior as? CopyToClipboardAction)
        XCTAssertNotEqual(firstAction, secondAction)
    }

    func testBitwiseAcceptsHexOperands() {
        guard case let .and(lhs, rhs)? = DeveloperToolsEngine.bitwiseOperation(from: "0xFF & 0x0F") else {
            return XCTFail("expected AND operation")
        }
        XCTAssertEqual(lhs, 255)
        XCTAssertEqual(rhs, 15)
    }

    func testCommaGroupedTimestampFollowsTheSameMagnitudeRuleAsPlainDigits() {
        let seconds = DeveloperToolsEngine.timestampConversions(for: "1,700,000,000")
        let plain = DeveloperToolsEngine.timestampConversions(for: "1700000000")
        XCTAssertEqual(seconds.first { $0.label == "Unix seconds" }?.value, "1700000000")
        XCTAssertEqual(seconds.map(\.value), plain.map(\.value))
        let milliseconds = DeveloperToolsEngine.timestampConversions(for: "1,700,000,000,000")
        XCTAssertEqual(milliseconds.first { $0.label == "Unix seconds" }?.value, "1700000000")
    }

    func testTimestampAcceptsISO8601WithZoneAndOffset() {
        for input in ["2023-11-14T22:13:20Z", "2023-11-14T22:13:20.000Z", "2023-11-15T03:43:20+05:30"] {
            let rows = DeveloperToolsEngine.timestampConversions(for: input)
            XCTAssertEqual(rows.first { $0.label == "Unix seconds" }?.value, "1700000000", input)
        }
    }

    func testBase64DecodeAcceptsURLSafeAndUnpaddedInput() {
        XCTAssertEqual(DeveloperToolsEngine.base64Decode("aGk"), "hi")
        XCTAssertEqual(DeveloperToolsEngine.base64Decode("aGk="), "hi")
        XCTAssertEqual(DeveloperToolsEngine.base64Decode("Pz8-"), "??>")
        XCTAssertEqual(DeveloperToolsEngine.base64Decode("Pz8_"), "???")
    }
}
