import Foundation

public enum ProvisioningError: Error, Equatable {
    case consentRequired, emptyPlan, executionFailed(String), cancelled
}
public enum ProvisioningEvent: Equatable, Sendable {
    case started, command(ExactCommand), progress(OperationProgress), completed, failed(String), cancelled
}
public protocol ProvisioningExecutor: Sendable { func execute(_ command: ExactCommand) async throws }

public struct DependencyProvisioner: Sendable {
    private let executor: any ProvisioningExecutor
    public init(executor: any ProvisioningExecutor) {
        self.executor = executor
    }
    public func provision(
        plan: SetupPlan,
        approvedFingerprint: String,
        onEvent: (@Sendable (ProvisioningEvent) -> Void)? = nil
    ) async throws -> [ProvisioningEvent] {
        guard approvedFingerprint == plan.fingerprint else { throw ProvisioningError.consentRequired }
        guard plan.commands.isEmpty == false else { throw ProvisioningError.emptyPlan }
        var events = [ProvisioningEvent.started]
        onEvent?(.started)
        do {
            let total = plan.commands.count
            emit(.progress(.items(completed: 0, total: total)), &events, onEvent)
            var items = 0
            for command in plan.commands {
                try Task.checkCancellation()
                emit(.command(command), &events, onEvent)
                try await executor.execute(command)
                try Task.checkCancellation()
                items += 1
                emit(.progress(.items(completed: items, total: total)), &events, onEvent)
            }
            try Task.checkCancellation()
            emit(.completed, &events, onEvent)
            return events
        } catch is CancellationError {
            emit(.cancelled, &events, onEvent)
            throw ProvisioningError.cancelled
        } catch let error as ProvisioningError {
            if error == .cancelled {
                emit(.cancelled, &events, onEvent)
            } else {
                emit(.failed(String(describing: error)), &events, onEvent)
            }
            throw error
        } catch {
            emit(.failed(error.localizedDescription), &events, onEvent)
            throw ProvisioningError.executionFailed(error.localizedDescription)
        }
    }
    private func emit(
        _ event: ProvisioningEvent,
        _ events: inout [ProvisioningEvent],
        _ callback: (@Sendable (ProvisioningEvent) -> Void)?
    ) {
        events.append(event)
        callback?(event)
    }
}
