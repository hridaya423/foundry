import Foundation
import os

final class DiagnosticsService: @unchecked Sendable {
    struct Span {
        let name: String
        let start: ContinuousClock.Instant
    }

    private let logger = Logger(subsystem: "app.foundry.prototype", category: "Foundry")
    private let clock = ContinuousClock()

    func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
        fputs("[Foundry] \(message)\n", stderr)
    }

    func startSpan(_ name: String) -> Span {
        Span(name: name, start: clock.now)
    }

    func endSpan(_ span: Span) {
        let duration = span.start.duration(to: clock.now)
        logger.debug("\(span.name, privacy: .public) completed in \(String(describing: duration), privacy: .public)")
    }
}
