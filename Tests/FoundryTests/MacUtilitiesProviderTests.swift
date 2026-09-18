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
}
