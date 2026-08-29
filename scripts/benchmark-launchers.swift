#!/usr/bin/env swift

import AppKit
import Carbon
import CoreGraphics
import Foundation

struct Launcher {
    let name: String
    let bundleIdentifier: String
    let bundleURL: URL
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

struct Summary: Codable {
    let minimum: Double
    let p50: Double
    let p95: Double
    let maximum: Double
    let mean: Double
}

struct LauncherResult: Codable {
    let name: String
    let version: String
    let bundleKilobytes: Int
    let panelLatencyMilliseconds: Summary
    let idleRSSMegabytes: Summary
    let panelSamplesMilliseconds: [Double]
    let rssSamplesMegabytes: [Double]
}

struct BenchmarkResult: Codable {
    let capturedAt: String
    let hardware: String
    let macOS: String
    let warmupRuns: Int
    let measuredRuns: Int
    let launchers: [LauncherResult]
}

let arguments = CommandLine.arguments
let measuredRuns = value(after: "--runs", in: arguments).flatMap(Int.init) ?? 30
let warmupRuns = value(after: "--warmups", in: arguments).flatMap(Int.init) ?? 5
let memorySamples = value(after: "--memory-samples", in: arguments).flatMap(Int.init) ?? 15

let configuredLaunchers = [
    Launcher(
        name: "Foundry",
        bundleIdentifier: "com.hridya.foundry",
        bundleURL: URL(fileURLWithPath: "/Applications/Foundry.app"),
        keyCode: CGKeyCode(kVK_Space),
        flags: .maskCommand
    ),
    Launcher(
        name: "Raycast",
        bundleIdentifier: "com.raycast.macos",
        bundleURL: URL(fileURLWithPath: "/Applications/Raycast.app"),
        keyCode: 47,
        flags: .maskCommand
    )
]
let launchers = arguments.contains("--reverse") ? Array(configuredLaunchers.reversed()) : configuredLaunchers

guard measuredRuns > 0, warmupRuns >= 0, memorySamples > 0 else {
    fatalError("Runs and memory samples must be positive")
}

for launcher in launchers where FileManager.default.fileExists(atPath: launcher.bundleURL.path) == false {
    fatalError("Missing \(launcher.bundleURL.path)")
}

let results = launchers.map { launcher in
    ensureRunning(launcher)
    Thread.sleep(forTimeInterval: 5)
    ensureHidden(launcher)

    for _ in 0..<warmupRuns {
        _ = measurePanel(launcher)
    }

    let panelSamples = (0..<measuredRuns).map { _ in measurePanel(launcher) }
    let rssSamples = (0..<memorySamples).compactMap { _ -> Double? in
        defer { Thread.sleep(forTimeInterval: 1) }
        return residentMemoryMegabytes(bundleURL: launcher.bundleURL)
    }

    return LauncherResult(
        name: launcher.name,
        version: bundleVersion(launcher.bundleURL),
        bundleKilobytes: bundleKilobytes(launcher.bundleURL),
        panelLatencyMilliseconds: summary(panelSamples),
        idleRSSMegabytes: summary(rssSamples),
        panelSamplesMilliseconds: panelSamples,
        rssSamplesMegabytes: rssSamples
    )
}

let formatter = ISO8601DateFormatter()
let report = BenchmarkResult(
    capturedAt: formatter.string(from: Date()),
    hardware: shell("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]).trimmingCharacters(in: .whitespacesAndNewlines),
    macOS: shell("/usr/bin/sw_vers", ["-productVersion"]).trimmingCharacters(in: .whitespacesAndNewlines),
    warmupRuns: warmupRuns,
    measuredRuns: measuredRuns,
    launchers: results
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(report))
FileHandle.standardOutput.write(Data("\n".utf8))

func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

func ensureRunning(_ launcher: Launcher) {
    if NSRunningApplication.runningApplications(withBundleIdentifier: launcher.bundleIdentifier).isEmpty == false { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    let semaphore = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: launcher.bundleURL, configuration: configuration) { _, error in
        if let error { fputs("Could not open \(launcher.name): \(error)\n", stderr) }
        semaphore.signal()
    }
    semaphore.wait()
}

func measurePanel(_ launcher: Launcher) -> Double {
    ensureHidden(launcher)
    Thread.sleep(forTimeInterval: 0.2)

    let start = ContinuousClock.now
    postKey(code: launcher.keyCode, flags: launcher.flags)
    guard wait(until: { windowIsVisible(owner: launcher.name) }, timeout: 2) else {
        fatalError("\(launcher.name) did not show a window")
    }
    let milliseconds = durationMilliseconds(start.duration(to: .now))

    Thread.sleep(forTimeInterval: 0.3)
    hide(launcher)
    return milliseconds
}

func ensureHidden(_ launcher: Launcher) {
    guard windowIsVisible(owner: launcher.name) else { return }
    hide(launcher)
}

func hide(_ launcher: Launcher) {
    for _ in 0..<3 {
        postKey(code: launcher.keyCode, flags: launcher.flags)
        if wait(until: { windowIsVisible(owner: launcher.name) == false }, timeout: 0.75) { return }
        Thread.sleep(forTimeInterval: 0.2)
    }
    fatalError("\(launcher.name) did not hide its window")
}

func postKey(code: CGKeyCode, flags: CGEventFlags) {
    let source = CGEventSource(stateID: .hidSystemState)
    for isDown in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown) else { continue }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        if isDown { usleep(1_000) }
    }
}

func windowIsVisible(owner: String) -> Bool {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains { window in
        window[kCGWindowOwnerName as String] as? String == owner
            && (window[kCGWindowAlpha as String] as? Double ?? 1) > 0
            && (window[kCGWindowLayer as String] as? Int ?? 0) >= 0
    }
}

func wait(until condition: () -> Bool, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        usleep(500)
    }
    return condition()
}

func residentMemoryMegabytes(bundleURL: URL) -> Double? {
    let output = shell("/bin/ps", ["-axo", "rss=,command="])
    let prefix = bundleURL.path + "/Contents/"
    let kilobytes = output.split(separator: "\n").reduce(0) { total, line in
        let fields = line.split(maxSplits: 1, whereSeparator: \Character.isWhitespace)
        guard fields.count == 2, fields[1].contains(prefix), let rss = Int(fields[0]) else { return total }
        return total + rss
    }
    return kilobytes > 0 ? Double(kilobytes) / 1024 : nil
}

func bundleVersion(_ url: URL) -> String {
    Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
}

func bundleKilobytes(_ url: URL) -> Int {
    let output = shell("/usr/bin/du", ["-sk", url.path])
    return output.split(whereSeparator: \Character.isWhitespace).first.flatMap { Int($0) } ?? 0
}

func shell(_ executable: String, _ arguments: [String]) -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    try! process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

func summary(_ values: [Double]) -> Summary {
    precondition(values.isEmpty == false)
    let sorted = values.sorted()
    return Summary(
        minimum: sorted[0],
        p50: percentile(sorted, 0.50),
        p95: percentile(sorted, 0.95),
        maximum: sorted[sorted.count - 1],
        mean: values.reduce(0, +) / Double(values.count)
    )
}

func percentile(_ sorted: [Double], _ percentile: Double) -> Double {
    let index = Int((Double(sorted.count - 1) * percentile).rounded(.up))
    return sorted[min(max(index, 0), sorted.count - 1)]
}

func durationMilliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
}
