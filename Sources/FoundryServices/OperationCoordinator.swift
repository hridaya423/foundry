import Foundation
import os
public final class OperationCoordinator: Sendable {
    private struct State {
        var states: [UUID: OperationSnapshot] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    public init() {}
    public func start(retryDescriptor: RetryDescriptor? = nil) -> UUID {
        let id = UUID()
        state.withLock { state in
            state.states[id] = OperationSnapshot(
                id: id,
                phase: .assessing,
                progress: nil,
                retryDescriptor: retryDescriptor,
                request: retryDescriptor?.request
            )
        }
        return id
    }
    public func retry(id: UUID) -> OperationSnapshot? {
        state.withLock { state in
            guard let prior = state.states[id],
                  prior.phase == .failed || prior.phase == .cancelled,
                  let descriptor = prior.retryDescriptor,
                  descriptor.currentAttempt < descriptor.maxAttempts
            else { return nil }
            let next = RetryDescriptor(
                request: OperationRequestToken(UUID().uuidString),
                originalRequest: descriptor.originalRequest,
                currentAttempt: descriptor.currentAttempt + 1,
                maxAttempts: descriptor.maxAttempts,
                delayNanoseconds: descriptor.delayNanoseconds
            )
            let snapshot = OperationSnapshot(
                id: UUID(),
                phase: .assessing,
                progress: nil,
                retryDescriptor: next,
                request: next.request
            )
            state.states[snapshot.id] = snapshot
            return snapshot
        }
    }
    @discardableResult
    public func update(
        id: UUID,
        phase: OperationPhase,
        progress: OperationProgress?,
        failure: OperationFailure? = nil
    ) -> Bool {
        state.withLock { state in
            guard let current = state.states[id], !current.phase.terminal else { return false }
            let legal: Set<OperationPhase> = {
                switch current.phase {
                case .assessing: return [.awaitingConsent, .provisioning, .downloading, .processing, .failed, .cancelled]
                case .awaitingConsent: return [.provisioning, .failed, .cancelled]
                case .provisioning: return [.downloading, .processing, .completed, .failed, .cancelled]
                case .downloading: return [.verifying, .failed, .cancelled]
                case .verifying: return [.processing, .failed, .cancelled]
                case .processing: return [.committing, .completed, .failed, .cancelled]
                case .committing: return [.completed, .failed, .cancelled]
                default: return []
                }
            }()
            guard legal.contains(phase) else { return false }
            state.states[id] = OperationSnapshot(
                id: id,
                phase: phase,
                progress: progress,
                failure: failure,
                retryDescriptor: current.retryDescriptor,
                request: current.request
            )
            return true
        }
    }
    @discardableResult
    public func updateProgress(id: UUID, progress: OperationProgress) -> Bool {
        state.withLock { state in
            guard let current = state.states[id], !current.phase.terminal else { return false }
            state.states[id] = OperationSnapshot(
                id: id,
                phase: current.phase,
                progress: progress,
                failure: current.failure,
                retryDescriptor: current.retryDescriptor,
                request: current.request
            )
            return true
        }
    }
    public func snapshot(id: UUID) -> OperationSnapshot? { state.withLock { $0.states[id] } }
}
