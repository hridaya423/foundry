import Foundation
import os

public final class DiagnosticsService: @unchecked Sendable {
    public struct Span {
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
}
