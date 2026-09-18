import Foundation
import FoundryServices
import XCTest
@testable import Foundry

final class ResourcePackagingTests: XCTestCase {
    func testCameraCommandIsProvidedByDedicatedProvider() async {
        let results = await CameraCommandProvider().results(matching: "camera")

        XCTAssertEqual(results.map(\.id), ["foundry.camera"])
        XCTAssertEqual(results.first?.primaryAction.kind, .openCamera)
    }

    func testBuildPackagingDeclaresCameraPurposeAndEntitlement() throws {
        let buildScript = try String(contentsOf: rootURL().appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)
        let entitlements = try String(contentsOf: rootURL().appendingPathComponent("Supporting/Foundry.entitlements"), encoding: .utf8)

        XCTAssertTrue(buildScript.contains("NSCameraUsageDescription"))
        XCTAssertTrue(buildScript.contains("com.hridya.foundry"))
        XCTAssertTrue(buildScript.contains("Foundry.entitlements"))
        XCTAssertTrue(buildScript.contains("codesign --display --entitlements :- \"$APP_DIR\" 2>/dev/null | plutil -lint -"))
        XCTAssertTrue(entitlements.contains("com.apple.security.device.camera"))
        XCTAssertTrue(entitlements.contains("<true/>"))
        XCTAssertFalse(entitlements.contains("com.apple.security.app-sandbox"))
    }

    func testPackageDeclaresOnlyCurrentResourceDirectories() throws {
        let package = try String(contentsOf: rootURL().appendingPathComponent("Package.swift"), encoding: .utf8)

        XCTAssertTrue(package.contains(".copy(\"Resources/ProviderIcons/anthropic.svg\")"))
        XCTAssertTrue(package.contains(".copy(\"Resources/ProviderIcons/opencode.svg\")"))
        XCTAssertTrue(package.contains(".copy(\"Resources/FirefoxConnector/manifest.json\")"))
        XCTAssertTrue(package.contains(".copy(\"Resources/FirefoxConnector/background.js\")"))
        XCTAssertTrue(package.contains(".copy(\"Resources/BackgroundRemoval/NOTICE.txt\")"))
        XCTAssertTrue(package.contains(".copy(\"Resources/BackgroundRemoval/background_removal_worker.py\")"))
        XCTAssertTrue(package.contains(".copy(\"Resources/emoji.tsv\")"))
        XCTAssertFalse(package.contains(".process(\"Resources\")"))
    }

    func testPackagingScriptsAndEntitlementsParse() async throws {
        for script in ["scripts/build-app.sh", "scripts/verify-packaging.sh"] {
            let check = try await ProcessRunner.run(path: "/bin/zsh", arguments: ["-n", rootURL().appendingPathComponent(script).path])
            XCTAssertEqual(check.exitCode, 0, "\(script) failed zsh syntax check: \(check.stderr)")
        }
        let lint = try await ProcessRunner.run(path: "/usr/bin/plutil", arguments: ["-lint", rootURL().appendingPathComponent("Supporting/Foundry.entitlements").path])
        XCTAssertEqual(lint.exitCode, 0, "entitlements failed plutil lint: \(lint.stderr)")
    }

    private func rootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
