import Foundation
import XCTest
@testable import Foundry

/// 5.9 groundwork: the Localizable.xcstrings catalog must actually compile
/// into the packaged resource bundle, seeded keys must resolve to English,
/// explicit keys must return their default value, and unseeded keys must
/// fall back to the source-language text.
final class LocalizationTests: XCTestCase {
    func testCatalogShipsInPackagedResourceBundle() throws {
        let bundle = try XCTUnwrap(Bundle.packagedResources, "Foundry_Foundry.bundle must be reachable")
        XCTAssertNotNil(bundle.url(forResource: "Localizable", withExtension: "strings"))
    }

    func testSeededKeysResolveFromPackagedBundle() throws {
        let bundle = try XCTUnwrap(Bundle.packagedResources)
        let missing = "<missing \(UUID().uuidString)>"
        XCTAssertEqual(bundle.localizedString(forKey: "Settings", value: missing, table: nil), "Settings")
        XCTAssertEqual(bundle.localizedString(forKey: "menu.item.settings", value: missing, table: nil), "Settings…")
        XCTAssertEqual(String(localized: "menu.item.settings", defaultValue: "Not the catalog value", bundle: bundle), "Settings…")
    }

    func testUnseededKeyFallsBackToSourceText() throws {
        let bundle = try XCTUnwrap(Bundle.packagedResources)
        let key = "No catalog entry exists for this"
        let missing = "<missing \(UUID().uuidString)>"
        XCTAssertEqual(bundle.localizedString(forKey: key, value: missing, table: nil), missing)
        XCTAssertEqual(String(localized: String.LocalizationValue(key), bundle: bundle), key)
    }
}
