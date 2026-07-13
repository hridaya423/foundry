import Foundation
import XCTest
@testable import Foundry

final class AppSearchProviderTests: XCTestCase {
    func testSearchDiscoversAppsInstalledAfterProviderInitialization() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-app-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let diagnostics = DiagnosticsService()
        let provider = AppSearchProvider(diagnostics: diagnostics, roots: [root])

        try writeApp(named: "First App", to: root)
        let firstResults = await provider.results(matching: "first app")
        XCTAssertEqual(firstResults.first?.title, "First App")

        try writeApp(named: "Second App", to: root)
        try await Task.sleep(for: .milliseconds(2_100))
        let secondResults = await provider.results(matching: "second app")
        XCTAssertEqual(secondResults.first?.title, "Second App")
    }

    private func writeApp(named name: String, to root: URL) throws {
        let app = root.appendingPathComponent("\(name).app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleDisplayName": name,
            "CFBundleIdentifier": "local.foundry.\(name.lowercased().replacingOccurrences(of: " ", with: "-"))"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Info.plist"))
    }
}
