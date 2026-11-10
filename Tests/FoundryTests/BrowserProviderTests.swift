import Foundation
import XCTest
import FoundryServices
@testable import Foundry

final class BrowserProviderTests: XCTestCase {
    func testRecordLoadsForDifferentCacheKeysDoNotBlockEachOther() {
        let gate = BrowserRecordsLoadGate()
        let firstEntered = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let secondEntered = DispatchSemaphore(value: 0)
        let firstKey = BrowserRecordsCache.Key(source: .firefox, kind: .history)
        let secondKey = BrowserRecordsCache.Key(source: .safari, kind: .bookmark)

        DispatchQueue.global().async {
            gate.withLock(for: firstKey) {
                firstEntered.signal()
                releaseFirst.wait()
            }
        }
        XCTAssertEqual(firstEntered.wait(timeout: .now() + 1), .success)

        DispatchQueue.global().async {
            _ = gate.withLock(for: secondKey) { secondEntered.signal() }
        }
        XCTAssertEqual(secondEntered.wait(timeout: .now() + 1), .success)
        releaseFirst.signal()
    }

    func testFirefoxSessionDecoderRejectsUnreasonableOutputSizeBeforeAllocation() {
        XCTAssertFalse(FirefoxSessionParser.isAllowedDecodedSize(64 * 1024 * 1024))
        XCTAssertTrue(FirefoxSessionParser.isAllowedDecodedSize(8 * 1024 * 1024))
    }

    func testFirefoxSessionDecoderRejectsMatchExpansionBeyondDeclaredSize() {
        var encoded = Data([0x6d, 0x6f, 0x7a, 0x4c, 0x7a, 0x34, 0x30, 0x00])
        encoded.append(contentsOf: withUnsafeBytes(of: UInt32(1).littleEndian, Array.init))
        encoded.append(contentsOf: [0x10, 0x78, 0x01, 0x00])

        XCTAssertNil(FirefoxSessionParser.parse(encoded))
    }

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

    func testBrowserLaunchDefaultsOnlyIncludeInstalledBrowsers() async {
        let results = await BrowserProvider(homeDirectory: temporaryHome()).defaultResults()
        XCTAssertTrue(results.contains { $0.id == "foundry.browser.safari" })
        XCTAssertEqual(results.count, BrowserSource.allCases.filter(\.isInstalled).count)
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

    func testOneTabWithANullURLDoesNotDropTheOthers() throws {
        let data = Data(#"{"tabs":[{"title":"Kept","url":"https://example.com"},{"title":null,"url":null}]}"#.utf8)
        let payload = try JSONDecoder().decode(FirefoxLiveTabs.self, from: data)
        XCTAssertEqual(payload.tabs.map(\.title), ["Kept", ""])
    }

    func testHistoryKeepsPagesBeyondTheLastHundredVisitsAndNullTitlesFallBackToTheURL() async throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let profile = home.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let visits = (1...150).map { "INSERT INTO visits (url, visit_time) VALUES (1, \(1_000 + $0));" }.joined()
        let script = "CREATE TABLE urls (id INTEGER PRIMARY KEY, title TEXT, url TEXT); CREATE TABLE visits (id INTEGER PRIMARY KEY, url INTEGER, visit_time INTEGER);"
            + "INSERT INTO urls VALUES (1, 'Busy page', 'https://busy.example'), (2, NULL, 'https://zebra.example');"
            + "INSERT INTO visits (url, visit_time) VALUES (2, 10);" + visits
        let created = ProcessRunner.runSynchronously(path: "/usr/bin/sqlite3", arguments: [profile.appendingPathComponent("History").path, script], timeout: 10)
        XCTAssertEqual(created?.succeeded, true)

        let results = await BrowserProvider(homeDirectory: home).results(matching: "history zebra")

        XCTAssertEqual(results.map(\.title), ["https://zebra.example"])
    }

    func testFirefoxShowsTabsFromTheCurrentSessionOnlyNotOlderBackups() async throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let backups = home.appendingPathComponent("Library/Application Support/Firefox/Profiles/abc.default/sessionstore-backups")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let session = { (title: String) in
            Data(#"{"windows":[{"tabs":[{"index":1,"entries":[{"url":"https://example.com/\#(title)","title":"\#(title)"}]}]}]}"#.utf8)
        }
        try session("Current").write(to: backups.appendingPathComponent("recovery.js"))
        try session("Closed").write(to: backups.appendingPathComponent("previous.js"))

        let results = await BrowserProvider(homeDirectory: home, liveTabsCacheLifetime: 0).results(matching: "firefox tabs")

        XCTAssertEqual(results.filter { $0.title == "Current" || $0.title == "Closed" }.map(\.title), ["Current"])
    }

    func testProviderReturnsNoResultsWhenBrowserDataIsUnavailable() async {
        let results = await BrowserProvider(homeDirectory: temporaryHome()).results(matching: "history example")
        XCTAssertTrue(results.isEmpty)
    }

    func testLiveTabsAreNotHeldByTheDurableRecordsCache() async throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let tabsURL = FirefoxNativeTabsStore.url(home: home)
        try FileManager.default.createDirectory(at: tabsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"tabs":[{"title":"First tab","url":"https://example.com/first"}]}"#.utf8).write(to: tabsURL)
        let provider = BrowserProvider(homeDirectory: home, liveTabsCacheLifetime: 0)

        let first = await provider.results(matching: "firefox tabs")
        XCTAssertEqual(first.first?.title, "First tab")

        try Data(#"{"tabs":[{"title":"Second tab","url":"https://example.com/second"}]}"#.utf8).write(to: tabsURL)

        let refreshed = await provider.results(matching: "firefox tabs")
        XCTAssertEqual(refreshed.first?.title, "Second tab")
    }

    private func temporaryHome() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("foundry-browser-tests-\(UUID().uuidString)")
    }
}

final class FirefoxNativeHostLaunchTests: XCTestCase {
    func testFirefoxsOwnLaunchArgumentsStartTheHost() {
        let firefoxLaunch = ["/Applications/Foundry.app/Contents/MacOS/Foundry",
            "/Users/me/Library/Application Support/Mozilla/NativeMessagingHosts/com.hridya.foundry.json", "firefox-connector@foundry.local"]
        XCTAssertTrue(FirefoxNativeHost.isLaunch(firefoxLaunch))
        XCTAssertFalse(FirefoxNativeHost.isLaunch(["/Applications/Foundry.app/Contents/MacOS/Foundry"]))
    }
}
