import os
import XCTest
import FoundryServices

final class DependencyProvisioningTests: XCTestCase {
    func testDefaultLocatorAcceptsExecutableSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let executable = root.appendingPathComponent("tool-real")
        let symlink = root.appendingPathComponent("tool")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: executable)

        XCTAssertEqual(try ExecutableLocator().locate(name: "tool", candidates: [symlink.path], environment: [:])?.path, symlink.path)
    }

    func testDiscoveryUsesInjectedCandidatesAndPathWithoutMutation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let executable = root.appendingPathComponent("tool")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let locator = ExecutableLocator(fileInfo: { path in
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            return (attrs?[.type] as? FileAttributeType) == .typeRegular && ((attrs?[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o111 != 0
        })
        XCTAssertEqual(try locator.locate(name: "tool", candidates: ["/invalid"], environment: ["PATH": root.path])?.path, executable.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }

    func testFingerprintChangesForMaterialFields() {
        let plan = SetupPlan(commands: [ExactCommand(executable: "/bin/tool", arguments: ["--a"])], artifacts: [], mutationScope: "user", cleanupOwnership: "app", disclosure: "install")
        XCTAssertEqual(plan.fingerprint, plan.fingerprint)
        let changed = SetupPlan(commands: [ExactCommand(executable: "/bin/tool", arguments: ["--b"])], artifacts: [], mutationScope: "user", cleanupOwnership: "app", disclosure: "install")
        XCTAssertNotEqual(plan.fingerprint, changed.fingerprint)
        XCTAssertNotEqual(SetupPlan(commands: [ExactCommand(executable: "a\u{1f}b", arguments: [])], artifacts: [], mutationScope: "u", cleanupOwnership: "c", disclosure: "d").fingerprint,
                           SetupPlan(commands: [ExactCommand(executable: "a", arguments: ["b"])], artifacts: [], mutationScope: "u", cleanupOwnership: "c", disclosure: "d").fingerprint)
        XCTAssertNotEqual(plan.fingerprint, SetupPlan(commands: plan.commands, artifacts: plan.artifacts, estimatedDownloadBytes: 1, mutationScope: plan.mutationScope, cleanupOwnership: plan.cleanupOwnership, disclosure: plan.disclosure).fingerprint)
    }

    func testFingerprintIncludesArtifactIntegrityExpectation() {
        let artifact = Artifact(origin: "x", destination: "y", integrityExpectation: "sha256:a")
        let changed = Artifact(origin: "x", destination: "y", integrityExpectation: "sha256:b")
        let base = SetupPlan(commands: [], artifacts: [artifact], mutationScope: "u", cleanupOwnership: "c", disclosure: "d")
        let other = SetupPlan(commands: [], artifacts: [changed], mutationScope: "u", cleanupOwnership: "c", disclosure: "d")
        XCTAssertNotEqual(base.fingerprint, other.fingerprint)
    }

    func testEmptyPlanIsTypedRejectionWithoutSideEffects() async {
        let executor = RecordingExecutor(); let plan = SetupPlan(commands: [], artifacts: [], mutationScope: "u", cleanupOwnership: "c", disclosure: "d")
        do { _ = try await DependencyProvisioner(executor: executor).provision(plan: plan, approvedFingerprint: plan.fingerprint); XCTFail("expected empty plan") }
        catch ProvisioningError.emptyPlan { } catch { XCTFail("unexpected error: \(error)") }
        XCTAssertTrue(executor.commands.isEmpty)
    }

    func testVersionParsingIsStrictAndNumeric() async throws {
        for output in ["1..2", "1.2.3.4", "tool 1.2suffix", "2026-08-13"] {
            let r = try CapabilityRequirement(executableName: "tool", explicitPaths: ["/bin/tool"], versionArguments: ["--version"], minimumVersion: "1.5")
            let a = CapabilityAssessor(locator: ExecutableLocator(fileInfo: { $0 == "/bin/tool" }), versionProbe: VersionProbe { _, _ in try await ProcessRunner.run(path: "/usr/bin/printf", arguments: [output]) })
            if case .ready = try await a.assess(r) { XCTFail("accepted invalid output \(output)") }
        }
        for output in ["tool version 1.5", "tool version 1.5.2", "v1.5.2"] {
            let r = try CapabilityRequirement(executableName: "tool", explicitPaths: ["/bin/tool"], versionArguments: ["--version"], minimumVersion: "1.5")
            let a = CapabilityAssessor(locator: ExecutableLocator(fileInfo: { $0 == "/bin/tool" }), versionProbe: VersionProbe { _, _ in try await ProcessRunner.run(path: "/usr/bin/printf", arguments: [output]) })
            if case .ready = try await a.assess(r) {} else { XCTFail("rejected valid output \(output)") }
        }
        let low = try CapabilityRequirement(executableName: "tool", explicitPaths: ["/bin/tool"], versionArguments: ["--version"], minimumVersion: "2.10")
        let a = CapabilityAssessor(locator: ExecutableLocator(fileInfo: { $0 == "/bin/tool" }), versionProbe: VersionProbe { _, _ in try await ProcessRunner.run(path: "/usr/bin/printf", arguments: ["2.9"]) })
        if case .degraded = try await a.assess(low) {} else { XCTFail("numeric comparison failed") }
    }

    func testMinimumVersionWithoutProbeArgumentsIsUnavailable() async throws {
        let r = try CapabilityRequirement(executableName: "tool", explicitPaths: ["/bin/tool"], minimumVersion: "1.0")
        let state = try await CapabilityAssessor(locator: ExecutableLocator(fileInfo: { _ in true }), versionProbe: VersionProbe()).assess(r)
        XCTAssertEqual(state, .unavailable("verification not configured: no version probe arguments"))
    }

    func testAssessmentRethrowsCancellationErrors() async throws {
        let r = try CapabilityRequirement(executableName: "tool", explicitPaths: ["/bin/tool"], versionArguments: ["--version"])
        for error in [ProcessRunnerError.cancelled as Error, CancellationError() as Error] {
            let a = CapabilityAssessor(locator: ExecutableLocator(fileInfo: { _ in true }), versionProbe: VersionProbe { _, _ in throw error })
            do { _ = try await a.assess(r); XCTFail("expected cancellation") } catch is CancellationError { } catch let e as ProcessRunnerError { XCTAssertEqual(e, .cancelled) } catch { XCTFail("unexpected error") }
        }
    }

    func testCapabilityAssessmentUsesProbeAndReportsVersionStates() async throws {
        let locator = ExecutableLocator(fileInfo: { $0 == "/bin/tool" })
        let requirement = try CapabilityRequirement(executableName: "tool", explicitPaths: ["/bin/tool"], pathDirectories: [], versionArguments: ["--version"], minimumVersion: "2")
        let assessment = CapabilityAssessor(locator: locator, versionProbe: VersionProbe { _, _ in try await ProcessRunner.run(path: "/usr/bin/printf", arguments: ["1"]) })
        if case .degraded = try await assessment.assess(requirement) {} else { XCTFail("expected degraded") }
        let failing = CapabilityAssessor(locator: locator, versionProbe: VersionProbe { _, _ in throw ProcessRunnerError.launchFailed("no") })
        if case .unavailable = try await failing.assess(requirement) {} else { XCTFail("expected unavailable") }
    }

    func testProvisioningRequiresMatchingConsent() async {
        let plan = SetupPlan(commands: [ExactCommand(executable: "/bin/tool", arguments: [])], artifacts: [], mutationScope: "user", cleanupOwnership: "app", disclosure: "install")
        let executor = RecordingExecutor()
        let service = DependencyProvisioner(executor: executor)
        do { _ = try await service.provision(plan: plan, approvedFingerprint: "wrong") ; XCTFail("expected rejection") } catch ProvisioningError.consentRequired { } catch { XCTFail("unexpected error") }
        XCTAssertTrue(executor.commands.isEmpty)
    }

    func testApprovedProvisioningRunsExactCommandsAndStopsOnFailure() async throws {
        let plan = SetupPlan(commands: [ExactCommand(executable: "/bin/one", arguments: ["a", "b"]), ExactCommand(executable: "/bin/two", arguments: [])], artifacts: [], mutationScope: "user", cleanupOwnership: "app", disclosure: "install")
        let executor = RecordingExecutor(results: [.failure, .success])
        let service = DependencyProvisioner(executor: executor)
        let events: [ProvisioningEvent]
        do { events = try await service.provision(plan: plan, approvedFingerprint: plan.fingerprint) } catch ProvisioningError.executionFailed { events = [.failed("failed")] } catch { XCTFail("unexpected error"); return }
        XCTAssertEqual(executor.commands.map { $0.executable }, ["/bin/one"])
        XCTAssertTrue(events.contains { if case .failed = $0 { return true }; return false })
    }

    func testProvisioningReportsAggregateItemProgress() async throws {
        let commands = [ExactCommand(executable: "one", arguments: []), ExactCommand(executable: "two", arguments: [])]
        let plan = SetupPlan(commands: commands, artifacts: [], mutationScope: "u", cleanupOwnership: "c", disclosure: "d")
        let events = try await DependencyProvisioner(executor: RecordingExecutor()).provision(plan: plan, approvedFingerprint: plan.fingerprint)
        let progress = events.compactMap { event -> OperationProgress? in if case let .progress(value) = event { return value }; return nil }
        XCTAssertEqual(progress, [.items(completed: 0, total: 2), .items(completed: 1, total: 2), .items(completed: 2, total: 2)])
    }
}

private final class RecordingExecutor: Sendable, ProvisioningExecutor {
    enum Result { case success, failure }
    private let box: OSAllocatedUnfairLock<(commands: [ExactCommand], results: [Result])>
    init(results: [Result] = []) { box = OSAllocatedUnfairLock(initialState: ([], results)) }
    var commands: [ExactCommand] { box.withLock { $0.commands } }
    func execute(_ command: ExactCommand) async throws {
        try box.withLock { box in
            box.commands.append(command)
            if box.results.first == .failure {
                box.results.removeFirst()
                throw ProvisioningError.executionFailed("failed")
            }
            if box.results.isEmpty == false { box.results.removeFirst() }
        }
    }
}
