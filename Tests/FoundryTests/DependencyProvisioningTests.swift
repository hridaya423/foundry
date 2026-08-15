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

    func testCapabilityStatesAreEquatable() {
        XCTAssertEqual(CapabilityState.ready, .ready)
        XCTAssertEqual(CapabilityState.setupRequired(SetupPlan(commands: [], artifacts: [], mutationScope: "none", cleanupOwnership: "none", disclosure: "none")), CapabilityState.setupRequired(SetupPlan(commands: [], artifacts: [], mutationScope: "none", cleanupOwnership: "none", disclosure: "none")))
        XCTAssertEqual(CapabilityState.unavailable("x"), .unavailable("x"))
        XCTAssertEqual(CapabilityState.degraded("x"), .degraded("x"))
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

    func testArtifactProgressAggregatesDeltasAcrossArtifacts() async throws {
        let artifacts = [Artifact(origin: "a", destination: "A", downloadBytes: 10), Artifact(origin: "b", destination: "B", downloadBytes: 20)]
        let recorder = CumulativeArtifactExecutor(values: [[3, 10], [5, 20]])
        let plan = SetupPlan(commands: [], artifacts: artifacts, mutationScope: "u", cleanupOwnership: "c", disclosure: "d")
        let events = try await DependencyProvisioner(executor: RecordingExecutor(), artifactProvisioner: recorder).provision(plan: plan, approvedFingerprint: plan.fingerprint)
        let progress = events.compactMap { event -> OperationProgress? in if case let .progress(value) = event { return value }; return nil }
        XCTAssertEqual(progress.filter { if case .bytes = $0 { return true }; return false }, [.bytes(completed: 3, total: 30), .bytes(completed: 10, total: 30), .bytes(completed: 15, total: 30), .bytes(completed: 30, total: 30)])
        XCTAssertEqual(progress.filter { if case .artifactBytes = $0 { return true }; return false }, [.artifactBytes(artifact: "A", completed: 3, total: 10), .artifactBytes(artifact: "A", completed: 10, total: 10), .artifactBytes(artifact: "B", completed: 5, total: 20), .artifactBytes(artifact: "B", completed: 20, total: 20)])
    }

    func testEmptyPlanIsTypedRejectionWithoutSideEffects() async {
        let executor = RecordingExecutor(); let plan = SetupPlan(commands: [], artifacts: [], mutationScope: "u", cleanupOwnership: "c", disclosure: "d")
        do { _ = try await DependencyProvisioner(executor: executor).provision(plan: plan, approvedFingerprint: plan.fingerprint); XCTFail("expected empty plan") }
        catch ProvisioningError.emptyPlan { } catch { XCTFail("unexpected error: \(error)") }
        XCTAssertTrue(executor.commands.isEmpty)
    }

    func testReceiptDestinationMismatchStopsRemainingArtifacts() async {
        let a = Artifact(origin: "a", destination: "A"); let b = Artifact(origin: "b", destination: "B")
        let recorder = ReceiptArtifactExecutor(receipts: [SetupReceipt(destination: "wrong", verifiedIntegrity: "verified"), SetupReceipt(destination: "B", verifiedIntegrity: "verified")])
        let plan = SetupPlan(commands: [], artifacts: [a, b], mutationScope: "u", cleanupOwnership: "c", disclosure: "d")
        do { _ = try await DependencyProvisioner(executor: RecordingExecutor(), artifactProvisioner: recorder).provision(plan: plan, approvedFingerprint: plan.fingerprint); XCTFail("expected mismatch") } catch ProvisioningError.receiptMismatch { } catch { XCTFail("unexpected error") }
        XCTAssertEqual(recorder.artifacts, [a])
    }

    func testReceiptIntegrityMismatchStopsRemainingArtifacts() async {
        let a = Artifact(origin: "a", destination: "A", integrityExpectation: "hash"); let b = Artifact(origin: "b", destination: "B")
        let recorder = ReceiptArtifactExecutor(receipts: [SetupReceipt(destination: "A", verifiedIntegrity: "wrong"), SetupReceipt(destination: "B", verifiedIntegrity: "verified")])
        let plan = SetupPlan(commands: [], artifacts: [a, b], mutationScope: "u", cleanupOwnership: "c", disclosure: "d")
        do { _ = try await DependencyProvisioner(executor: RecordingExecutor(), artifactProvisioner: recorder).provision(plan: plan, approvedFingerprint: plan.fingerprint); XCTFail("expected mismatch") } catch ProvisioningError.receiptMismatch { } catch { XCTFail("unexpected error") }
        XCTAssertEqual(recorder.artifacts, [a])
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

    func testArtifactExecutorReceivesExactArtifactAndProgress() async throws {
        let artifact = Artifact(origin: "https://example/x", destination: "/tmp/x", downloadBytes: 10, installBytes: 20)
        let artifactExecutor = RecordingArtifactExecutor()
        let service = DependencyProvisioner(executor: RecordingExecutor(), artifactProvisioner: artifactExecutor)
        let events = try await service.provision(plan: SetupPlan(commands: [], artifacts: [artifact], mutationScope: "u", cleanupOwnership: "c", disclosure: "d"), approvedFingerprint: SetupPlan(commands: [], artifacts: [artifact], mutationScope: "u", cleanupOwnership: "c", disclosure: "d").fingerprint)
        XCTAssertEqual(artifactExecutor.artifacts, [artifact])
        XCTAssertTrue(events.contains { if case .progress(.bytes(10, 10)) = $0 { return true }; return false })
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

    func testArtifactPlanWithoutProvisionerFailsBeforeCompletion() async {
        let artifact = Artifact(origin: "x", destination: "y")
        let plan = SetupPlan(commands: [], artifacts: [artifact], mutationScope: "u", cleanupOwnership: "c", disclosure: "d")
        do { _ = try await DependencyProvisioner(executor: RecordingExecutor()).provision(plan: plan, approvedFingerprint: plan.fingerprint); XCTFail("expected unavailable") }
        catch ProvisioningError.artifactProvisionerUnavailable { }
        catch { XCTFail("unexpected error: \(error)") }
    }

    func testProvisioningReportsAggregateItemProgress() async throws {
        let plan = SetupPlan(commands: [ExactCommand(executable: "one", arguments: [])], artifacts: [Artifact(origin: "x", destination: "y")], mutationScope: "u", cleanupOwnership: "c", disclosure: "d")
        let events = try await DependencyProvisioner(executor: RecordingExecutor(), artifactProvisioner: RecordingArtifactExecutor()).provision(plan: plan, approvedFingerprint: plan.fingerprint)
        let progress = events.compactMap { event -> OperationProgress? in if case let .progress(value) = event { return value }; return nil }
        XCTAssertEqual(progress, [.items(completed: 0, total: 2), .items(completed: 1, total: 2), .artifactBytes(artifact: "y", completed: 10, total: nil), .bytes(completed: 10, total: nil), .items(completed: 2, total: 2)])
    }
}

private final class RecordingExecutor: @unchecked Sendable, ProvisioningExecutor {
    enum Result { case success, failure }
    var commands: [ExactCommand] = []
    var results: [Result]
    init(results: [Result] = []) { self.results = results }
    func execute(_ command: ExactCommand) async throws { commands.append(command); if results.first == .failure { results.removeFirst(); throw ProvisioningError.executionFailed("failed") }; if results.isEmpty == false { results.removeFirst() } }
}

private final class RecordingArtifactExecutor: @unchecked Sendable, ArtifactProvisioner {
    var artifacts: [Artifact] = []
    func provision(_ artifact: Artifact, progress: (@Sendable (OperationProgress) -> Void)?) async throws -> SetupReceipt { artifacts.append(artifact); progress?(.bytes(completed: 10, total: artifact.downloadBytes)); return SetupReceipt(destination: artifact.destination, verifiedIntegrity: artifact.integrityExpectation) }
}

private final class CumulativeArtifactExecutor: @unchecked Sendable, ArtifactProvisioner {
    var values: [[Int64]]; var index = 0
    init(values: [[Int64]]) { self.values = values }
    func provision(_ artifact: Artifact, progress: (@Sendable (OperationProgress) -> Void)?) async throws -> SetupReceipt { for value in values[index] { progress?(.bytes(completed: value, total: artifact.downloadBytes)) }; index += 1; return SetupReceipt(destination: artifact.destination, verifiedIntegrity: artifact.integrityExpectation) }
}
private final class ReceiptArtifactExecutor: @unchecked Sendable, ArtifactProvisioner {
    let receipts: [SetupReceipt]; var index = 0; var artifacts = [Artifact](); init(receipts: [SetupReceipt]) { self.receipts = receipts }
    func provision(_ artifact: Artifact, progress: (@Sendable (OperationProgress) -> Void)?) async throws -> SetupReceipt { artifacts.append(artifact); defer { index += 1 }; return receipts[index] }
}
