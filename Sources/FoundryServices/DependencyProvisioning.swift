import Foundation

public enum ProvisioningError: Error, Equatable { case consentRequired, emptyPlan, executionFailed(String), artifactProvisionerUnavailable, receiptMismatch, cancelled }
public enum ProvisioningEvent: Equatable, Sendable { case started, command(ExactCommand), downloading(Artifact), progress(OperationProgress), completed, failed(String), cancelled }
public protocol ProvisioningExecutor: Sendable { func execute(_ command: ExactCommand) async throws }
public struct SetupReceipt: Equatable, Sendable { public let destination: String; public let verifiedIntegrity: String; public init(destination: String, verifiedIntegrity: String) { self.destination = destination; self.verifiedIntegrity = verifiedIntegrity } }
public protocol ArtifactProvisioner: Sendable { func provision(_ artifact: Artifact, progress: (@Sendable (OperationProgress) -> Void)?) async throws -> SetupReceipt }

public struct DependencyProvisioner: Sendable {
    private let executor: any ProvisioningExecutor; private let artifactProvisioner: (any ArtifactProvisioner)?
    public init(executor: any ProvisioningExecutor) { self.executor = executor; artifactProvisioner = nil }
    public init(executor: any ProvisioningExecutor, artifactProvisioner: any ArtifactProvisioner) { self.executor = executor; self.artifactProvisioner = artifactProvisioner }
    public func provision(plan: SetupPlan, approvedFingerprint: String, onEvent: (@Sendable (ProvisioningEvent) -> Void)? = nil) async throws -> [ProvisioningEvent] {
        guard approvedFingerprint == plan.fingerprint else { throw ProvisioningError.consentRequired }
        guard plan.commands.isEmpty == false || plan.artifacts.isEmpty == false else { throw ProvisioningError.emptyPlan }
        var events = [ProvisioningEvent.started]; onEvent?(.started)
        do {
            let total = plan.commands.count + plan.artifacts.count; emit(.progress(.items(completed: 0, total: total)), &events, onEvent); var items = 0; var aggregate: Int64 = 0
            for command in plan.commands { try Task.checkCancellation(); emit(.command(command), &events, onEvent); try await executor.execute(command); try Task.checkCancellation(); items += 1; emit(.progress(.items(completed: items, total: total)), &events, onEvent) }
            for artifact in plan.artifacts {
                try Task.checkCancellation(); guard let provisioner = artifactProvisioner else { throw ProvisioningError.artifactProvisionerUnavailable }; emit(.downloading(artifact), &events, onEvent)
                let collector = ProgressCollector(); let receipt = try await provisioner.provision(artifact) { collector.append($0) }
                guard receipt.destination == artifact.destination, receipt.verifiedIntegrity == artifact.integrityExpectation else { throw ProvisioningError.receiptMismatch }
                let aggregateTotal = plan.artifacts.allSatisfy { $0.downloadBytes != nil } ? plan.artifacts.compactMap(\.downloadBytes).reduce(0, +) : nil
                var lastCompleted: Int64 = 0
                for value in collector.values { if case let .bytes(completed, _) = value { let delta = max(0, completed - lastCompleted); lastCompleted = max(lastCompleted, completed); aggregate += delta; emit(.progress(.artifactBytes(artifact: artifact.destination, completed: completed, total: artifact.downloadBytes)), &events, onEvent); emit(.progress(.bytes(completed: aggregate, total: aggregateTotal)), &events, onEvent) } }
                items += 1; emit(.progress(.items(completed: items, total: total)), &events, onEvent)
            }
            try Task.checkCancellation(); emit(.completed, &events, onEvent); return events
        } catch is CancellationError { emit(.cancelled, &events, onEvent); throw ProvisioningError.cancelled
        } catch let error as ProvisioningError { if error == .cancelled { emit(.cancelled, &events, onEvent) } else { emit(.failed(String(describing: error)), &events, onEvent) }; throw error
        } catch { emit(.failed(error.localizedDescription), &events, onEvent); throw ProvisioningError.executionFailed(error.localizedDescription) }
    }
    private func emit(_ event: ProvisioningEvent, _ events: inout [ProvisioningEvent], _ callback: (@Sendable (ProvisioningEvent) -> Void)?) { events.append(event); callback?(event) }
}
private final class ProgressCollector: @unchecked Sendable { private let lock = NSLock(); private(set) var values = [OperationProgress](); func append(_ value: OperationProgress) { lock.withLock { values.append(value) } } }
