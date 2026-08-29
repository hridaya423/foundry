#!/usr/bin/env swift

import AppKit
import Carbon
import CoreGraphics
import Darwin
import Foundation

struct Launcher {
    let name: String
    let bundleIdentifier: String
    let bundleURL: URL
    let shortcut: Shortcut
    let includesDetachedWebKit: Bool
}

struct Shortcut {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
    let displayName: String
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
    let bundleIdentifier: String
    let version: String
    let build: String
    let hotkey: String
    let keyCode: UInt16
    let modifierFlags: UInt64
    let bundleKilobytes: Int
    let panelLatencyMilliseconds: Summary
    let warmedFootprintMegabytes: Summary
    let idleRSSMegabytes: Summary
    let panelSamples: [PanelSample]
    let memorySamples: [MemorySample]
}

struct PanelSample: Codable {
    let capturedAt: String
    let milliseconds: Double
}

struct ProcessSnapshot: Codable {
    let pid: Int
    let parentPID: Int
    let rssKilobytes: Int
    let elapsedSeconds: Int
    let command: String
    let ownership: String
}

struct MemorySample: Codable {
    let capturedAt: String
    let footprintMegabytes: Double
    let rssMegabytes: Double
    let processes: [ProcessSnapshot]
}

struct EnvironmentSnapshot: Codable {
    let powerSource: String
    let powerDetails: String
    let powerSettings: String
    let thermalDetails: String
}

struct BenchmarkResult: Codable {
    let startedAt: String
    let capturedAt: String
    let hardware: String
    let machineIdentifier: String
    let logicalCPUCount: Int
    let physicalMemoryBytes: UInt64
    let macOS: String
    let macOSBuild: String
    let systemAtStart: EnvironmentSnapshot
    let systemAtEnd: EnvironmentSnapshot
    let warmupRuns: Int
    let measuredRuns: Int
    let memorySampleCount: Int
    let startupWaitSeconds: Double
    let postPanelSettleSeconds: Double
    let memorySampleIntervalSeconds: Double
    let panelTimeoutSeconds: Double
    let panelPollMicroseconds: Int
    let panelMetric: String
    let memoryMetric: String
    let processSelection: String
    let processMinimumAgeSeconds: Int
    let processStabilitySeconds: Double
    let isolatedLaunchers: Bool
    let launchers: [LauncherResult]
}

let arguments = CommandLine.arguments
let measuredRuns = value(after: "--runs", in: arguments).flatMap(Int.init) ?? 30
let warmupRuns = value(after: "--warmups", in: arguments).flatMap(Int.init) ?? 5
let memorySampleCount = value(after: "--memory-samples", in: arguments).flatMap(Int.init) ?? 15
let startupWaitSeconds = value(after: "--startup-wait", in: arguments).flatMap(Double.init) ?? 10
let postPanelSettleSeconds = value(after: "--settle", in: arguments).flatMap(Double.init) ?? 2
let memorySampleIntervalSeconds = value(after: "--memory-interval", in: arguments).flatMap(Double.init) ?? 1
let processMinimumAgeSeconds = 5
let processStabilitySeconds = 0.1
let requireACPower = arguments.contains("--require-ac")
let isolateLaunchers = arguments.contains("--isolate")

let configuredLaunchers = [
    Launcher(
        name: "Foundry",
        bundleIdentifier: "com.hridya.foundry",
        bundleURL: URL(fileURLWithPath: "/Applications/Foundry.app"),
        shortcut: foundryShortcut(),
        includesDetachedWebKit: false
    ),
    Launcher(
        name: "Raycast",
        bundleIdentifier: "com.raycast.macos",
        bundleURL: URL(fileURLWithPath: "/Applications/Raycast.app"),
        shortcut: raycastShortcut(),
        includesDetachedWebKit: true
    )
]
let launchers = arguments.contains("--reverse") ? Array(configuredLaunchers.reversed()) : configuredLaunchers

guard measuredRuns > 0,
      warmupRuns >= 0,
      memorySampleCount > 0,
      startupWaitSeconds >= 0,
      postPanelSettleSeconds >= 0,
      memorySampleIntervalSeconds > 0 else {
    fatalError("Runs and memory samples must be positive, and timing values must not be negative")
}

for launcher in launchers where FileManager.default.fileExists(atPath: launcher.bundleURL.path) == false {
    fatalError("Missing \(launcher.bundleURL.path)")
}

if isolateLaunchers {
    for launcher in configuredLaunchers where NSRunningApplication.runningApplications(withBundleIdentifier: launcher.bundleIdentifier).isEmpty == false {
        fatalError("Stop \(launcher.name) before using --isolate")
    }
}

let startedAt = timestamp()
let systemAtStart = environmentSnapshot()
if requireACPower && systemAtStart.powerSource != "AC Power" {
    fatalError("Benchmark requires AC power, found \(systemAtStart.powerSource)")
}

let results = launchers.map { launcher in
    let baselineProcessIDs = Set(processSnapshots().map(\.pid))
    ensureRunning(launcher)
    Thread.sleep(forTimeInterval: startupWaitSeconds)
    ensureHidden(launcher)

    for _ in 0..<warmupRuns {
        _ = measurePanel(launcher)
    }

    let panelSamples = (0..<measuredRuns).map { _ in
        PanelSample(capturedAt: timestamp(), milliseconds: measurePanel(launcher))
    }
    Thread.sleep(forTimeInterval: postPanelSettleSeconds)
    let memoryReadings = (0..<memorySampleCount).map { _ -> MemorySample in
        defer { Thread.sleep(forTimeInterval: memorySampleIntervalSeconds) }
        guard let sample = memorySample(
            bundleURL: launcher.bundleURL,
            baselineProcessIDs: baselineProcessIDs,
            includesDetachedWebKit: launcher.includesDetachedWebKit,
            stabilitySeconds: processStabilitySeconds
        ) else {
            fatalError("Could not collect a complete memory sample for \(launcher.name)")
        }
        return sample
    }

    let result = LauncherResult(
        name: launcher.name,
        bundleIdentifier: launcher.bundleIdentifier,
        version: bundleVersion(launcher.bundleURL),
        build: bundleBuild(launcher.bundleURL),
        hotkey: launcher.shortcut.displayName,
        keyCode: launcher.shortcut.keyCode,
        modifierFlags: launcher.shortcut.flags.rawValue,
        bundleKilobytes: bundleKilobytes(launcher.bundleURL),
        panelLatencyMilliseconds: summary(panelSamples.map(\.milliseconds)),
        warmedFootprintMegabytes: summary(memoryReadings.map(\.footprintMegabytes)),
        idleRSSMegabytes: summary(memoryReadings.map(\.rssMegabytes)),
        panelSamples: panelSamples,
        memorySamples: memoryReadings
    )
    if isolateLaunchers {
        stopLauncher(
            launcher,
            processIDs: Set(memoryReadings.flatMap { $0.processes.map(\.pid) }),
            baselineProcessIDs: baselineProcessIDs
        )
    }
    return result
}

let systemAtEnd = environmentSnapshot()
if requireACPower && systemAtEnd.powerSource != "AC Power" {
    fatalError("Benchmark ended without AC power, found \(systemAtEnd.powerSource)")
}

let formatter = ISO8601DateFormatter()
let report = BenchmarkResult(
    startedAt: startedAt,
    capturedAt: formatter.string(from: Date()),
    hardware: shell("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]).trimmingCharacters(in: .whitespacesAndNewlines),
    machineIdentifier: shell("/usr/sbin/sysctl", ["-n", "hw.model"]).trimmingCharacters(in: .whitespacesAndNewlines),
    logicalCPUCount: Int(shell("/usr/sbin/sysctl", ["-n", "hw.ncpu"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
    physicalMemoryBytes: UInt64(shell("/usr/sbin/sysctl", ["-n", "hw.memsize"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
    macOS: shell("/usr/bin/sw_vers", ["-productVersion"]).trimmingCharacters(in: .whitespacesAndNewlines),
    macOSBuild: shell("/usr/bin/sw_vers", ["-buildVersion"]).trimmingCharacters(in: .whitespacesAndNewlines),
    systemAtStart: systemAtStart,
    systemAtEnd: systemAtEnd,
    warmupRuns: warmupRuns,
    measuredRuns: measuredRuns,
    memorySampleCount: memorySampleCount,
    startupWaitSeconds: startupWaitSeconds,
    postPanelSettleSeconds: postPanelSettleSeconds,
    memorySampleIntervalSeconds: memorySampleIntervalSeconds,
    panelTimeoutSeconds: 2,
    panelPollMicroseconds: 500,
    panelMetric: "Elapsed time from CGEvent post to the first matching on-screen CGWindow entry",
    memoryMetric: "Summary Footprint from macOS footprint for selected process IDs",
    processSelection: "Bundle processes, their descendants, and Raycast's newly spawned WebKit XPC processes",
    processMinimumAgeSeconds: processMinimumAgeSeconds,
    processStabilitySeconds: processStabilitySeconds,
    isolatedLaunchers: isolateLaunchers,
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

func stopLauncher(_ launcher: Launcher, processIDs: Set<Int>, baselineProcessIDs: Set<Int>) {
    for application in NSRunningApplication.runningApplications(withBundleIdentifier: launcher.bundleIdentifier) {
        application.forceTerminate()
    }

    var stoppingPIDs = processIDs
    for _ in 0..<50 {
        let processes = processSnapshots()
        let bundlePrefix = launcher.bundleURL.path + "/Contents/"
        var currentPIDs = Set(processes.compactMap { process in
            let isBundleProcess = process.command.contains(bundlePrefix)
            let isNewWebKitProcess = launcher.includesDetachedWebKit
                && isWebKitProcess(process)
                && baselineProcessIDs.contains(process.pid) == false
            return isBundleProcess || isNewWebKitProcess ? process.pid : nil
        })
        var changed = true
        while changed {
            changed = false
            for process in processes where currentPIDs.contains(process.parentPID) && currentPIDs.contains(process.pid) == false {
                currentPIDs.insert(process.pid)
                changed = true
            }
        }
        stoppingPIDs.formUnion(currentPIDs)
        for pid in stoppingPIDs {
            _ = Darwin.kill(pid_t(pid), SIGTERM)
        }

        let appStopped = NSRunningApplication.runningApplications(withBundleIdentifier: launcher.bundleIdentifier).isEmpty
        let remainingPIDs = Set(processSnapshots().map(\.pid).filter { stoppingPIDs.contains($0) })
        if appStopped && remainingPIDs.isEmpty { return }
        usleep(100_000)
    }
    fatalError("Could not isolate \(launcher.name)")
}

func measurePanel(_ launcher: Launcher) -> Double {
    ensureHidden(launcher)
    Thread.sleep(forTimeInterval: 0.2)

    let start = ContinuousClock.now
    postKey(code: launcher.shortcut.keyCode, flags: launcher.shortcut.flags)
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
        postKey(code: launcher.shortcut.keyCode, flags: launcher.shortcut.flags)
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

func memorySample(bundleURL: URL, baselineProcessIDs: Set<Int>, includesDetachedWebKit: Bool, stabilitySeconds: Double) -> MemorySample? {
    for attempt in 0..<5 {
        let firstOwned = ownedProcesses(
            bundleURL: bundleURL,
            baselineProcessIDs: baselineProcessIDs,
            includesDetachedWebKit: includesDetachedWebKit,
            processes: processSnapshots()
        )
        usleep(useconds_t(stabilitySeconds * 1_000_000))
        let secondOwned = ownedProcesses(
            bundleURL: bundleURL,
            baselineProcessIDs: baselineProcessIDs,
            includesDetachedWebKit: includesDetachedWebKit,
            processes: processSnapshots()
        )
        let firstPIDs = Set(firstOwned.map(\.pid))
        let owned = secondOwned.filter { firstPIDs.contains($0.pid) }
        if owned.isEmpty == false,
           let footprintBytes = footprintBytes(for: owned.map(\.pid)) {
            let rssKilobytes = owned.reduce(0) { $0 + $1.rssKilobytes }
            return MemorySample(
                capturedAt: timestamp(),
                footprintMegabytes: Double(footprintBytes) / 1_048_576,
                rssMegabytes: Double(rssKilobytes) / 1024,
                processes: owned
            )
        }
        if attempt < 4 { usleep(100_000) }
    }
    return nil
}

func processSnapshots() -> [ProcessSnapshot] {
    let output = shell("/bin/ps", ["-axo", "pid=,ppid=,rss=,etime=,command="])
    return output.split(separator: "\n").compactMap(parseProcess)
}

func ownedProcesses(bundleURL: URL, baselineProcessIDs: Set<Int>, includesDetachedWebKit: Bool, processes: [ProcessSnapshot]) -> [ProcessSnapshot] {
    let prefix = bundleURL.path + "/Contents/"
    let eligibleProcesses = processes.filter { $0.elapsedSeconds >= processMinimumAgeSeconds }
    var ownership: [Int: String] = [:]
    for process in eligibleProcesses where process.command.contains(prefix) {
        ownership[process.pid] = "bundle"
    }
    for process in eligibleProcesses where includesDetachedWebKit && isWebKitProcess(process) && baselineProcessIDs.contains(process.pid) == false {
        ownership[process.pid] = "newDetachedWebKit"
    }

    var changed = true
    while changed {
        changed = false
        for process in eligibleProcesses where ownership[process.pid] == nil {
            guard let parentOwnership = ownership[process.parentPID] else { continue }
            ownership[process.pid] = parentOwnership == "newDetachedWebKit" ? "WebKitDescendant" : "descendant"
            changed = true
        }
    }

    return eligibleProcesses.compactMap { process in
        guard let processOwnership = ownership[process.pid] else { return nil }
        return ProcessSnapshot(
            pid: process.pid,
            parentPID: process.parentPID,
            rssKilobytes: process.rssKilobytes,
            elapsedSeconds: process.elapsedSeconds,
            command: process.command,
            ownership: processOwnership
        )
    }.sorted { $0.pid < $1.pid }
}

func isWebKitProcess(_ process: ProcessSnapshot) -> Bool {
    process.command.contains("/WebKit.framework/") && process.command.contains("/XPCServices/com.apple.WebKit.")
}

func footprintBytes(for pids: [Int]) -> Int? {
    guard pids.isEmpty == false else { return nil }
    let output = shell("/usr/bin/footprint", ["--noCategories", "-f", "bytes"] + pids.map(String.init))
    var processFootprint: Int?
    for line in output.split(separator: "\n") {
        let fields = line.split(whereSeparator: \Character.isWhitespace)
        if fields.count == 4, fields[0] == "Summary", fields[1] == "Footprint:", fields[3] == "B" {
            return Int(fields[2])
        }
        guard let index = fields.firstIndex(of: "Footprint:"),
              fields.indices.contains(index + 2),
              fields[index + 2] == "B" else { continue }
        if pids.count == 1 {
            processFootprint = processFootprint ?? Int(fields[index + 1])
        }
    }
    return processFootprint
}

func parseProcess(_ line: Substring) -> ProcessSnapshot? {
    let fields = line.split(maxSplits: 4, whereSeparator: \Character.isWhitespace)
    guard fields.count == 5,
          let pid = Int(fields[0]),
          let parentPID = Int(fields[1]),
          let rssKilobytes = Int(fields[2]),
          let elapsedSeconds = elapsedSeconds(from: fields[3]) else { return nil }
    return ProcessSnapshot(
        pid: pid,
        parentPID: parentPID,
        rssKilobytes: rssKilobytes,
        elapsedSeconds: elapsedSeconds,
        command: String(fields[4]),
        ownership: ""
    )
}

func elapsedSeconds(from value: Substring) -> Int? {
    let dayAndTime = value.split(separator: "-", maxSplits: 1).map(String.init)
    let days: Int
    let clock: String
    if dayAndTime.count == 2 {
        guard let parsedDays = Int(dayAndTime[0]) else { return nil }
        days = parsedDays
        clock = dayAndTime[1]
    } else {
        days = 0
        clock = dayAndTime[0]
    }
    let parts = clock.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2 || parts.count == 3 else { return nil }
    let hours = parts.count == 3 ? parts[0] : 0
    let minutes = parts.count == 3 ? parts[1] : parts[0]
    let seconds = parts.count == 3 ? parts[2] : parts[1]
    return days * 86_400 + hours * 3_600 + minutes * 60 + seconds
}

func bundleVersion(_ url: URL) -> String {
    Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
}

func bundleBuild(_ url: URL) -> String {
    Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
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
    let rank = max(Int((Double(sorted.count) * percentile).rounded(.up)), 1)
    let index = rank - 1
    return sorted[min(max(index, 0), sorted.count - 1)]
}

func durationMilliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
}

func timestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
}

func environmentSnapshot() -> EnvironmentSnapshot {
    EnvironmentSnapshot(
        powerSource: powerSource(),
        powerDetails: shell("/usr/bin/pmset", ["-g", "batt"]).trimmingCharacters(in: .whitespacesAndNewlines),
        powerSettings: shell("/usr/bin/pmset", ["-g"]).trimmingCharacters(in: .whitespacesAndNewlines),
        thermalDetails: shell("/usr/bin/pmset", ["-g", "therm"]).trimmingCharacters(in: .whitespacesAndNewlines)
    )
}

func powerSource() -> String {
    let line = shell("/usr/bin/pmset", ["-g", "batt"]).split(separator: "\n").first.map(String.init) ?? ""
    let parts = line.split(separator: "'")
    return parts.count >= 2 ? String(parts[1]) : "unknown"
}

func foundryShortcut() -> Shortcut {
    let fallback = Shortcut(keyCode: CGKeyCode(kVK_Space), flags: .maskCommand, displayName: "Command-Space")
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/foundry/config.json")
    guard let data = try? Data(contentsOf: url),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let hotkey = root["hotkey"] as? [String: Any],
          let keyCode = hotkey["keyCode"] as? NSNumber,
          let modifiers = hotkey["modifiers"] as? NSNumber else { return fallback }
    let displayName = hotkey["displayName"] as? String ?? fallback.displayName
    return Shortcut(
        keyCode: CGKeyCode(keyCode.uint16Value),
        flags: eventFlags(carbonModifiers: modifiers.uint32Value),
        displayName: displayName
    )
}

func raycastShortcut() -> Shortcut {
    let value = shell("/usr/bin/defaults", ["read", "com.raycast.macos", "raycastGlobalHotkey"])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = value.split(separator: "-")
    guard let keyCode = parts.last.flatMap({ UInt16($0) }), parts.count > 1 else {
        fatalError("Could not read Raycast global hotkey: \(value)")
    }
    return Shortcut(
        keyCode: CGKeyCode(keyCode),
        flags: eventFlags(modifierNames: parts.dropLast().map(String.init)),
        displayName: value
    )
}

func eventFlags(carbonModifiers: UInt32) -> CGEventFlags {
    var flags: CGEventFlags = []
    if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.maskCommand) }
    if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
    if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
    if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
    return flags
}

func eventFlags(modifierNames: [String]) -> CGEventFlags {
    var flags: CGEventFlags = []
    for modifier in modifierNames {
        switch modifier.lowercased() {
        case "command", "cmd": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "option", "alt": flags.insert(.maskAlternate)
        case "control", "ctrl": flags.insert(.maskControl)
        default: break
        }
    }
    return flags
}
