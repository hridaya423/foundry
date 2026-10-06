import AppKit
import Darwin

@MainActor
enum DownloadNotice {
    static let shownKey = "foundry.downloadedNoticeShown"

    private static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    private static var isQuarantined: Bool {
        Bundle.main.bundlePath.withCString { getxattr($0, "com.apple.quarantine", nil, 0, 0, 0) >= 0 }
    }

    static func showIfNeeded(defaults: UserDefaults = .standard) {
        if isTranslocated {
            showTranslocatedAlert()
            return
        }
        guard isQuarantined, defaults.bool(forKey: shownKey) == false else { return }
        let alert = NSAlert()
        alert.messageText = "Foundry isn't notarized yet"
        alert.informativeText = "You downloaded Foundry directly, so macOS may warn that the developer can't be verified. That's expected for this build — if it refuses to open now or after an update, go to System Settings → Privacy & Security → Security → Open Anyway."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Privacy & Security")
        if alert.runModal() == .alertSecondButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") {
            NSWorkspace.shared.open(url)
        }
        defaults.set(true, forKey: shownKey)
    }

    private static func showTranslocatedAlert() {
        let alert = NSAlert()
        alert.messageText = "Move Foundry to Applications"
        alert.informativeText = "You're running Foundry straight from the disk image, so macOS is keeping it in a temporary sandbox. Features like launch at login won't work until it's installed. Quit, drag Foundry into Applications from the DMG window, then open it again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Continue Anyway")
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }
}
