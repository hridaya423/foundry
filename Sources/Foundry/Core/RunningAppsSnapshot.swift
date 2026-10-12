import AppKit
import Foundation
import os

enum RunningAppsSnapshot {
    private static let cached = OSAllocatedUnfairLock<(all: Set<String>, regular: Set<String>, at: Date)?>(initialState: nil)
    private static let refreshing = OSAllocatedUnfairLock(initialState: false)

    /// Stale-while-revalidate: `NSWorkspace.runningApplications` costs
    /// ~10 ms on the main run loop, so a TTL miss refreshes in the
    /// background and serves the last snapshot instead of stalling search.
    static func bundleIDs(regularOnly: Bool = false, ttl: TimeInterval = 2) -> Set<String> {
        let (result, shouldRefresh) = cached.withLock { cached -> (Set<String>?, Bool) in
            guard let cached else { return (nil, true) }
            return (regularOnly ? cached.regular : cached.all, Date().timeIntervalSince(cached.at) >= ttl)
        }
        guard let result else {
            return refreshNow(regularOnly: regularOnly)
        }
        if shouldRefresh {
            let claimed = refreshing.withLock { fresh -> Bool in
                if fresh { return false }
                fresh = true
                return true
            }
            if claimed {
                Task.detached(priority: .utility) { _ = refreshNow(regularOnly: false) }
            }
        }
        return result
    }

    @discardableResult
    private static func refreshNow(regularOnly: Bool) -> Set<String> {
        let apps = NSWorkspace.shared.runningApplications
        let all = Set(apps.compactMap(\.bundleIdentifier))
        let regular = Set(apps.filter { $0.activationPolicy == .regular }.compactMap(\.bundleIdentifier))
        cached.withLock { $0 = (all, regular, Date()) }
        refreshing.withLock { $0 = false }
        return regularOnly ? regular : all
    }
}
