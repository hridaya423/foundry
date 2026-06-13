import Foundation

final class IndexingStatusStore: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [String: String] = [:]

    func setStatus(_ status: String?, for providerID: String) {
        lock.lock()
        if let status {
            statuses[providerID] = status
        } else {
            statuses.removeValue(forKey: providerID)
        }
        lock.unlock()
    }

    func summary() -> String? {
        lock.lock()
        let values = statuses.values.sorted()
        lock.unlock()
        guard values.isEmpty == false else { return nil }
        return values.joined(separator: " · ")
    }
}
