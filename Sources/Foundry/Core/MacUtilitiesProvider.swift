import AppKit
import CoreAudio
import Foundation

final class MacUtilitiesProvider: CommandProvider {
    let id = "foundry.mac-utilities"

    private let activitySampler = ActivityMonitorSampler()

    func results(matching query: String) async -> [CommandResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }

        var results: [CommandResult] = []
        results.append(contentsOf: keepAwakeResults(query: trimmed))
        results.append(contentsOf: killProcessResults(query: trimmed))
        results.append(contentsOf: quitAppResults(query: trimmed))
        results.append(contentsOf: portResults(query: trimmed))
        results.append(contentsOf: audioDeviceResults(query: trimmed))

        return results.sorted {
            if $0.score == $1.score { return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            return $0.score > $1.score
        }
    }

    func defaultResults() async -> [CommandResult] {
        [
            makeResult(id: "mac.keepawake", title: KeepAwakeController.isActive() ? "Disable Keep Awake" : "Enable Keep Awake", subtitle: "Prevent the Mac from sleeping", icon: "cup.and.saucer.fill", fallback: "ZZ", score: 4, primary: .toggleKeepAwake),
            makeResult(id: "mac.audio.output", title: "Switch Audio Output", subtitle: "Choose a playback device", icon: "speaker.wave.2.fill", fallback: "AU", score: 2, primary: .log("Search for an output device by name")),
            makeResult(id: "mac.port", title: "Kill Port", subtitle: "Stop the process listening on a TCP port", icon: "network", fallback: "PT", score: 2, primary: .log("Search with a port number, e.g. port 3000"))
        ]
    }

    private func keepAwakeResults(query: String) -> [CommandResult] {
        guard SearchScoring.score(query: query, title: "Keep Awake", aliases: ["coffee", "caffeinate", "awake", "sleep off"]) != nil else { return [] }
        let active = KeepAwakeController.isActive()
        return [makeResult(id: "mac.keepawake.toggle", title: active ? "Disable Keep Awake" : "Enable Keep Awake", subtitle: active ? "caffeinate is currently running" : "Prevent the Mac from sleeping", icon: "cup.and.saucer.fill", fallback: "ZZ", score: 96, primary: .toggleKeepAwake)]
    }

    private func killProcessResults(query: String) -> [CommandResult] {
        guard let needle = payload(in: query, prefixes: ["kill", "terminate", "kill process", "stop process"]), needle.isEmpty == false else { return [] }
        let snapshot = activitySampler.sample()
        return snapshot.processes
            .filter { process in
                let haystacks = [process.displayName, process.name, process.path ?? "", String(process.pid)]
                return haystacks.contains { SearchScoring.normalize($0).contains(SearchScoring.normalize(needle)) }
            }
            .prefix(8)
            .map { process in
                makeResult(
                    id: "mac.kill.\(process.pid)",
                    title: "Kill \(process.displayName)",
                    subtitle: process.subtitle,
                    icon: process.symbolName ?? "xmark.app.fill",
                    fallback: "KP",
                    score: 98 - Double(max(0, process.pid % 7)),
                    primary: .terminateProcess(pid: process.pid)
                )
            }
    }

    private func quitAppResults(query: String) -> [CommandResult] {
        guard let needle = payload(in: query, prefixes: ["quit", "close app", "quit app", "quit application"]), needle.isEmpty == false else { return [] }
        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard let name = app.localizedName, app.activationPolicy != .prohibited else { return false }
                return SearchScoring.normalize(name).contains(SearchScoring.normalize(needle))
            }
            .prefix(8)
            .map { app in
                let name = app.localizedName ?? "Application"
                return makeResult(
                    id: "mac.quit.\(app.processIdentifier)",
                    title: "Quit \(name)",
                    subtitle: app.bundleIdentifier ?? "Running application",
                    icon: "app.badge.xmark",
                    fallback: "QA",
                    score: 97,
                    primary: .quitApplication(bundleID: app.bundleIdentifier, name: name)
                )
            }
    }

    private func portResults(query: String) -> [CommandResult] {
        let needle = payload(in: query, prefixes: ["port", "kill port", "stop port"])
        let candidateSource = needle?.isEmpty == false ? needle! : query
        guard let candidate = candidateSource.split(whereSeparator: { !$0.isNumber }).first,
              let port = Int(candidate), (1...65535).contains(port) else { return [] }
        let usage = PortUtility.lookup(port: port)
        return [
            makeResult(
                id: "mac.port.\(port)",
                title: "Kill Port \(port)",
                subtitle: usage ?? "Terminate the process listening on tcp:\(port)",
                icon: "network",
                fallback: "PT",
                score: 98,
                primary: .terminatePort(port)
            )
        ]
    }

    private func audioDeviceResults(query: String) -> [CommandResult] {
        let normalized = SearchScoring.normalize(query)
        let wantsOutput = normalized.contains("audio") || normalized.contains("sound") || normalized.contains("speaker") || normalized.contains("output")
        let wantsInput = normalized.contains("microphone") || normalized.contains("mic") || normalized.contains("input")
        guard wantsOutput || wantsInput else { return [] }

        let devices = AudioDevicesUtility.devices()
        return devices.compactMap { device in
            let kindMatches = (wantsInput && device.hasInput) || (wantsOutput && device.hasOutput)
            guard kindMatches else { return nil }
            guard SearchScoring.score(query: query, title: device.name, aliases: [device.hasOutput ? "output audio" : "", device.hasInput ? "input audio" : ""].filter { !$0.isEmpty }) != nil else { return nil }
            let kind: AudioDeviceKind = wantsInput && device.hasInput && wantsOutput == false ? .input : .output
            return makeResult(
                id: "mac.audio.\(device.id).\(kind == .output ? "out" : "in")",
                title: "Use \(device.name)",
                subtitle: kind == .output ? "Set as output device" : "Set as input device",
                icon: kind == .output ? "speaker.wave.2.fill" : "mic.fill",
                fallback: "AU",
                score: 95,
                primary: .setAudioDevice(id: device.id, kind: kind)
            )
        }
    }

    private func payload(in query: String, prefixes: [String]) -> String? {
        let normalizedQuery = SearchScoring.normalize(query)
        for prefix in prefixes.map(SearchScoring.normalize) {
            if normalizedQuery == prefix { return "" }
            if normalizedQuery.hasPrefix(prefix + " ") {
                let index = query.index(query.startIndex, offsetBy: prefix.count)
                return query[index...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func makeResult(id: String, title: String, subtitle: String, icon: String, fallback: String, score: Double, primary: CommandActionKind) -> CommandResult {
        CommandResult(id: id, title: title, subtitle: subtitle, icon: CommandIcon(fallback: fallback, systemName: icon), score: score, primaryAction: CommandAction(id: id + ".primary", title: "Run", kind: primary), secondaryActions: [])
    }
}

private enum PortUtility {
    static func lookup(port: Int) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n")
        guard lines.count > 1 else { return nil }
        let columns = lines[1].split(whereSeparator: { $0.isWhitespace })
        guard columns.count >= 2 else { return nil }
        return "\(columns[0]) PID \(columns[1]) is listening on tcp:\(port)"
    }
}

private enum AudioDevicesUtility {
    struct Device: Sendable {
        let id: AudioDeviceID
        let name: String
        let hasOutput: Bool
        let hasInput: Bool
    }

    static func devices() -> [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap(device)
    }

    private static func device(id: AudioDeviceID) -> Device? {
        guard let name = name(id: id) else { return nil }
        return Device(id: id, name: name, hasOutput: hasStreams(id: id, scope: kAudioDevicePropertyScopeOutput), hasInput: hasStreams(id: id, scope: kAudioDevicePropertyScopeInput))
    }

    private static func name(id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var cfName: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &cfName) == noErr else { return nil }
        return cfName as String
    }

    private static func hasStreams(id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }
}
