import AppKit
import Darwin
import Foundation
import ServiceManagement

// Vars like ELECTRON_RUN_AS_NODE leak in when Foundry is started from an
// Electron-hosted shell (e.g. Devin CLI, VS Code terminal). LaunchServices and
// Process both propagate the caller's environment to children, so every app
// Foundry opens would inherit them — ELECTRON_RUN_AS_NODE makes Electron apps
// boot as plain node and never load. Strip the host's vars once at startup.
for key in ProcessInfo.processInfo.environment.keys {
    if key.hasPrefix("ELECTRON_") || key.hasPrefix("VSCODE_") || key == "ATOM_SHELL_INTERNAL_RUN_AS_NODE" {
        unsetenv(key)
    }
}

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

#if DEBUG
if Bundle.main.bundleURL.pathExtension != "app" {
    try? SMAppService.mainApp.unregister()
    guard let sourceRoot = SourceRootLocator.locate() else {
        fputs("Foundry source root is unavailable\n", stderr)
        exit(EXIT_FAILURE)
    }
    let build = Process()
    build.executableURL = URL(fileURLWithPath: "/bin/zsh")
    build.currentDirectoryURL = sourceRoot
    build.arguments = ["-lc", "./scripts/build-app.sh"]
    build.environment = ProcessInfo.processInfo.environment.merging([
        "INSTALL_APP": "1",
        "LAUNCH_APP": "1",
    ]) { _, sourceRunValue in sourceRunValue }
    do {
        try build.run()
        build.waitUntilExit()
        exit(build.terminationStatus == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
    } catch {
        fputs("Failed to run build-app.sh: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}
#endif

let app = NSApplication.shared
let delegate = AppDelegate()

app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
