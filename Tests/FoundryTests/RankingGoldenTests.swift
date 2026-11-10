import XCTest
@testable import Foundry
import FoundryDomain
import FoundryServices

/// The audit's golden set: ~30 query → top-3 expectations run through the
/// real coordinator pipeline. Deterministic providers only — apps come from
/// a temp root of fake bundles, and host-dependent providers (files,
/// scripts, shortcuts, browsers, notes) are excluded.
final class RankingGoldenTests: XCTestCase {
    private struct Case {
        let query: String
        /// Expected titles for the first N slots — top-3 where every slot is
        /// host-independent, fewer when a host-derived row (audio devices,
        /// running apps) can legitimately appear underneath.
        let top: [String]
    }

    private static let cases: [Case] = [
        Case(query: "als", top: ["Almost Maximize Window"]),
        Case(query: "saf", top: ["Safari"]),
        Case(query: "term", top: ["Terminal"]),
        Case(query: "sys", top: ["Open System Settings", "Open Console", "Open Software Update Settings"]),
        Case(query: "cl", top: ["Clipboard History", "Clear Clipboard", "Create Snippet from Clipboard"]),
        Case(query: "mail", top: ["Mail", "Open Internet Accounts Settings", "Random Data"]),
        Case(query: "calc", top: ["Calculator"]),
        Case(query: "12*34", top: ["408"]),
        Case(query: "emoji", top: ["Emoji & Symbols"]),
        Case(query: "qr", top: ["Read QR Code", "Wi-Fi QR Code", "Generate QR Code"]),
        Case(query: "wifi", top: ["Open Wi-Fi Settings", "Wi-Fi QR Code"]),
        Case(query: "snip", top: ["Snippets", "Import Snippets", "Open Screenshot"]),
        Case(query: "color", top: ["Pick Color", "Random Data"]),
        Case(query: "trash", top: ["Empty Trash"]),
        Case(query: "keep", top: ["Enable Keep Awake"]),
        Case(query: "audio", top: ["Open Sound Settings"]),
        Case(query: "left", top: ["Tile Window Left Half", "Tile Window Left Third", "Tile Window Left Two Thirds"]),
        Case(query: "max", top: ["Maximize Window", "Maximize Window Height", "Almost Maximize Window"]),
        Case(query: "center", top: ["Center Window", "Tile Window Center Two Thirds", "Tile Window Center Half"]),
        Case(query: "trans", top: ["Open Transfer or Reset Settings", "Convert File", "Translate"]),
        Case(query: "shelf", top: ["File Shelf"]),
        Case(query: "convert", top: ["Convert File", "Change Case", "Unix Timestamp"]),
        Case(query: "downloads", top: ["Downloads"]),
        Case(query: "dev", top: ["Developer Tools", "Open Profiles Settings", "Open Bluetooth Settings"]),
        Case(query: "ai", top: ["Ask AI", "Mail", "Paste Clipboard as Plain Text"]),
        Case(query: "capture", top: ["Capture Text from Screen", "Open Screenshot"]),
        Case(query: "confetti", top: ["Make Confetti"]),
        Case(query: "settings", top: ["Open System Settings", "Foundry Settings", "Open VPN Settings"]),
        Case(query: "notes", top: ["Notes"]),
        Case(query: "xcode", top: ["Xcode", "Read QR Code", "Wi-Fi QR Code"]),
    ]

    func testGoldenQueriesProduceExpectedTopResults() async throws {
        let registry = try makeRegistry()
        try await warm(registry)

        for goldenCase in Self.cases {
            let results = await registry.fullResults(matching: goldenCase.query)
            let top = results.prefix(goldenCase.top.count).map(\.title)
            XCTAssertEqual(
                Array(top),
                goldenCase.top,
                "query \"\(goldenCase.query)\" drifted — got \(top.joined(separator: " | "))"
            )
        }
    }

    func testAnAnswerRanksFirstAndOnlyFallbacksFollowIt() async throws {
        let registry = try makeRegistry()
        try await warm(registry)

        for query in ["2+2", "sqrt(16)", "10!", "1/3", "5 km"] {
            let results = await registry.fullResults(matching: query)
            XCTAssertEqual(results.first?.payload.isAnswer, true, "\(query): \(results.map(\.title))")
            let others = results.filter { $0.payload.isAnswer == false }
            XCTAssertFalse(others.isEmpty, "\(query) offers no fallback")
            XCTAssertEqual(others.filter { $0.payload.usesTheQuery == false }.map(\.title), [], query)
        }
        let time = await registry.fullResults(matching: "time in tokyo")
        XCTAssertEqual(time.first?.payload.isAnswer, true, "\(time.map(\.title))")
    }

    func testAFreshHomeLeadsWithTheMainTools() async throws {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("home-\(UUID()).json"))
        let registry = CommandRegistry(
            providers: [DeveloperToolsProvider(), SystemCommandProvider(), WindowManagementProvider(), BuiltInCommandProvider()],
            usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        let home = await registry.homeResults()
        XCTAssertEqual(home.map(\.title), ["Clipboard History", "Ask AI", "Snippets", "Emoji & Symbols", "File Shelf"])
    }

    func testComputedValuesLeadInTheOrderTheirToolGivesThem() async throws {
        let registry = try makeRegistry()
        try await warm(registry)

        let radix = await registry.fullResults(matching: "0xff")
        XCTAssertEqual(radix.prefix(4).map(\.title), ["255", "FF", "11111111", "377"])
        let encoded = await registry.fullResults(matching: "base64 hello")
        XCTAssertEqual(encoded.first?.title, "aGVsbG8=")
        let colour = await registry.fullResults(matching: "#ff0000")
        XCTAssertEqual(colour.prefix(2).map(\.title), ["rgb(255, 0, 0)", "hsl(0, 100%, 50%)"])
        let stamp = await registry.fullResults(matching: "1731258000")
        XCTAssertEqual(stamp.dropFirst().first?.title, "2024-11-10T17:00:00.000Z")
        let volume = await registry.fullResults(matching: "volume 50")
        XCTAssertEqual(volume.first?.title, "Set Volume to 50%")
    }

    /// Prints actual top-3 for every candidate query — run with
    /// FOUNDRY_GOLDEN_RECORD=1 when updating the table deliberately.
    func testRecordGoldenTable() async throws {
        guard ProcessInfo.processInfo.environment["FOUNDRY_GOLDEN_RECORD"] == "1" else {
            throw XCTSkip("set FOUNDRY_GOLDEN_RECORD=1 to print candidate top-3s")
        }
        let registry = try makeRegistry()
        try await warm(registry)
        for query in Self.candidates {
            let results = await registry.fullResults(matching: query)
            let top = results.prefix(8).map { "\($0.id)=\($0.title)" }
            print("GOLDEN\t\(query)\t\(top.joined(separator: " | "))")
        }
    }

    private static let candidates: [String] = [
        "als", "saf", "term", "sys", "cl", "mail", "calc", "12*34",
        "emoji", "qr", "wifi", "snip", "color", "trash", "keep",
        "audio", "left", "max", "center", "trans", "shelf", "convert",
        "downloads", "dev", "ai", "capture", "confetti", "settings",
        "notes", "xcode",
    ]

    private func warm(_ registry: CommandRegistry) async throws {
        for _ in 0..<100 {
            if await registry.fullResults(matching: "safari").first?.title == "Safari" { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("the app index never loaded")
    }

    private func makeRegistry() throws -> CommandRegistry {
        let diagnostics = DiagnosticsService()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("golden-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let config = ConfigService(diagnostics: diagnostics, url: tmp.appendingPathComponent("config.json"))
        let appRoot = tmp.appendingPathComponent("Apps", isDirectory: true)
        for name in ["Safari", "Terminal", "Mail", "Notes", "Xcode", "Calendar",
                     "Music", "Photos", "Slack", "Preview", "TextEdit", "Maps",
                     "Calculator"] {
            try writeApp(named: name, to: appRoot)
        }

        let usage = UsageRankingStore.scratch(diagnostics)
        usage.recordExecution(resultID: "foundry.clipboard-history", query: "cl")

        return CommandRegistry(
            providers: [
                AppSearchProvider(diagnostics: diagnostics, roots: [appRoot]),
                CalculatorProvider(),
                TimeConversionProvider(),
                DeveloperToolsProvider(),
                MacUtilitiesProvider(processSnapshotProvider: EmptyProcessSnapshotProvider()),
                TranslationProvider(),
                AIProvider(config: config, diagnostics: diagnostics),
                LibraryProvider(store: FileSnippetStore(url: tmp.appendingPathComponent("snippets.json"))),
                QuicklinkProvider(store: QuicklinkStore(url: tmp.appendingPathComponent("quicklinks.json"))),
                MediaDownloadProvider(),
                SystemCommandProvider(),
                WindowManagementProvider(),
                BuiltInCommandProvider(),
            ],
            usageRanking: usage,
            diagnostics: diagnostics,
            configService: config
        )
    }

    private func writeApp(named name: String, to root: URL) throws {
        let bundle = root.appendingPathComponent("\(name).app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleDisplayName": name,
            "CFBundleIdentifier": "local.foundry.golden.\(name.lowercased().replacingOccurrences(of: " ", with: "-"))",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: bundle.appendingPathComponent("Info.plist"))
    }
}

private struct EmptyProcessSnapshotProvider: ProcessSnapshotProviding {
    func capture() -> [ProcessInfoRow] { [] }
}
