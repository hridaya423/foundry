import XCTest
@testable import Foundry
import FoundryDomain

final class AppleNotesProviderTests: XCTestCase {
    func testFailedLookupReportsUnavailableInsteadOfEmptyLibrary() async {
        let provider = AppleNotesProvider(lookup: { _ in .failed })
        let results = await provider.search(CommandSearchRequest(query: "notes anything"))

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "apple-note.unavailable")
        XCTAssertTrue(results[0].subtitle?.contains("Automation") == true)
        XCTAssertFalse(results[0].secondaryActions.isEmpty)
    }

    func testSuccessfulLookupMapsNotesToOpenableResults() async {
        let provider = AppleNotesProvider(lookup: { _ in
            .results([AppleNoteResult(id: "x-coredata://note/1", title: "Shopping", preview: "milk, eggs")])
        })
        let results = await provider.search(CommandSearchRequest(query: "notes shop"))

        XCTAssertEqual(results.first?.title, "Shopping")
        XCTAssertEqual(results.first?.route, .notesSearch)
        if case .runProcess = results.first?.primaryAction.kind {} else {
            XCTFail("Expected a process action that opens Notes")
        }
    }

    func testEmptyLookupReturnsNoResults() async {
        let provider = AppleNotesProvider(lookup: { _ in .results([]) })
        let results = await provider.search(CommandSearchRequest(query: "notes zzz"))

        XCTAssertTrue(results.isEmpty)
    }
}
