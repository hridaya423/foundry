import Foundation
import os

/// Named swallow for best-effort work. Use where "absent" and "broken"
/// legitimately collapse to the same outcome — a missing file, a corrupt
/// cache, an optional sidecar — but the failure should still be visible in
/// the diagnostics log instead of disappearing into `try?`.
///
/// Do NOT use for user-initiated writes (saves, exports, deletes) — those
/// must surface the error. Do not use for shape probes (trying alternative
/// Codable layouts) or cancellation — plain `try?` is honest there.
public enum BestEffort {
    private static let logger = Logger(subsystem: "app.foundry.prototype", category: "BestEffort")

    /// Runs `body`, returning nil and logging the error on failure.
    @discardableResult
    public static func attempt<T>(_ label: String, _ body: () throws -> T) -> T? {
        do { return try body() } catch {
            logger.error("\(label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Async variant of ``attempt(_:_:)``. `body` must be `@Sendable` —
    /// call sites that need to capture non-Sendable values (e.g.
    /// `NSItemProvider`) should write an explicit `do/catch` and call
    /// ``log(_:_:)`` instead.
    @discardableResult
    public static func attempt<T>(_ label: String, _ body: @Sendable () async throws -> T) async -> T? {
        do { return try await body() } catch {
            log(label, error)
            return nil
        }
    }

    /// Logs an error at `.error` level — for `catch` blocks at call sites
    /// that can't use ``attempt(_:_:)``.
    public static func log(_ label: String, _ error: any Error) {
        logger.error("\(label, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
}

extension URL {
    /// Non-throwing `resourceValues` probe for directory scans and display
    /// metadata: a file that vanishes mid-scan collapses to nil, same as
    /// missing attributes. Not logged — called at scan frequency.
    public func fileResourceValues(_ keys: Set<URLResourceKey>) -> URLResourceValues? {
        try? resourceValues(forKeys: keys)
    }
}

extension FileManager {
    /// Non-throwing `attributesOfItem` probe — returns nil for missing files
    /// the same as unreadable ones. For callers that only need presence or
    /// one attribute value.
    public func attributesIfPresent(atPath path: String) -> [FileAttributeKey: Any]? {
        try? attributesOfItem(atPath: path)
    }

    /// Non-throwing `contentsOfDirectory` probe for optional directories
    /// (script folders, backup roots). Returns nil when the directory is
    /// absent or unreadable.
    public func contentsOfDirectoryIfPresent(at url: URL, keys: [URLResourceKey]? = nil, options: FileManager.DirectoryEnumerationOptions = []) -> [URL]? {
        try? contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)
    }

    /// Path-based variant of ``contentsOfDirectoryIfPresent(at:keys:options:)``.
    public func contentsOfDirectoryIfPresent(atPath path: String) -> [String]? {
        try? contentsOfDirectory(atPath: path)
    }
}
