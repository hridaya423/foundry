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

    func testSearchCoversEveryConfiguredFolderAndHonoursSkippedNames() async {
        let config = FileSearchConfig(folders: ["/Users/test/work", "/Volumes/Projects"], excludedFolders: ["build"])
        let provider = FileSearchProvider(settings: { config }) { _, scope in
            ["\(scope.path)/report.txt", "\(scope.path)/build/report.txt", "\(scope.path)/Library/report.txt"]
        }
        let paths = await provider.results(matching: "f report").compactMap { result -> String? in
            if case let .file(url) = result.payload { return url.path }
            return nil
        }
        XCTAssertEqual(Set(paths), ["/Users/test/work/report.txt", "/Users/test/work/Library/report.txt", "/Volumes/Projects/report.txt",
            "/Volumes/Projects/Library/report.txt"])
        let decoded = try? JSONDecoder().decode(FileSearchConfig.self, from: Data(#"{"folders":[]}"#.utf8))
        XCTAssertEqual(decoded, .default)
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
        XCTAssertEqual(results.map { $0.primaryAction.behavior as? FillQueryAction }, [FillQueryAction("f ")])
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
        XCTAssertEqual(first.primaryAction.behavior as? OpenURLAction, OpenURLAction("file:///Users/test/Documents/report-1.txt"))
        XCTAssertEqual(ResultSection.of(first), .files)
    }

    func testFileResultExposesFinderStyleActions() {
        let path = "/Users/test/Documents/report-1.txt"
        let result = FileSearchProvider.result(path)
        let behaviors = result.secondaryActions.map(\.behavior)

        XCTAssertTrue(behaviors.contains { $0 as? RevealFileAction == RevealFileAction(path: path) })
        XCTAssertTrue(behaviors.contains { $0 as? CopyFileAction == CopyFileAction(path: path) })
        XCTAssertTrue(behaviors.contains { $0 as? CopyToClipboardAction == CopyToClipboardAction(path) })
        XCTAssertTrue(behaviors.contains { $0 as? AddToFileShelfAction == AddToFileShelfAction(path: path) })
        XCTAssertTrue(behaviors.contains { $0 as? OpenFileConverterAction == OpenFileConverterAction(path: path) })
        XCTAssertTrue(behaviors.contains { $0 as? CompressFileAction == CompressFileAction(path: path) })
        XCTAssertTrue(behaviors.contains { $0 as? RenameFileAction == RenameFileAction(path: path) })
        XCTAssertTrue(behaviors.contains { $0 as? MoveToTrashAction == MoveToTrashAction(path: path) })
        XCTAssertTrue(result.secondaryActions.contains { $0.isDestructive })
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
        let registry = CommandRegistry(providers: providers, usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)

        let results = await registry.completeResults(matching: "zzqx plover", initialResults: [])
        XCTAssertEqual(results[0].primaryAction.behavior as? OpenQuickAIAction, OpenQuickAIAction(prompt: "zzqx plover"))
        XCTAssertEqual(results[1].primaryAction.behavior as? OpenURLAction, OpenURLAction("https://www.google.com/search?q=zzqx%20plover"))
        XCTAssertEqual(results[2].primaryAction.behavior as? FillQueryAction, FillQueryAction("f zzqx plover"))

        var preference = CommandPreference()
        preference.fallbackEligible = false
        try config.updateCommandPreference(preference, for: FileSearchProvider.commandID)
        let withoutFiles = await registry.completeResults(matching: "zzqx plover", initialResults: [])
        XCTAssertEqual(withoutFiles.count, 2)
    }

    func testFallbackOrderAndDefineFollowSettings() async throws {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json"))
        var fallbacks = FallbackConfig.default
        fallbacks.disabled = [.askAI]
        fallbacks.move(.define, by: -10)
        try config.updateFallbacks(fallbacks)
        let registry = CommandRegistry(providers: [FileSearchProvider(scope: home) { _, _ in [] }],
            usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)

        let results = await registry.completeResults(matching: "zzqxplover", initialResults: [])
        XCTAssertEqual(results.first?.primaryAction.behavior as? OpenURLAction, OpenURLAction("dict://zzqxplover"))
        XCTAssertEqual(results.dropFirst().first?.primaryAction.behavior as? FillQueryAction, FillQueryAction("f zzqxplover"))
        XCTAssertEqual(results.count, 2)
        XCTAssertNil(CommandRegistry.defineResult(for: "two words"))

        let decoded = try JSONDecoder().decode(FallbackConfig.self, from: Data(#"{"order":["define","bogus","define"]}"#.utf8))
        XCTAssertEqual(decoded.order, [.define, .suggestions, .askAI, .searchWeb, .searchFiles])
        XCTAssertEqual(decoded.disabled, FallbackConfig.default.disabled)
    }

    func testFileModeShowsOnlyFilesEvenWhenSpotlightIsSlowerThanTheDeferredBudget() async {
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json"))
        let files = FileSearchProvider(scope: home) { _, _ in
            try? await Task.sleep(for: .milliseconds(600))
            return ["/Users/test/Documents/report.txt"]
        }
        let registry = CommandRegistry(providers: [BuiltInCommandProvider(), files], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)

        let results = await registry.completeResults(matching: "f report", initialResults: [])
        XCTAssertEqual(results.map(\.title), ["report.txt"])

        let empty = FileSearchProvider(scope: home) { _, _ in [] }
        let emptyRegistry = CommandRegistry(providers: [BuiltInCommandProvider(), empty], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
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

    /// Spotlight index order is meaningless — name-match quality decides.
    func testRankScoresBasenameMatchQuality() async {
        let provider = FileSearchProvider(scope: home) { _, _ in
            [
                "/Users/test/code/displays/notes.txt",
                "/Users/test/Documents/Display Settings.pdf",
                "/Users/test/Downloads/old-display-photo.png",
            ]
        }
        let results = await provider.results(matching: "f display")
        // "Display Settings.pdf" (word-boundary prefix) beats the
        // mid-word/fuzzy "display-photo" and the non-matching "notes".
        XCTAssertEqual(results.map(\.title).first, "Display Settings.pdf")
    }

}
