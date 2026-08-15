import Foundation
import XCTest
@testable import Foundry

final class ResourcePackagingTests: XCTestCase {
    func testCameraProviderExposesOnlyCameraPermission() {
        let descriptor = CameraCommandProvider().descriptor

        XCTAssertEqual(descriptor.id, "foundry.camera")
        XCTAssertEqual(descriptor.requiredPermissions, ["camera"])
    }

    func testCameraCommandIsProvidedByDedicatedProvider() async {
        let results = await CameraCommandProvider().results(matching: "camera")

        XCTAssertEqual(results.map(\.id), ["foundry.camera"])
        XCTAssertEqual(results.first?.primaryAction.kind, .openCamera)
    }

    func testBuildPackagingDeclaresCameraPurposeAndEntitlement() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let buildScript = try String(contentsOf: root.appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)
        let entitlements = try String(contentsOf: root.appendingPathComponent("Supporting/Foundry.entitlements"), encoding: .utf8)

        XCTAssertTrue(buildScript.contains("NSCameraUsageDescription"))
        XCTAssertTrue(buildScript.contains("com.hridya.foundry"))
        XCTAssertTrue(buildScript.contains("Foundry.entitlements"))
        XCTAssertTrue(entitlements.contains("com.apple.security.device.camera"))
        XCTAssertTrue(entitlements.contains("<true/>"))
        XCTAssertFalse(entitlements.contains("com.apple.security.app-sandbox"))
    }

    func testBuildScriptCanStageWithoutInstallingOrLaunching() throws {
        let buildScript = try String(contentsOf: rootURL().appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)

        XCTAssertTrue(buildScript.contains("INSTALL_APP"))
        XCTAssertTrue(buildScript.contains("LAUNCH_APP"))
        XCTAssertFalse(buildScript.contains("SKIP_INSTALL"))
        XCTAssertFalse(buildScript.contains("SKIP_LAUNCH"))

        let installOnlyWork = try XCTUnwrap(buildScript.range(of: "if [[ \"${INSTALL_APP:-0}\" == \"1\" ]]; then"))
        let installOnlyBlock = String(buildScript[installOnlyWork.lowerBound...])
        XCTAssertTrue(installOnlyBlock.contains("Stopping the running installed copy..."))
        XCTAssertTrue(installOnlyBlock.contains("osascript"))
        XCTAssertTrue(installOnlyBlock.contains("cp -R \"$APP_DIR\" \"$INSTALL_DIR\""))
        XCTAssertTrue(installOnlyBlock.contains("defaults write com.hridya.foundry foundry.sourceRoot \"$ROOT_DIR\""))
        XCTAssertFalse(buildScript[..<installOnlyWork.lowerBound].contains("Stopping the running installed copy..."))
        XCTAssertFalse(buildScript[..<installOnlyWork.lowerBound].contains("osascript"))
        XCTAssertTrue(buildScript.contains("LAUNCH_APP=1 requires INSTALL_APP=1"))
    }

    func testPackagingVerifierChecksTheBuiltArtifact() throws {
        let verifier = try String(contentsOf: rootURL().appendingPathComponent("scripts/verify-packaging.sh"), encoding: .utf8)

        XCTAssertTrue(verifier.contains("build/Foundry.app"))
        XCTAssertTrue(verifier.contains("codesign --verify"))
        XCTAssertTrue(verifier.contains("NSCameraUsageDescription"))
        XCTAssertTrue(verifier.contains("FoundrySourceRoot"))
        XCTAssertTrue(verifier.contains("feynobg_worker.py"))
        XCTAssertTrue(verifier.contains("com.apple.security.device.camera"))
        XCTAssertTrue(verifier.contains("source path remains"))
        XCTAssertTrue(verifier.contains("default packaging unexpectedly created"))
    }

    func testREADMEDocumentsBuildAndOptionalSetup() throws {
        let readme = try String(contentsOf: rootURL().appendingPathComponent("README.md"), encoding: .utf8)
        for claim in ["Persistent local clipboard history", "automatic expansion support", "automatic YouTube support", "optional BEN2 support", "without installing or launching"] {
            XCTAssertTrue(readme.contains(claim), "README is missing: \(claim)")
        }
        XCTAssertFalse(readme.contains("optional YouTube support"))
        XCTAssertFalse(readme.contains("Activity Monitor"))
    }

    func testEntitlementsVerificationKeepsCodesignDiagnosticsOutOfPlistInput() throws {
        let script = try String(contentsOf: rootURL().appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("codesign --display --entitlements :- \"$APP_DIR\" 2>/dev/null | plutil -lint -"))
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

    func testBuildRejectsStaleAndExecutableResources() throws {
        let script = try String(contentsOf: rootURL().appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)

        XCTAssertTrue(script.contains("*.pyc"))
        XCTAssertTrue(script.contains("feynobg_worker.py"))
        XCTAssertTrue(script.contains("-perm -111"))
        XCTAssertTrue(script.contains("NOTICE.txt"))
    }

    private func rootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
