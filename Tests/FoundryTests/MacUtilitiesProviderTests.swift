import XCTest
@testable import Foundry

final class MacUtilitiesProviderTests: XCTestCase {
    func testPortResultsRequireExplicitPortIntent() async {
        let provider = MacUtilitiesProvider()

        let bareDigits = await provider.results(matching: "2024")
        XCTAssertFalse(bareDigits.contains { $0.id.hasPrefix("mac.port.") })

        let explicit = await provider.results(matching: "port 1")
        XCTAssertTrue(explicit.contains { $0.id == "mac.port.1" })
    }

    func testKillPortLooksUpListenersOnly() {
        let arguments = TerminatePortAction.lookupArguments(port: 3000)
        XCTAssertTrue(arguments.contains("-sTCP:LISTEN"))
        XCTAssertTrue(arguments.contains("-iTCP:3000"))
    }

    func testKillPortNeverTargetsItsOwnProcess() {
        XCTAssertEqual(TerminatePortAction.targets(fromLookupOutput: "12\n34\n12\n\n", excluding: 34), ["12"])
    }
}
