import XCTest
import FoundryDomain
@testable import Foundry

final class QuicklinkTests: XCTestCase {
    private let context = SnippetRenderContext(now: Date(timeIntervalSince1970: 0), locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian), clipboard: "a&b")

    func testExpansionPercentEncodesArgumentsInURLs() {
        XCTAssertEqual(QuicklinkTemplate.expand("https://x.com/?q={argument}", argument: "swift & c++", context: context), "https://x.com/?q=swift%20%26%20c%2B%2B")
        XCTAssertEqual(QuicklinkTemplate.expand("https://x.com/?q={clipboard}", argument: "", context: context), "https://x.com/?q=a%26b")
    }

    func testSelectionPlaceholderExpandsAndEncodes() {
        var context = context
        context.selection = "pick me & go"
        XCTAssertEqual(QuicklinkTemplate.expand("https://x.com/?q={selection}", argument: "", context: context), "https://x.com/?q=pick%20me%20%26%20go")
        let rendered = SnippetRenderer.render("said: {selection}", context: context)
        XCTAssertEqual(rendered.text, "said: pick me & go")
    }

    func testRaycastArgumentFormsAreRecognised() {
        XCTAssertEqual(QuicklinkTemplate.expand("https://x.com/{argument name=\"term\"}", argument: "hi", context: context), "https://x.com/hi")
        XCTAssertEqual(QuicklinkTemplate.expand("https://x.com/{Query}", argument: "hi", context: context), "https://x.com/hi")
        XCTAssertFalse(Quicklink(name: "Home", link: "https://x.com").takesArgument)
    }

    func testNonURLTemplatesAreNotEncoded() {
        XCTAssertEqual(QuicklinkTemplate.expand("~/Notes/{argument}", argument: "a b", context: context), "~/Notes/a b")
    }

    func testRaycastImport() throws {
        let data = Data(#"[{"name":"Docs","link":"https://docs.dev/?q={Query}","openWith":"com.apple.Safari"}]"#.utf8)
        let imported = try QuicklinkTemplate.importRaycast(data)
        XCTAssertEqual(imported.map(\.name), ["Docs"])
        XCTAssertEqual(imported.first?.openWithBundleID, "com.apple.Safari")
        XCTAssertThrowsError(try QuicklinkTemplate.importRaycast(Data("{}".utf8)))
    }

    func testOpenWithRoutesToTheChosenApp() async throws {
        let store = QuicklinkStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("quicklinks-\(UUID().uuidString).json"))
        try store.save([Quicklink(name: "Docs", link: "https://docs.dev/?q={argument}", keyword: "d", openWithBundleID: "com.apple.Safari")])
        let context = self.context
        let provider = QuicklinkProvider(store: store, context: { context })

        let results = await provider.results(matching: "d closures")
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.primaryAction.kind, .openURLWithApp(url: "https://docs.dev/?q=closures", bundleID: "com.apple.Safari"))
    }

    func testFileSearchQuicklinkFillsTheFileQuery() async throws {
        let store = QuicklinkStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("quicklinks-\(UUID().uuidString).json"))
        let context = self.context
        let provider = QuicklinkProvider(store: store, context: { context })

        let results = await provider.results(matching: "sf invoice")
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.id, "quicklink.search-files")
        XCTAssertEqual(result.primaryAction.kind, .fillQuery("f invoice"))
    }

    func testFaviconOptOutSkipsTheRemoteIcon() async throws {
        let store = QuicklinkStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("quicklinks-\(UUID().uuidString).json"))
        try store.save([
            Quicklink(name: "Shown", link: "https://a.dev"),
            Quicklink(name: "Hidden", link: "https://b.dev", useFavicon: false)
        ])
        let context = self.context
        let provider = QuicklinkProvider(store: store, context: { context })

        let shownResults = await provider.results(matching: "shown")
        let shown = try XCTUnwrap(shownResults.first)
        let hiddenResults = await provider.results(matching: "hidden")
        let hidden = try XCTUnwrap(hiddenResults.first)
        XCTAssertNotNil(shown.icon.remoteIconURL)
        XCTAssertNil(hidden.icon.remoteIconURL)
    }

    func testProviderFillsQueryThenOpensExpandedLink() async throws {
        let store = QuicklinkStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("quicklinks-\(UUID().uuidString).json"))
        let context = self.context
        let provider = QuicklinkProvider(store: store, context: { context })

        let bareResults = await provider.results(matching: "search google")
        let bare = try XCTUnwrap(bareResults.first { $0.id == "quicklink.google" })
        XCTAssertEqual(bare.primaryAction.kind, .fillQuery("g "))

        let argumentResults = await provider.results(matching: "g swift actors")
        let withArgument = try XCTUnwrap(argumentResults.first)
        XCTAssertEqual(withArgument.primaryAction.kind, .openURL("https://www.google.com/search?q=swift%20actors"))
        XCTAssertEqual(withArgument.title, "Search Google for “swift actors”")
    }

    func testStoreSeedsDefaultsAndPersistsEdits() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quicklinks-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(QuicklinkStore(url: url).load().count, 6)
        try QuicklinkStore(url: url).save([Quicklink(name: "One", link: "https://one")])
        XCTAssertEqual(QuicklinkStore(url: url).load().map(\.name), ["One"])
    }

    func testFaviconURLUsesTheLinksOwnHost() {
        XCTAssertEqual(
            QuicklinkProvider.faviconURL(for: "https://www.google.com/search?q={argument}")?.absoluteString,
            "https://www.google.com/favicon.ico"
        )
        XCTAssertEqual(
            QuicklinkProvider.faviconURL(for: "https://x.com/{argument}/status")?.absoluteString,
            "https://x.com/favicon.ico"
        )
        XCTAssertNil(QuicklinkProvider.faviconURL(for: "maps://?q={argument}"))
        XCTAssertNil(QuicklinkProvider.faviconURL(for: "mailto:{argument}"))
    }
}
