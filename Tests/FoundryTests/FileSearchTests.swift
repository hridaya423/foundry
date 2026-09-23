import os
import XCTest
import FoundryDomain
import FoundryServices
@testable import Foundry

final class FileSearchTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/test")

    func testFilterEnforcesScopeAndIgnoreRules() {
        let paths = [
            "/Users/test/Documents/Report.pdf",
            "/Users/test/Library/Caches/Report.pdf",
            "/Users/test/code/app/node_modules/report/index.js",
            "/Users/test/code/app/.git/report",
            "/Users/test/.hidden/report.txt",
            "/Users/tester/report.txt",
            "/Volumes/Other/report.txt"
        ]
        XCTAssertEqual(FileSearchProvider.filter(paths, scope: home), ["/Users/test/Documents/Report.pdf"])
    }

    func testPrefixGatesFileModeAndStripsSpotlightMetacharacters() {
        let provider = FileSearchProvider(scope: home) { _, _ in [] }
        XCTAssertFalse(provider.isActive(for: "report"))
        XCTAssertFalse(provider.isActive(for: "firefox"))
        XCTAssertTrue(provider.isActive(for: "f report"))
        XCTAssertTrue(provider.isActive(for: "search fi"))
        XCTAssertEqual(FileSearchProvider.fileQuery("F  it's*\"x\" "), "itsx")
        XCTAssertNil(FileSearchProvider.fileQuery("finder"))
    }

    func testSearchFilesCommandFillsThePrefix() async {
        let provider = FileSearchProvider(scope: home) { _, _ in [] }
        let results = await provider.results(matching: "search fi")
        XCTAssertEqual(results.map(\.primaryAction.kind), [.fillQuery("f ")])
    }

    func testResultsOpenTheFileAndSitInTheFilesSection() async throws {
        let paths = (1...20).map { "/Users/test/Documents/report-\($0).txt" }
        let provider = FileSearchProvider(scope: home) { predicate, _ in
            XCTAssertEqual(predicate, "kMDItemFSName == '*report*'cd")
            return paths
        }
        let results = await provider.results(matching: "f report")
        XCTAssertEqual(results.count, FileSearchProvider.resultLimit)
        let first = try XCTUnwrap(results.first)
        XCTAssertEqual(first.title, "report-1.txt")
        XCTAssertEqual(first.primaryAction.kind, .openURL("file:///Users/test/Documents/report-1.txt"))
        XCTAssertEqual(ResultSection.of(first), .files)
    }

    func testCancelledSearchPublishesNothing() async {
        let provider = FileSearchProvider(scope: home) { _, _ in
            try? await Task.sleep(for: .milliseconds(200))
            return ["/Users/test/Documents/report.txt"]
        }
        let task = Task { await provider.results(matching: "f report") }
        task.cancel()
        let results = await task.value
        XCTAssertTrue(results.isEmpty)
    }

    func testNoMatchShowsAskAIThenGoogleThenFilesAndRespectsFallbackToggles() async throws {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json"))
        let links = QuicklinkStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("links-\(UUID()).json"))
        let providers: [CommandProvider] = [FileSearchProvider(scope: home) { _, _ in [] }, QuicklinkProvider(store: links)]
        let registry = CommandRegistry(providers: providers, usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)

        let results = await registry.completeResults(matching: "zzqx plover", initialResults: [])
        XCTAssertEqual(results.map(\.primaryAction.kind), [
            .openQuickAI(prompt: "zzqx plover"),
            .openURL("https://www.google.com/search?q=zzqx%20plover"),
            .fillQuery("f zzqx plover")
        ])

        var preference = CommandPreference()
        preference.fallbackEligible = false
        try config.updateCommandPreference(preference, for: FileSearchProvider.commandID)
        let withoutFiles = await registry.completeResults(matching: "zzqx plover", initialResults: [])
        XCTAssertEqual(withoutFiles.count, 2)
    }

    func testFileModeShowsOnlyFilesEvenWhenSpotlightIsSlowerThanTheDeferredBudget() async {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json"))
        let files = FileSearchProvider(scope: home) { _, _ in
            try? await Task.sleep(for: .milliseconds(600))
            return ["/Users/test/Documents/report.txt"]
        }
        let registry = CommandRegistry(providers: [BuiltInCommandProvider(), files], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)

        let results = await registry.completeResults(matching: "f report", initialResults: [])
        XCTAssertEqual(results.map(\.title), ["report.txt"])

        let empty = FileSearchProvider(scope: home) { _, _ in [] }
        let emptyRegistry = CommandRegistry(providers: [BuiltInCommandProvider(), empty], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        let noFallbacks = await emptyRegistry.completeResults(matching: "f nothing", initialResults: [])
        XCTAssertTrue(noFallbacks.isEmpty)
    }
    func testKindTokensBecomeContentTypePredicates() async {
        let seen = OSAllocatedUnfairLock(initialState: "")
        let provider = FileSearchProvider(scope: home) { predicate, _ in
            seen.withLock { $0 = predicate }
            return ["/Users/test/Documents/report.pdf"]
        }
        let results = await provider.results(matching: "f report kind:pdf")
        XCTAssertTrue(seen.withLock { $0 }.contains("kMDItemFSName == '*report*'cd"))
        XCTAssertTrue(seen.withLock { $0 }.contains("kMDItemContentType == 'com.adobe.pdf'"))
        XCTAssertEqual(results.count, 1)

        let parsed = FileSearchProvider.parse("notes kind:xyz kind:image")
        XCTAssertEqual(parsed.term, "notes")
        XCTAssertEqual(parsed.kinds, ["image"])
    }

    func testBarePrefixListsRecentsByModificationDate() async {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let older = dir.appendingPathComponent("older.txt")
        let newer = dir.appendingPathComponent("newer.txt")
        fm.createFile(atPath: older.path, contents: Data())
        fm.createFile(atPath: newer.path, contents: Data())
        try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: older.path)
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: newer.path)

        let seen = OSAllocatedUnfairLock(initialState: "")
        let provider = FileSearchProvider(scope: dir) { predicate, _ in
            seen.withLock { $0 = predicate }
            return [older.path, newer.path]
        }
        let results = await provider.results(matching: "f ")
        XCTAssertTrue(seen.withLock { $0 }.contains("kMDItemContentChangeDate >= $time.this_week"))
        XCTAssertEqual(results.map(\.title), ["newer.txt", "older.txt"])
    }

    func testCameraCommandIsHiddenByDefaultUntilEnabled() async throws {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json"))
        let registry = CommandRegistry(providers: [CameraCommandProvider()], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)

        let hidden = await registry.completeResults(matching: "camera", initialResults: [])
        XCTAssertFalse(hidden.contains { $0.id == "foundry.camera" })

        var preference = CommandPreference()
        preference.isEnabled = true
        try config.updateCommandPreference(preference, for: "foundry.camera")
        let shown = await registry.completeResults(matching: "camera", initialResults: [])
        XCTAssertTrue(shown.contains { $0.id == "foundry.camera" })
    }

}
