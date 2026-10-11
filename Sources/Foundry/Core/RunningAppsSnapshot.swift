import AppKit
import Foundation
import os

enum RunningAppsSnapshot {
    private static let cached = OSAllocatedUnfairLock<(all: Set<String>, regular: Set<String>, at: Date)?>(initialState: nil)

    static func bundleIDs(regularOnly: Bool = false, ttl: TimeInterval = 2) -> Set<String> {
        cached.withLock { cached in
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
}
