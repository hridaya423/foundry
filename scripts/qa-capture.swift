import Cocoa
import Carbon

// qa-capture.swift — drive the running Foundry panel and capture per-surface PNGs.
// usage: swift scripts/qa-capture.swift <outDir> [--prefix NAME] [surface...]
//   surfaces: home | search | actions | clipboard | settings (default: all)
//   captures only the panel window via screencapture -x -o -l <windowID>

let args = Array(CommandLine.arguments.dropFirst())
var outDir: String?
var prefix = ""
var requested: [String] = []
var index = 0
while index < args.count {
    let arg = args[index]
    if arg == "--prefix" {
        index += 1
        prefix = index < args.count ? args[index] : ""
    } else if outDir == nil {
        outDir = arg
    } else {
        requested.append(arg)
    }
    index += 1
}
guard let outDir else {
    FileHandle.standardError.write("usage: swift scripts/qa-capture.swift <outDir> [--prefix NAME] [surface...]\n".data(using: .utf8)!)
    exit(2)
}
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let bundleID = "com.hridya.foundry"
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    fatalError("Foundry (\(bundleID)) is not running")
}
let pid = app.processIdentifier

struct Hotkey {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

func launcherHotkey() -> Hotkey {
    let fallback = Hotkey(keyCode: CGKeyCode(kVK_Space), flags: .maskCommand)
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/foundry/config.json")
    guard let data = try? Data(contentsOf: url),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let hotkey = root["hotkey"] as? [String: Any],
          let keyCode = hotkey["keyCode"] as? NSNumber,
          let modifiers = hotkey["modifiers"] as? NSNumber else { return fallback }
    var flags: CGEventFlags = []
    let carbon = modifiers.uint32Value
    if carbon & UInt32(cmdKey) != 0 { flags.insert(.maskCommand) }
    if carbon & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
    if carbon & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
    if carbon & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
    return Hotkey(keyCode: CGKeyCode(keyCode.uint16Value), flags: flags)
}

let hotkey = launcherHotkey()

func postKey(_ key: CGKeyCode, flags: CGEventFlags = []) {
    let src = CGEventSource(stateID: .hidSystemState)
    let dn = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
    dn?.flags = flags
    up?.flags = flags
    dn?.post(tap: .cghidEventTap)
    usleep(12000)
    up?.post(tap: .cghidEventTap)
}

let keyMap: [Character: CGKeyCode] = [
    "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38,
    "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1,
    "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
    " ": 49, ".": 47, ",": 43, "-": 27,
]

func type(_ text: String) {
    for ch in text.lowercased() {
        guard let key = keyMap[ch] else { continue }
        postKey(key)
        Thread.sleep(forTimeInterval: 0.09)
    }
}

func panelWindowID() -> Int? {
    foundryWindowID { $0 < 760 }
}



func foundryWindowID(matchingWidth accepts: (CGFloat) -> Bool) -> Int? {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return nil }
    var best: (wid: Int, area: CGFloat)?
    for window in list {
        guard (window["kCGWindowOwnerPID"] as? Int32) == pid,
              let wid = window["kCGWindowNumber"] as? Int,
              (window["kCGWindowAlpha"] as? Double ?? 0) > 0.05 else { continue }
        let bounds = window["kCGWindowBounds"] as? [String: CGFloat] ?? [:]
        guard accepts(bounds["Width"] ?? 0) else { continue }
        let area = (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
        if best == nil || area > best!.area { best = (wid, area) }
    }
    return best?.wid
}

func ensurePanelOpen() {
    guard panelWindowID() == nil else { return }
    postKey(hotkey.keyCode, flags: hotkey.flags)
    Thread.sleep(forTimeInterval: 0.9)
}

func ensurePanelClosed() {
    guard panelWindowID() != nil else { return }
    postKey(hotkey.keyCode, flags: hotkey.flags)
    Thread.sleep(forTimeInterval: 0.6)
}

func axChildren(of element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
    return value as? [AXUIElement] ?? []
}

func axTitle(of element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else { return nil }
    return value as? String
}

func openClipboardHistoryViaMenu() -> Bool {
    let appElement = AXUIElementCreateApplication(pid)
    var extrasValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appElement, kAXExtrasMenuBarAttribute as CFString, &extrasValue) == .success,
          let extrasValue else { return false }
    let extras = extrasValue as! AXUIElement
    guard let statusItem = axChildren(of: extras).first,
          let menu = axChildren(of: statusItem).first else { return false }
    for item in axChildren(of: menu) where axTitle(of: item) == "Clipboard History" {
        AXUIElementPerformAction(item, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.9)
        return true
    }
    return false
}

func snap(_ surface: String) {
    guard let wid = panelWindowID() else {
        print("WARN no panel window for \(surface); skipping")
        return
    }
    let name = prefix.isEmpty ? "\(surface).png" : "\(prefix)-\(surface).png"
    let path = "\(outDir)/\(name)"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o", "-l", String(wid), path]
    try? process.run()
    process.waitUntilExit()
    print("captured \(path)")
}

func drive(_ surface: String) {
    ensurePanelClosed()
    switch surface {
    case "clipboard":
        if openClipboardHistoryViaMenu() == false {
            print("WARN status item menu unavailable; falling back to command search")
            ensurePanelOpen()
            type("clipboard")
            Thread.sleep(forTimeInterval: 0.7)
            postKey(36)
            Thread.sleep(forTimeInterval: 0.7)
        }
    default:
        ensurePanelOpen()
        switch surface {
        case "home":
            break
        case "search":
            type("saf")
            Thread.sleep(forTimeInterval: 0.9)
        case "actions":
            type("saf")
            Thread.sleep(forTimeInterval: 0.8)
            postKey(40, flags: .maskCommand)
            Thread.sleep(forTimeInterval: 0.5)
        case "settings", "settings-search":
            type("settings")
            Thread.sleep(forTimeInterval: 0.7)
            postKey(36)
            Thread.sleep(forTimeInterval: 0.9)
            if surface == "settings-search" {
                type("clip")
                Thread.sleep(forTimeInterval: 0.5)
            }
        default:
            print("WARN unknown surface \(surface); capturing raw")
        }
    }
    snap(surface)
    ensurePanelClosed()
}

let allSurfaces = ["home", "search", "actions", "clipboard", "settings", "settings-search"]
let targets = requested.isEmpty ? allSurfaces : requested
print("Foundry pid \(pid); hotkey keyCode \(hotkey.keyCode) flags \(hotkey.flags.rawValue)")
for surface in targets {
    drive(surface)
}
