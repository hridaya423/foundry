import os
import Foundation
import XCTest
@testable import Foundry
import FoundryServices

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
        let secondResults = await provider.results(matching: "second app")
        XCTAssertEqual(secondResults.first?.title, "Second App")
    }

    func testFinderIsFoundButCoreServicesHelpersAreNot() async {
        let provider = AppSearchProvider(diagnostics: DiagnosticsService(), roots: [], extraApps: AppSearchProvider.coreServicesApps)
        let finder = await provider.results(matching: "finder")
        XCTAssertEqual(finder.first?.id, "app.com.apple.finder")
        let dock = await provider.results(matching: "dock")
        XCTAssertTrue(dock.isEmpty)
    }

    func testRunningAppsGetQuitHideAndForceQuitActions() {
        let idle = AppSearchProvider.actions(identity: "x", name: "X", path: "/Applications/X.app", bundleID: "com.x", isRunning: false).map(\.title)
        XCTAssertEqual(idle, ["Show in Finder", "Copy Path", "Copy Bundle ID"])
        let running = AppSearchProvider.actions(identity: "x", name: "X", path: "/Applications/X.app", bundleID: "com.x", isRunning: true).map(\.title)
        XCTAssertEqual(running, ["Quit", "Hide", "Force Quit", "Show in Finder", "Copy Path", "Copy Bundle ID"])
        XCTAssertTrue(ForceQuitApplicationAction(bundleID: "com.x", name: "X").style == .destructive)
    }

    func testIndexSuppliesAppsOutsideTheScannedRoots() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-app-tests-\(UUID().uuidString)")
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-app-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: elsewhere) }
        try writeApp(named: "Root App", to: root)
        try writeApp(named: "Nested Elsewhere App", to: elsewhere)

        let index = FakeAppIndex(urls: [elsewhere.appendingPathComponent("Nested Elsewhere App.app")])
        let provider = AppSearchProvider(diagnostics: DiagnosticsService(), roots: [root], index: index)

        let rootResults = await provider.results(matching: "root app")
        XCTAssertEqual(rootResults.first?.title, "Root App")
        let indexedResults = await provider.results(matching: "nested elsewhere")
        XCTAssertEqual(indexedResults.first?.title, "Nested Elsewhere App")
    }

    func testIndexUpdateInvalidatesTheCacheImmediately() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-app-tests-\(UUID().uuidString)")
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-app-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: elsewhere) }
        try writeApp(named: "Late Arrival", to: elsewhere)

        let index = FakeAppIndex(urls: [])
        let provider = AppSearchProvider(diagnostics: DiagnosticsService(), roots: [root], index: index)
        let before = await provider.results(matching: "late arrival")
        XCTAssertTrue(before.isEmpty)

        index.setURLs([elsewhere.appendingPathComponent("Late Arrival.app")])
        index.fireUpdate()
        let after = await provider.results(matching: "late arrival")
        XCTAssertEqual(after.first?.title, "Late Arrival")
    }

    private final class FakeAppIndex: AppIndexing, @unchecked Sendable {
        private let state = OSAllocatedUnfairLock(initialState: [URL]())
        var onUpdate: (@Sendable () -> Void)?

        init(urls: [URL]) { setURLs(urls) }

        func start() {}
        var urls: [URL] { state.withLock { $0 } }
        func setURLs(_ urls: [URL]) { state.withLock { $0 = urls } }
        func fireUpdate() { onUpdate?() }
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
