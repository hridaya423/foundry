import XCTest
@testable import Foundry

final class ShortcutsProviderTests: XCTestCase {
    func testParseSkipsBlankLines() {
        XCTAssertEqual(ShortcutsProvider.parse("Morning Routine\n\n  Resize Image \n"), ["Morning Routine", "Resize Image"])
    }

    func testSearchUsesCacheAndRunsThroughTheCLI() async throws {
        let calls = LockedCounter()
        let provider = ShortcutsProvider { calls.increment(); return ["Morning Routine", "Resize Image"] }
        provider.refresh()

        let results = await provider.results(matching: "resize")
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.title, "Resize Image")
        XCTAssertEqual(result.primaryAction.kind, .runProcess(path: "/usr/bin/shortcuts", arguments: ["run", "Resize Image"]))
        _ = await provider.results(matching: "morning")
        XCTAssertEqual(calls.value, 1, "fresh cache must not re-run the CLI per keystroke")
    }

    func testStaleCacheRefreshesInBackgroundAndKeepsOldNamesOnFailure() async {
        let responses = LockedCounter()
        let provider = ShortcutsProvider(refreshInterval: 0) { responses.increment() == 1 ? ["One"] : nil }
        provider.refresh()
        XCTAssertEqual(provider.cachedNames(), ["One"])
        await waitUntil { responses.value >= 2 }
        XCTAssertEqual(provider.cachedNames(), ["One"])
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    @discardableResult func increment() -> Int { lock.withLock { count += 1; return count } }
}
