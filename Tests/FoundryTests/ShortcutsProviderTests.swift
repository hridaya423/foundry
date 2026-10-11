import os
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

private final class LockedCounter: Sendable {
    private let count = OSAllocatedUnfairLock(initialState: 0)
    var value: Int { count.withLock { $0 } }
    @discardableResult func increment() -> Int { count.withLock { $0 += 1; return $0 } }
}
