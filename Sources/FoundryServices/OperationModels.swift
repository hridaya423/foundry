import Foundation
public enum OperationPhase: Equatable, Sendable { case assessing, awaitingConsent, provisioning, downloading, verifying, processing, committing, completed, failed, cancelled; public var terminal: Bool { self == .completed || self == .failed || self == .cancelled } }
public enum OperationProgress: Equatable, Sendable { case bytes(completed: Int64, total: Int64?), artifactBytes(artifact: String, completed: Int64, total: Int64?), items(completed: Int, total: Int?), indeterminate }
public struct OperationFailure: Equatable, Sendable {
    public let message: String
    public let retryable: Bool
    public init(message: String, retryable: Bool = false) { self.message = message; self.retryable = retryable }
}
public struct OperationRequestToken: Equatable, Sendable { public let value: String; public init(_ value: String) { self.value = value } }
public struct RetryDescriptor: Equatable, Sendable { public let request: OperationRequestToken; public let originalRequest: OperationRequestToken; public let currentAttempt: Int; public let maxAttempts: Int; public let delayNanoseconds: UInt64; public init(request: OperationRequestToken = OperationRequestToken(""), originalRequest: OperationRequestToken? = nil, currentAttempt: Int = 1, maxAttempts: Int, delayNanoseconds: UInt64 = 0) { self.request = request; self.originalRequest = originalRequest ?? request; self.currentAttempt = currentAttempt; self.maxAttempts = maxAttempts; self.delayNanoseconds = delayNanoseconds } }
public struct OperationSnapshot: Equatable, Sendable { public let id: UUID; public let phase: OperationPhase; public let progress: OperationProgress?; public let failure: OperationFailure?; public let retryDescriptor: RetryDescriptor?; public let request: OperationRequestToken?; public init(id: UUID, phase: OperationPhase, progress: OperationProgress?, failure: OperationFailure? = nil, retryDescriptor: RetryDescriptor? = nil, request: OperationRequestToken? = nil) { self.id = id; self.phase = phase; self.progress = progress; self.failure = failure; self.retryDescriptor = retryDescriptor; self.request = request } }
