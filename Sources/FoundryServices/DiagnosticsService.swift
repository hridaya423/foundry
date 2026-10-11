import Foundation
import os

public final class DiagnosticsService: Sendable {
    public struct Span: Sendable {
        let name: String
        let start: ContinuousClock.Instant
        let signpostID: OSSignpostID
    }

    private let logger = Logger(subsystem: "app.foundry.prototype", category: "Foundry")
    private let signpostLog = OSLog(subsystem: "app.foundry.prototype", category: .pointsOfInterest)
    private let clock = ContinuousClock()

    public init() {}

    public func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    /// Point-in-time signpost for correlating spans with UI commits
    /// (e.g. "results.committed", "panel.firstFrame"). Shows in
    /// `log stream --predicate 'subsystem == "app.foundry.prototype"'`
    /// and Instruments points-of-interest.
    public func mark(_ name: String) {
        os_signpost(.event, log: signpostLog, name: "FoundryMark", "%{public}s", name)
    }

    public func startSpan(_ name: String) -> Span {
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: "FoundrySpan", signpostID: signpostID, "%{public}s", name)
        return Span(name: name, start: clock.now, signpostID: signpostID)
    }

    public func endSpan(_ span: Span) {
        let duration = span.start.duration(to: clock.now)
        os_signpost(.end, log: signpostLog, name: "FoundrySpan", signpostID: span.signpostID, "%{public}s", span.name)
        logger.debug("\(span.name, privacy: .public) completed in \(String(describing: duration), privacy: .public)")
    }

    public func discardSpan(_ span: Span) {
        os_signpost(.end, log: signpostLog, name: "FoundrySpan", signpostID: span.signpostID, "%{public}s", span.name)
    }
}
