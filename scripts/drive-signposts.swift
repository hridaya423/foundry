import Cocoa
import Foundation

// Drives the running Foundry via its launcher hotkey (⌘Space) so DiagnosticsService spans
// (panel.show, search.immediate, search.complete, search.keyToResults, mode.switch) and marks
// (panel.firstFrame, results.committed, results.paintCommitted) can be collected with:
//   log stream --predicate 'subsystem == "app.foundry.prototype"' --level debug
// `drive-signposts.swift 30 --reopen build/Foundry.app` needs no Accessibility: it opens the panel
// through the app's reopen handler and closes it by activating Finder. It measures panel.show only.
// `--bench` adds wall-clock hotkey→panel-onscreen timings per cycle and prints p50/p95.
let arguments = CommandLine.arguments
let cycles = Int(arguments.dropFirst().first ?? "") ?? 30
let queries = ["saf", "calc", "clip", "wifi", "12*34", "term", "note", "emoji"]
let source = CGEventSource(stateID: .hidSystemState)

func panelOnScreen() -> Bool {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains { $0[kCGWindowOwnerName as String] as? String == "Foundry" }
}

if let flag = arguments.firstIndex(of: "--reopen"), arguments.indices.contains(flag + 1) {
    // NSRunningApplication.activate() from a background script is refused (cooperative activation);
    // a LaunchServices open is not.
    func open(_ url: URL) {
        let opened = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in opened.signal() }
        opened.wait()
    }
    let bundle = URL(fileURLWithPath: arguments[flag + 1])
    let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    var stuck = 0
    for _ in 0..<cycles {
        open(bundle)
        usleep(900_000)
        open(finder)
        usleep(700_000)
        if panelOnScreen() { stuck += 1 }
    }
    if stuck > 0 { fputs("Panel stayed on screen after \(stuck) of \(cycles) cycles\n", stderr) }
    exit(stuck == 0 ? 0 : 1)
}

func press(_ key: CGKeyCode, flags: CGEventFlags = []) {
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }
}

// Real virtual keys — keyboardSetUnicodeString events never reach the panel's field.
let keycodes: [Character: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26,
    "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
    "k": 40, "n": 45, "m": 46, "h": 4, "*": 67,
]

func type(_ text: String) {
    for char in text {
        guard let key = keycodes[char] else { continue }
        press(key)
        usleep(90_000)
    }
}

func waitForPanel(_ onscreen: Bool) -> Bool {
    for _ in 0..<40 {
        if panelOnScreen() == onscreen { return true }
        usleep(50_000)
    }
    return false
}

let benchMode = arguments.contains("--bench")
var openLatencies: [Double] = []
var keyLatencies: [Double] = []

func percentile(_ values: [Double], _ p: Double) -> Double {
    guard values.isEmpty == false else { return .nan }
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, max(0, Int((Double(sorted.count) * p).rounded(.down))))]
}

for cycle in 0..<cycles {
    // Blind toggles invert if the panel starts open — only press when state disagrees.
    if !panelOnScreen() {
        let openStart = ContinuousClock().now
        press(49, flags: .maskCommand)
        if waitForPanel(true) {
            if benchMode {
                let elapsed = ContinuousClock().now - openStart
                openLatencies.append(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
            }
        } else {
            fputs("cycle \(cycle): panel never appeared\n", stderr)
            continue
        }
    }
    let query = queries[cycle % queries.count]
    let keyStart = ContinuousClock().now
    type(query)
    if benchMode {
        // Wall-clock cost of typing the whole query; per-keystroke timing is
        // the signposts' job — this approximates keystroke→first-results
        // only for the first key.
        let elapsed = ContinuousClock().now - keyStart
        keyLatencies.append(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
    }
    usleep(900_000)
    if panelOnScreen() { press(49, flags: .maskCommand) }
    _ = waitForPanel(false)
}

if benchMode {
    let fmt = { (name: String, values: [Double]) in
        print(String(format: "%@  n=%d  p50=%.1fms  p95=%.1fms", name, values.count, percentile(values, 0.50), percentile(values, 0.95)))
    }
    fmt("hotkey→panelOnScreen", openLatencies)
    fmt("query.typeWall", keyLatencies)
}
