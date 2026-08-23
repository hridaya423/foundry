import Foundation
import FoundryDomain
import FoundryServices

final class CommandProviderScheduler: @unchecked Sendable {
    private let diagnostics: DiagnosticsService
    private let providerHealth: ProviderHealthStore
    private let gateLock = NSLock()
    private var providerGates: [String: ProviderExecutionGate] = [:]

    init(diagnostics: DiagnosticsService, providerHealth: ProviderHealthStore) {
        self.diagnostics = diagnostics
        self.providerHealth = providerHealth
    }

    func search(
        query: String,
        providers: [CommandProvider],
        aliases: [String: [String]],
        sensitivity: SearchSensitivity,
        timeout: Duration
    ) async -> ([RankCandidate], [ProviderSearchTiming]) {
        let aliasKey = aliases
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.joined(separator: ","))" }
            .joined(separator: "|")

        return await withTaskGroup(of: ProviderSearchResult.self, returning: ([RankCandidate], [ProviderSearchTiming]).self) { group in
            for provider in providers {
                group.addTask { [diagnostics] in
                    let span = diagnostics.startSpan("search.provider.\(provider.id)")
                    defer { diagnostics.endSpan(span) }
                    let startedAt = Date().timeIntervalSinceReferenceDate
                    let deadline = ContinuousClock().now.advanced(by: timeout)
                    let outcome = await self.results(
                        from: provider,
                        query: query,
                        aliases: aliases,
                        sensitivity: sensitivity,
                        aliasKey: aliasKey,
                        deadline: deadline
                    )
                    let elapsedMilliseconds = (Date().timeIntervalSinceReferenceDate - startedAt) * 1_000
                    await self.record(outcome.status, providerID: provider.id, elapsedMilliseconds: elapsedMilliseconds, resultCount: outcome.value?.count ?? 0)
                    return ProviderSearchResult(
                        providerID: provider.id,
                        results: outcome.value ?? [],
                        elapsedMilliseconds: elapsedMilliseconds,
                        status: outcome.status
                    )
                }
            }

            var candidates: [RankCandidate] = []
            var timings: [ProviderSearchTiming] = []
            for await providerResult in group {
                guard Task.isCancelled == false else {
                    group.cancelAll()
                    return ([], [])
                }
                candidates.append(contentsOf: providerResult.results.enumerated().map { index, result in
                    RankCandidate(result: result, providerID: providerResult.providerID, sourceOrder: index)
                })
                timings.append(ProviderSearchTiming(
                    providerID: providerResult.providerID,
                    elapsedMilliseconds: providerResult.elapsedMilliseconds,
                    status: providerResult.status
                ))
            }
            return (candidates, timings)
        }
    }

    func defaults(for provider: CommandProvider, deadline: ContinuousClock.Instant) async -> ProviderOperationResult<[CommandResult]> {
        let startedAt = Date().timeIntervalSinceReferenceDate
        let outcome = await race(providerID: provider.id, operationKey: "defaults", {
            try await provider.defaultResults()
        }, until: deadline)
        let elapsedMilliseconds = (Date().timeIntervalSinceReferenceDate - startedAt) * 1_000
        await record(outcome.status, providerID: provider.id, elapsedMilliseconds: elapsedMilliseconds, resultCount: outcome.value?.count ?? 0)
        return outcome
    }

    private func results(
        from provider: CommandProvider,
        query: String,
        aliases: [String: [String]],
        sensitivity: SearchSensitivity,
        aliasKey: String,
        deadline: ContinuousClock.Instant
    ) async -> ProviderOperationResult<[CommandResult]> {
        let operationKey = "search:\(query)|\(sensitivity.rawValue)|\(aliasKey)"
        return await race(providerID: provider.id, operationKey: operationKey, {
            try await provider.search(CommandSearchRequest(
                query: query,
                customAliases: aliases,
                sensitivity: sensitivity,
                deadline: deadline
            ))
        }, until: deadline)
    }

    private func race(
        providerID: String,
        operationKey: String,
        _ work: @escaping @Sendable () async throws -> [CommandResult],
        until deadline: ContinuousClock.Instant
    ) async -> ProviderOperationResult<[CommandResult]> {
        let gate = executionGate(for: providerID)
        guard let operationTask = await gate.task(for: operationKey, work: {
            do {
                return .success(try await work())
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failed(error.localizedDescription)
            }
        }) else {
            return .busy
        }

        let race = FirstResultRace<ProviderOperationResult<[CommandResult]>>()
        let watcher = Task {
            race.finish(await operationTask.value)
        }
        let timeout = Task {
            let remaining = ContinuousClock().now.duration(to: deadline)
            if remaining > .zero {
                try? await Task.sleep(for: remaining)
            }
            race.finish(.timedOut)
        }
        let result = await withTaskCancellationHandler {
            await race.wait()
        } onCancel: {
            race.finish(.cancelled)
        }
        watcher.cancel()
        timeout.cancel()
        return result ?? .cancelled
    }

    private func executionGate(for providerID: String) -> ProviderExecutionGate {
        gateLock.withLock {
            if let gate = providerGates[providerID] {
                return gate
            }
            let gate = ProviderExecutionGate()
            providerGates[providerID] = gate
            return gate
        }
    }

    private func record(
        _ status: ProviderCallStatus,
        providerID: String,
        elapsedMilliseconds: Double,
        resultCount: Int
    ) async {
        switch status {
        case .success:
            await providerHealth.recordRequest(
                providerID: providerID,
                elapsedMilliseconds: elapsedMilliseconds,
                resultCount: resultCount
            )
        case let .failed(message):
            await providerHealth.recordFailure(providerID: providerID, message: message)
        case .timedOut:
            await providerHealth.recordTimeout(
                providerID: providerID,
                message: "Provider timed out after \(String(format: "%.0f", elapsedMilliseconds))ms"
            )
        case .cancelled:
            await providerHealth.recordCancellation(providerID: providerID)
        case .busy:
            break
        }
    }
}

struct RankCandidate {
    let result: CommandResult
    let providerID: String
    let sourceOrder: Int
}

enum ProviderCallStatus: Sendable, Equatable {
    case success
    case timedOut
    case cancelled
    case busy
    case failed(String)
}

struct ProviderOperationResult<Value: Sendable>: Sendable {
    let value: Value?
    let status: ProviderCallStatus

    static func success(_ value: Value) -> Self {
        Self(value: value, status: .success)
    }

    static var timedOut: Self { Self(value: nil, status: .timedOut) }
    static var cancelled: Self { Self(value: nil, status: .cancelled) }
    static var busy: Self { Self(value: nil, status: .busy) }

    static func failed(_ message: String) -> Self {
        Self(value: nil, status: .failed(message))
    }
}

struct ProviderSearchResult: Sendable {
    let providerID: String
    let results: [CommandResult]
    let elapsedMilliseconds: Double
    let status: ProviderCallStatus
}

struct ProviderSearchTiming: Sendable {
    let providerID: String
    let elapsedMilliseconds: Double
    let status: ProviderCallStatus
}

final class FirstResultRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?
    private var finished = false
    private var finishedValue: Value?

    func wait() async -> Value? {
        await withCheckedContinuation { continuation in
            let state = lock.withLock { () -> (shouldResume: Bool, value: Value?) in
                if finished { return (true, finishedValue) }
                self.continuation = continuation
                return (false, nil)
            }
            if state.shouldResume {
                continuation.resume(returning: state.value)
            }
        }
    }

    func finish(_ value: Value?) {
        let continuation = lock.withLock { () -> CheckedContinuation<Value?, Never>? in
            guard finished == false else { return nil }
            finished = true
            finishedValue = value
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: value)
    }
}

private actor ProviderExecutionGate {
    private var inFlight: [String: Task<ProviderOperationResult<[CommandResult]>, Never>] = [:]

    func task(
        for key: String,
        work: @escaping @Sendable () async -> ProviderOperationResult<[CommandResult]>
    ) -> Task<ProviderOperationResult<[CommandResult]>, Never>? {
        if let existing = inFlight[key] {
            return existing
        }
        guard inFlight.isEmpty else { return nil }

        let task = Task.detached { [self] in
            let result = await work()
            await self.finish(key: key)
            return result
        }
        inFlight[key] = task
        return task
    }

    private func finish(key: String) {
        inFlight.removeValue(forKey: key)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
