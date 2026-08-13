import AppKit
import Darwin
import Foundation
import ServiceManagement

if let bridgeIndex = CommandLine.arguments.firstIndex(of: "--agent-bridge"),
   bridgeIndex + 1 < CommandLine.arguments.count,
   let provider = AgentBridgeProvider(rawValue: CommandLine.arguments[bridgeIndex + 1]) {
    AgentHookBridge.run(provider: provider)
    exit(EXIT_SUCCESS)
}

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
    try? SMAppService.mainApp.unregister()
    let build = Process()
    build.executableURL = URL(fileURLWithPath: "/bin/zsh")
    build.arguments = ["-lc", "./scripts/build-app.sh"]
    build.environment = ProcessInfo.processInfo.environment.merging([
        "INSTALL_APP": "1",
        "LAUNCH_APP": "1",
    ]) { _, sourceRunValue in sourceRunValue }
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
