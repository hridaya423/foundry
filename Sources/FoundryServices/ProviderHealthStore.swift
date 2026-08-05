import Foundation
import FoundryDomain

public actor ProviderHealthStore {
    private struct Metrics {
        var requestCount = 0
        var successCount = 0
        var failureCount = 0
        var timeoutCount = 0
        var cancellationCount = 0
        var emptyResponseCount = 0
        var latencies: [Double] = []
        var lastFailure: String?
        var lastFailureAt: Date?
        var permissionState: ProviderPermissionState = .unknown
    }

    private var metrics: [String: Metrics] = [:]

    public init() {}

    public func recordRequest(providerID: String, elapsedMilliseconds: Double, resultCount: Int) {
        var value = metrics[providerID, default: Metrics()]
        value.requestCount += 1
        value.successCount += 1
        if resultCount == 0 {
            value.emptyResponseCount += 1
        }
        value.latencies.append(max(0, elapsedMilliseconds))
        if value.latencies.count > 200 {
            value.latencies.removeFirst(value.latencies.count - 200)
        }
        metrics[providerID] = value
    }

    public func recordFailure(providerID: String, message: String) {
        var value = metrics[providerID, default: Metrics()]
        value.requestCount += 1
        value.failureCount += 1
        value.lastFailure = message
        value.lastFailureAt = Date()
        metrics[providerID] = value
    }

    public func recordTimeout(providerID: String, message: String) {
        var value = metrics[providerID, default: Metrics()]
        value.requestCount += 1
        value.failureCount += 1
        value.timeoutCount += 1
        value.lastFailure = message
        value.lastFailureAt = Date()
        metrics[providerID] = value
    }

    public func recordCancellation(providerID: String) {
        var value = metrics[providerID, default: Metrics()]
        value.requestCount += 1
        value.cancellationCount += 1
        metrics[providerID] = value
    }

    public func setPermissionState(_ state: ProviderPermissionState, for providerID: String) {
        var value = metrics[providerID, default: Metrics()]
        value.permissionState = state
        metrics[providerID] = value
    }

    public func snapshot(for providerID: String) -> ProviderHealthSnapshot {
        let value = metrics[providerID, default: Metrics()]
        return ProviderHealthSnapshot(
            providerID: providerID,
            requestCount: value.requestCount,
            successCount: value.successCount,
            failureCount: value.failureCount,
            timeoutCount: value.timeoutCount,
            cancellationCount: value.cancellationCount,
            emptyResponseCount: value.emptyResponseCount,
            latencyP50Milliseconds: Self.percentile(value.latencies, percentile: 0.50),
            latencyP95Milliseconds: Self.percentile(value.latencies, percentile: 0.95),
            lastFailure: value.lastFailure,
            lastFailureAt: value.lastFailureAt,
            permissionState: value.permissionState
        )
    }

    public func snapshots(for providerIDs: [String]) -> [String: ProviderHealthSnapshot] {
        Dictionary(uniqueKeysWithValues: providerIDs.map { ($0, snapshot(for: $0)) })
    }

    private static func percentile(_ values: [Double], percentile: Double) -> Double? {
        guard values.isEmpty == false else { return nil }
        let sorted = values.sorted()
        let position = Double(sorted.count - 1) * percentile
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = min(sorted.count - 1, lowerIndex + 1)
        let fraction = position - Double(lowerIndex)
        return sorted[lowerIndex] + (sorted[upperIndex] - sorted[lowerIndex]) * fraction
    }
}
