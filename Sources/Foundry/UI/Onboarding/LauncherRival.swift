import AppKit
import Foundation
import FoundryServices

/// Another launcher that can hold ⌘ Space. Foundry frees the chord by moving
/// the rival to ⌥ Space, the default both Raycast and Alfred ship with.
struct LauncherRival: Identifiable, Sendable {
    let id: String
    let name: String
    let bundleID: String
    /// Whether the rival's saved hotkey is ⌘ Space.
    let holdsCommandSpace: @Sendable () -> Bool
    /// Rewrites the saved hotkey to ⌥ Space. Runs while the rival is quit,
    /// because a running app writes its in-memory hotkey back on quit.
    let moveToOptionSpace: @Sendable () -> Bool

    static var all: [LauncherRival] { [.raycast(), .alfred()] }

    /// Quits the rival if it is running, rewrites its hotkey, and relaunches it.
    @MainActor
    func release() async -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in running { app.terminate() }
        for _ in 0..<30 where running.contains(where: { $0.isTerminated == false }) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard running.allSatisfy(\.isTerminated), moveToOptionSpace() else { return false }
        if running.isEmpty == false, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
        }
        return true
    }

    /// Raycast keeps its hotkey as `Modifier-keyCode` in its own defaults domain.
    static func raycast(suiteName: String = "com.raycast.macos") -> LauncherRival {
        let key = "raycastGlobalHotkey"
        return LauncherRival(
            id: "raycast", name: "Raycast", bundleID: "com.raycast.macos",
            holdsCommandSpace: { UserDefaults(suiteName: suiteName)?.string(forKey: key) == "Command-49" },
            moveToOptionSpace: {
                guard let defaults = UserDefaults(suiteName: suiteName) else { return false }
                defaults.set("Option-49", forKey: key)
                return defaults.synchronize()
            })
    }

    /// Alfred keeps its hotkey in `preferences/local/<machine>/hotkey/prefs.plist`
    /// inside its preferences bundle, which may live in a sync folder.
    static func alfred(preferencesRoot: URL? = alfredPreferencesRoot()) -> LauncherRival {
        let commandMask = Int(NSEvent.ModifierFlags.command.rawValue)
        let optionMask = Int(NSEvent.ModifierFlags.option.rawValue)
        @Sendable func hotkeyFiles() -> [URL] {
            guard let local = preferencesRoot?.appendingPathComponent("preferences/local") else { return [] }
            return (FileManager.default.contentsOfDirectoryIfPresent(at: local) ?? [])
                .map { $0.appendingPathComponent("hotkey/prefs.plist") }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        @Sendable func holds(_ prefs: NSDictionary) -> Bool {
            prefs["key"] as? Int == 49 && prefs["mod"] as? Int == commandMask
        }
        return LauncherRival(
            id: "alfred", name: "Alfred", bundleID: "com.runningwithcrayons.Alfred",
            holdsCommandSpace: { hotkeyFiles().contains { NSDictionary(contentsOf: $0).map(holds) ?? false } },
            moveToOptionSpace: {
                hotkeyFiles().allSatisfy { url in
                    guard let prefs = NSMutableDictionary(contentsOf: url), holds(prefs) else { return true }
                    prefs["mod"] = optionMask
                    return BestEffort.attempt("rewrite Alfred hotkey") { try prefs.write(to: url) } != nil
                }
            })
    }

    static func alfredPreferencesRoot() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let synced = UserDefaults(suiteName: "com.runningwithcrayons.Alfred-Preferences")?.string(forKey: "syncfolder")
        let folder = synced.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? home.appendingPathComponent("Library/Application Support/Alfred")
        return folder.appendingPathComponent("Alfred.alfredpreferences")
    }
}
