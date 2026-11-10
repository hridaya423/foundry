import AppKit

/// AppKit activation seam so the shell's focus lifecycle can be driven and
/// asserted without a real running app graph.
@MainActor
protocol AppActivation {
    func activate()
    func deactivate()
    var isActive: Bool { get }
}

struct NSAppActivation: AppActivation {
    func activate() {
        NSApp.activate()
    }

    /// Hides the app and returns focus to whatever was frontmost before
    /// Foundry activated — the contract a launcher owes the user on dismiss.
    func deactivate() {
        NSApp.hide(nil)
    }

    var isActive: Bool { NSApp.isActive }
}
