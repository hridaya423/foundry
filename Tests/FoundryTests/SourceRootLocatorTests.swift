import Foundation
import XCTest
@testable import Foundry

final class SourceRootLocatorTests: XCTestCase {
    func testSourceRunRegistersTheFirstValidatedCandidate() throws {
        let root = try makeProjectRoot()
        let defaults = try makeDefaults()

        let located = SourceRootLocator.locate(
            packaged: false,
            candidates: [root],
            defaults: defaults,
            fileChecks: .real
        )

        XCTAssertEqual(located, root)
        XCTAssertEqual(defaults.string(forKey: SourceRootLocator.registrationKey), root.path)
    }

    func testPackagedAppUsesOnlyTheValidatedRegisteredRoot() throws {
        let root = try makeProjectRoot()
        let defaults = try makeDefaults()
        defaults.set(root.path, forKey: SourceRootLocator.registrationKey)

        let located = SourceRootLocator.locate(
            packaged: true,
            candidates: [URL(fileURLWithPath: "/tmp/untrusted")],
            defaults: defaults,
            fileChecks: .real
        )

        XCTAssertEqual(located, root)
    }

    func testPackagedAppDoesNotTrustCandidatesWhenRegistrationIsMissing() throws {
        let root = try makeProjectRoot()
        let defaults = try makeDefaults()

        let located = SourceRootLocator.locate(
            packaged: true,
            candidates: [root],
            defaults: defaults,
            fileChecks: .real
        )

        XCTAssertNil(located)
    }

    func testInvalidRegisteredRootIsRejected() throws {
        let defaults = try makeDefaults()
        defaults.set("/tmp/not-a-project", forKey: SourceRootLocator.registrationKey)

        let located = SourceRootLocator.locate(
            packaged: true,
            candidates: [],
            defaults: defaults,
            fileChecks: .real
        )

        XCTAssertNil(located)
    }

    func testSourceRunUsesInjectedFileChecksBeforeRegistering() throws {
        let rejected = URL(fileURLWithPath: "/tmp/rejected")
        let accepted = URL(fileURLWithPath: "/tmp/accepted")
        let defaults = try makeDefaults()
        let checks = SourceRootLocator.FileChecks { candidate in
            candidate == accepted
        }

        let located = SourceRootLocator.locate(
            packaged: false,
            candidates: [rejected, accepted],
            defaults: defaults,
            fileChecks: checks
        )

        XCTAssertEqual(located, accepted)
        XCTAssertEqual(defaults.string(forKey: SourceRootLocator.registrationKey), accepted.path)
    }

    private func makeProjectRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("scripts/build-app.sh")
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/zsh\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "SourceRootLocatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return defaults
    }
}
