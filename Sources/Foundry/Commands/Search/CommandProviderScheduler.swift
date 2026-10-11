import Foundation
import FoundryDomain
import FoundryServices
import os

final class CommandProviderScheduler: Sendable {
    private let diagnostics: DiagnosticsService
    private let providerGates = OSAllocatedUnfairLock(initialState: [String: ProviderExecutionGate]())

    init(diagnostics: DiagnosticsService) {
        self.diagnostics = diagnostics
    }

    func search(
        query: String,
        providers: [CommandProvider],
        aliases: [String: [String]],
        sensitivity: SearchSensitivity,
        snippetInsertAsPrimary: Bool = true,
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
                    let deadline = ContinuousClock().now.advanced(by: provider.searchTimeout ?? timeout)
                    let outcome = await self.results(
                        from: provider,
                        query: query,
                        aliases: aliases,
                        sensitivity: sensitivity,
                        snippetInsertAsPrimary: snippetInsertAsPrimary,
                        aliasKey: aliasKey,
                        deadline: deadline
                    )
                    let elapsedMilliseconds = (Date().timeIntervalSinceReferenceDate - startedAt) * 1_000
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
        await race(providerID: provider.id, operationKey: "defaults", {
            try await provider.defaultResults()
        }, until: deadline)
    }

    private func results(
        from provider: CommandProvider,
        query: String,
        aliases: [String: [String]],
        sensitivity: SearchSensitivity,
        snippetInsertAsPrimary: Bool,
        aliasKey: String,
        deadline: ContinuousClock.Instant
    ) async -> ProviderOperationResult<[CommandResult]> {
        let operationKey = "search:\(query)|\(sensitivity.rawValue)|\(snippetInsertAsPrimary)|\(aliasKey)"
        return await race(providerID: provider.id, operationKey: operationKey, {
            try await provider.search(CommandSearchRequest(
                query: query,
                customAliases: aliases,
                sensitivity: sensitivity,
                snippetInsertAsPrimary: snippetInsertAsPrimary
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
        }, until: deadline) else {
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
        providerGates.withLock {
            if let gate = $0[providerID] {
                return gate
            }
            let gate = ProviderExecutionGate()
            $0[providerID] = gate
            return gate
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

final class FirstResultRace<Value: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Value?, Never>?
        var finished = false
        var finishedValue: Value?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func wait() async -> Value? {
        await withCheckedContinuation { continuation in
            let resolved = state.withLock { state -> (shouldResume: Bool, value: Value?) in
                if state.finished { return (true, state.finishedValue) }
                state.continuation = continuation
                return (false, nil)
            }
            if resolved.shouldResume {
                continuation.resume(returning: resolved.value)
            }
        }
    }

    func finish(_ value: Value?) {
        let continuation = state.withLock { state -> CheckedContinuation<Value?, Never>? in
            guard state.finished == false else { return nil }
            state.finished = true
            state.finishedValue = value
            let continuation = state.continuation
            state.continuation = nil
            return continuation
        }
        continuation?.resume(returning: value)
    }
}

private actor ProviderExecutionGate {
    private var inFlight: [String: Task<ProviderOperationResult<[CommandResult]>, Never>] = [:]

    func task(
        for key: String,
        work: @escaping @Sendable () async -> ProviderOperationResult<[CommandResult]>,
        until deadline: ContinuousClock.Instant
    ) async -> Task<ProviderOperationResult<[CommandResult]>, Never>? {
        guard Task.isCancelled == false else { return nil }
        if let existing = inFlight[key] {
            return existing
        }
        if let existing = inFlight.values.first {
            existing.cancel()
            guard await waitForCompletion(of: existing, until: deadline), inFlight.isEmpty else { return nil }
            guard Task.isCancelled == false else { return nil }
        }

        let task = Task.detached { [self] in
            let result = await work()
            await self.finish(key: key)
            return result
        }
        inFlight[key] = task
        return task
    }

    private func waitForCompletion(
        of task: Task<ProviderOperationResult<[CommandResult]>, Never>,
        until deadline: ContinuousClock.Instant
    ) async -> Bool {
        let race = FirstResultRace<Bool>()
        let watcher = Task {
            _ = await task.value
            race.finish(true)
        }
        let timeout = Task {
            let remaining = ContinuousClock().now.duration(to: deadline)
            if remaining > .zero { try? await Task.sleep(for: remaining) }
            race.finish(false)
        }
        let completed = await race.wait() ?? false
        watcher.cancel()
        timeout.cancel()
        return completed
    }

    private func finish(key: String) {
        inFlight.removeValue(forKey: key)
    }
}
