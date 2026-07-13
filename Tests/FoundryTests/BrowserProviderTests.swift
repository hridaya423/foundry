import Foundation
import XCTest
@testable import Foundry

final class BrowserProviderTests: XCTestCase {
    func testChromeBookmarkParserWalksNestedFolders() {
        let object: [String: Any] = [
            "bookmark_bar": [
                "type": "folder",
                "children": [
                    ["type": "url", "name": "Foundry", "url": "https://example.com/foundry"],
                    ["type": "folder", "children": [["type": "url", "name": "Docs", "url": "https://example.com/docs"]]]
                ]
            ]
        ]

        let bookmarks = ChromeBookmarkParser.parse(object)
        XCTAssertEqual(bookmarks.map(\.title), ["Foundry", "Docs"])
        XCTAssertEqual(bookmarks.map(\.url), ["https://example.com/foundry", "https://example.com/docs"])
    }

    func testSafariBookmarkParserWalksNestedChildren() {
        let object = NSDictionary(dictionary: [
            "WebBookmarkType": "WebBookmarkTypeList",
            "Children": [
                NSDictionary(dictionary: [
                    "WebBookmarkType": "WebBookmarkTypeLeaf",
                    "URLString": "https://example.com/safari",
                    "URIDictionary": ["title": "Safari bookmark"]
                ])
            ]
        ])

        let bookmarks = SafariBookmarkParser.parse(object)
        XCTAssertEqual(bookmarks.count, 1)
        XCTAssertEqual(bookmarks.first?.title, "Safari bookmark")
        XCTAssertEqual(bookmarks.first?.url, "https://example.com/safari")
    }

    func testFirefoxSessionParserReadsSelectedEntryFromEachWindow() throws {
        let object: [String: Any] = [
            "windows": [
                ["tabs": [[
                    "index": 2,
                    "entries": [
                        ["title": "Old", "url": "https://example.com/old"],
                        ["title": "Current", "url": "https://example.com/current"]
                    ]
                ]]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: object)

        let session = try XCTUnwrap(FirefoxSessionParser.parse(data))
        XCTAssertEqual(session.tabs.map(\.title), ["Current"])
        XCTAssertEqual(session.tabs.map(\.url), ["https://example.com/current"])
    }

    func testFirefoxSessionParserReadsMozillaLZ4LiteralBlock() throws {
        let json = #"{"windows":[{"tabs":[{"index":1,"entries":[{"title":"Current","url":"https://example.com/current"}]}]}]}"#.data(using: .utf8)!
        let literalLength = json.count
        var compressed = Data([0xf0, UInt8(literalLength - 15)])
        compressed.append(json)
        var encoded = Data([0x6d, 0x6f, 0x7a, 0x4c, 0x7a, 0x34, 0x30, 0x00])
        encoded.append(contentsOf: withUnsafeBytes(of: UInt32(literalLength).littleEndian, Array.init))
        encoded.append(compressed)

        let session = try XCTUnwrap(FirefoxSessionParser.parse(encoded))
        XCTAssertEqual(session.tabs.first?.url, "https://example.com/current")
    }

    func testProviderHasBrowserLaunchDefaults() async {
        let results = await BrowserProvider(homeDirectory: temporaryHome()).defaultResults()
        XCTAssertEqual(results.count, BrowserSource.allCases.count)
        XCTAssertEqual(results.map(\.id), BrowserSource.allCases.map { "foundry.browser.\($0.rawValue)" })
    }

    func testBrowserCatalogIncludesMajorBrowserFamilies() {
        XCTAssertTrue(BrowserSource.allCases.contains(.firefox))
        XCTAssertTrue(BrowserSource.allCases.contains(.arc))
        XCTAssertTrue(BrowserSource.allCases.contains(.dia))
        XCTAssertTrue(BrowserSource.allCases.contains(.helium))
        XCTAssertTrue(BrowserSource.allCases.contains(.brave))
        XCTAssertTrue(BrowserSource.allCases.contains(.edge))
    }

    func testBrowserCategoryQueriesCanListAllItems() {
        let request = BrowserSearchRequest(query: "helium tabs")
        XCTAssertEqual(request.browser, .helium)
        XCTAssertEqual(request.kind, .tab)
        XCTAssertTrue(request.search.isEmpty)
    }

    func testBrowserProviderOnlyActivatesForExplicitBrowserIntent() {
        XCTAssertFalse(BrowserSearchRequest(query: "calculator").isBrowserIntent)
        XCTAssertTrue(BrowserSearchRequest(query: "helium tabs").isBrowserIntent)
        XCTAssertTrue(BrowserSearchRequest(query: "history github").isBrowserIntent)
    }

    func testFirefoxNativeMessagePayloadDecodesIntoLiveTabs() throws {
        let data = #"{"tabs":[{"title":"Firefox tab","url":"https://example.com"}]}"#.data(using: .utf8)!
        let payload = try JSONDecoder().decode(FirefoxLiveTabs.self, from: data)
        XCTAssertEqual(payload.tabs.count, 1)
        XCTAssertEqual(payload.tabs.first?.title, "Firefox tab")
        XCTAssertEqual(payload.tabs.first?.url, "https://example.com")
    }

    func testProviderReturnsNoResultsWhenBrowserDataIsUnavailable() async {
        let results = await BrowserProvider(homeDirectory: temporaryHome()).results(matching: "history example")
        XCTAssertTrue(results.isEmpty)
    }

    private func temporaryHome() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("foundry-browser-tests-\(UUID().uuidString)")
    }
}
