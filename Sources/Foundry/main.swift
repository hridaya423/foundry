import AppKit
import Darwin
import Foundation
import ServiceManagement

if CommandLine.arguments.contains("--firefox-native-host") {
    FirefoxNativeHost.run()
    exit(EXIT_SUCCESS)
}

if Bundle.main.bundleIdentifier == "com.hridya.foundry" {
    let currentPID = ProcessInfo.processInfo.processIdentifier
    let existingInstances = NSRunningApplication.runningApplications(withBundleIdentifier: "com.hridya.foundry")
        .filter { $0.processIdentifier != currentPID }
    if let existingInstance = existingInstances.first {
        existingInstance.activate(options: [.activateAllWindows])
        exit(EXIT_SUCCESS)
    }
}

if Bundle.main.bundleURL.pathExtension != "app" {
    // A previous source-run build could have registered the debug executable
    // as a login item. Remove that stale registration before building the app.
    try? SMAppService.mainApp.unregister()
    let build = Process()
    build.executableURL = URL(fileURLWithPath: "/bin/zsh")
    build.arguments = ["-lc", "./scripts/build-app.sh"]
    do {
        try build.run()
        build.waitUntilExit()
    } catch {
        fputs("Failed to run build-app.sh: \(error.localizedDescription)\n", stderr)
    }
    exit(EXIT_SUCCESS)
}

let app = NSApplication.shared
let delegate = AppDelegate()

app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
