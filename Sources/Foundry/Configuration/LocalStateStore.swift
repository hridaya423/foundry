import Foundation
import os

/// Typed access to the machine-local slice of FoundryConfig — the values
/// that used to be scattered across UserDefaults keys (main browser,
/// consent flags, feature recents). `shared` is bound to the app's
/// ConfigService at launch; stores created without a service keep an
/// in-memory snapshot so tests and standalone tools stay isolated.
final class LocalStateStore: Sendable {
    static let shared = LocalStateStore()

    private struct State {
        var service: ConfigService?
        var standalone = FoundryLocalState()
    }

    private let state: OSAllocatedUnfairLock<State>

    init(service: ConfigService? = nil) {
        self.state = OSAllocatedUnfairLock(initialState: State(service: service))
    }

    /// Point a store at the app's ConfigService. Call on `shared` once at
    /// launch, before any consumer reads — writes made while unbound stay
    /// in memory and are discarded.
    func bind(to service: ConfigService) {
        state.withLock { $0.service = service }
    }

    /// Current values — a copy; write through `set`/`update`.
    var snapshot: FoundryLocalState {
        state.withLock { $0.service?.current.localState ?? $0.standalone }
    }

    func get<Value>(_ keyPath: KeyPath<FoundryLocalState, Value>) -> Value {
        snapshot[keyPath: keyPath]
    }

    @discardableResult
    func set<Value>(_ keyPath: WritableKeyPath<FoundryLocalState, Value>, _ value: Value) -> Bool {
        update { $0[keyPath: keyPath] = value }
    }

    /// Returns false when the bound service is read-only (corrupt config) —
    /// callers that must persist should surface that via diagnostics.
    @discardableResult
    func update(_ mutate: (inout FoundryLocalState) -> Void) -> Bool {
        let service: ConfigService? = state.withLockUnchecked { state in
            guard let service = state.service else {
                mutate(&state.standalone)
                return nil
            }
            return service
        }
        guard let service else { return true }
        do {
            try service.updateLocalState(mutate)
            return true
        } catch {
            return false
        }
    }
}
