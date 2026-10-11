import Foundation

/// Typed access to the machine-local slice of FoundryConfig — the values
/// that used to be scattered across UserDefaults keys (main browser,
/// consent flags, feature recents). `shared` is bound to the app's
/// ConfigService at launch; stores created without a service keep an
/// in-memory snapshot so tests and standalone tools stay isolated.
final class LocalStateStore: @unchecked Sendable {
    static let shared = LocalStateStore()

    private let lock = NSLock()
    private var service: ConfigService?
    private var standalone = FoundryLocalState()

    init(service: ConfigService? = nil) {
        self.service = service
    }

    /// Point a store at the app's ConfigService. Call on `shared` once at
    /// launch, before any consumer reads — writes made while unbound stay
    /// in memory and are discarded.
    func bind(to service: ConfigService) {
        lock.withLock { self.service = service }
    }

    /// Current values — a copy; write through `set`/`update`.
    var snapshot: FoundryLocalState {
        lock.withLock { service?.current.localState ?? standalone }
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
        lock.lock()
        guard let service else {
            mutate(&standalone)
            lock.unlock()
            return true
        }
        lock.unlock()
        do {
            try service.updateLocalState(mutate)
            return true
        } catch {
            return false
        }
    }
}
