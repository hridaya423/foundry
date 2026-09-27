import AppKit
import Foundation

enum RunningAppsSnapshot {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: (all: Set<String>, regular: Set<String>, at: Date)?

    static func bundleIDs(regularOnly: Bool = false, ttl: TimeInterval = 2) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        if let cached, Date().timeIntervalSince(cached.at) < ttl {
            return regularOnly ? cached.regular : cached.all
        }
        let apps = NSWorkspace.shared.runningApplications
        let all = Set(apps.compactMap(\.bundleIdentifier))
        let regular = Set(apps.filter { $0.activationPolicy == .regular }.compactMap(\.bundleIdentifier))
        cached = (all, regular, Date())
        return regularOnly ? regular : all
    }
}
