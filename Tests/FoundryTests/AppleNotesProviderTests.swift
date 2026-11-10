import XCTest
import os
import FoundryServices
@testable import Foundry

final class AppleNotesProviderTests: XCTestCase {
    func testASlowNotesIsReportedAsSlowAndNotAskedAgainOnTheNextKeystroke() async {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let provider = AppleNotesProvider { _ in
            calls.withLock { $0 += 1 }
            return ProcessRunner.runSynchronously(path: "/bin/sleep", arguments: ["5"], timeout: 0.1)
        }

        let first = await provider.results(matching: "notes groceries")
        let second = await provider.results(matching: "notes grocerie")

        XCTAssertEqual(first.map(\.id), ["apple-note.failed"])
        XCTAssertEqual(second.map(\.id), ["apple-note.failed"])
        XCTAssertEqual(calls.withLock { $0 }, 1)
    }

    func testRefusedAutomationPointsAtPrivacySettings() async {
        let provider = AppleNotesProvider { _ in
            ProcessRunner.runSynchronously(path: "/bin/sh", arguments: ["-c", "echo 'execution error: Not authorized to send Apple events to Notes. (-1743)' >&2; exit 1"])
        }

        let results = await provider.results(matching: "notes groceries")

        XCTAssertEqual(results.map(\.id), ["apple-note.unavailable"])
    }

    func testNotesMatchOnTitleOrPreview() async {
        let json = #"[{"id":"x-coredata://1","title":"Groceries","preview":"milk eggs"},{"id":"x-coredata://2","title":"Trip","preview":"pack milk"}]"#
        let provider = AppleNotesProvider { _ in ProcessRunner.runSynchronously(path: "/usr/bin/printf", arguments: ["%s", json]) }

        let results = await provider.results(matching: "notes milk")

        XCTAssertEqual(results.map(\.title), ["Groceries", "Trip"])
    }
}
