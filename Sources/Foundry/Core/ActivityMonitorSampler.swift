import AppKit
import Darwin
import Foundation

struct ActivitySnapshot: Sendable {
    let sampledAt: Date
    let cpuUsage: Double
    let memoryUsed: UInt64
    let memoryTotal: UInt64
    let processCount: Int
    let groupCount: Int
    let processes: [ActivityProcess]
}

struct ActivityProcess: Identifiable, Hashable, Sendable {
    let id: Int32
    let pid: Int32
    let parentPID: Int32
    let name: String
    let displayName: String
    let path: String?
    let bundlePath: String?
    let iconPath: String?
    let symbolName: String?
    let groupKey: String
    let groupName: String
    let hasCPUReading: Bool
    let cpuUsage: Double
    let memoryBytes: UInt64
    let threadCount: Int
    let launchTime: Date?

    var subtitle: String {
        let memory = ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
        if threadCount > 0 {
            return "PID \(pid) - \(memory) - \(threadCount) threads"
        }
        return "PID \(pid) - \(memory)"
    }
}

final class ActivityMonitorSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var previousSample: [Int32: ProcessCPUReading] = [:]
    private var previousSystemCPU: SystemCPUReading?
    private var previousDate: Date?

    func sample() -> ActivitySnapshot {
        let now = Date()
        let runningApps = NSWorkspace.shared.runningApplications
        let appByPID = Dictionary(uniqueKeysWithValues: runningApps.map { ($0.processIdentifier, $0) })
        let elapsed = lock.withLock { previousDate.map { now.timeIntervalSince($0) } ?? 1 }
        let safeElapsed = max(elapsed, 0.1)
        let pids = allPIDs()
        var readings: [Int32: ProcessCPUReading] = [:]
        var rawProcesses: [RawActivityProcess] = []
        rawProcesses.reserveCapacity(pids.count)

        for pid in pids where pid > 0 {
            guard let taskInfo = taskInfo(for: pid) else { continue }
            let bsdInfo = bsdInfo(for: pid)
            let cpuTime = (Double(taskInfo.pti_threads_user) + Double(taskInfo.pti_threads_system)) / 1_000_000_000
            readings[pid] = ProcessCPUReading(cpuTime: cpuTime)

            let previous = lock.withLock { previousSample[pid] }
            let cpuUsage = previous.map { max(0, (cpuTime - $0.cpuTime) / safeElapsed * 100) } ?? 0
            let path = processPath(pid: pid)
            let name = processName(pid: pid, path: path)
            let app = appByPID[pid]
            let derivedBundlePath = app?.bundleURL?.path ?? appBundlePath(containing: path)

            rawProcesses.append(
                RawActivityProcess(
                    pid: pid,
                    parentPID: bsdInfo.map { Int32($0.pbi_ppid) } ?? 0,
                    name: name,
                    path: path,
                    bundlePath: derivedBundlePath,
                    runningAppName: app?.localizedName,
                    cpuUsage: cpuUsage.isFinite ? cpuUsage : 0,
                    hasCPUReading: previous != nil,
                    memoryBytes: taskInfo.pti_resident_size,
                    threadCount: Int(taskInfo.pti_threadnum)
                )
            )
        }

        let rawByPID = Dictionary(uniqueKeysWithValues: rawProcesses.map { ($0.pid, $0) })
        let processFamilies = rawProcesses.map { raw -> ActivityProcess in
            let family = resolveFamily(for: raw, processByPID: rawByPID)
            return ActivityProcess(
                id: raw.pid,
                pid: raw.pid,
                parentPID: raw.parentPID,
                name: raw.name,
                displayName: family.name,
                path: raw.path,
                bundlePath: family.bundlePath,
                iconPath: family.iconPath,
                symbolName: family.symbolName,
                groupKey: family.key,
                groupName: family.name,
                hasCPUReading: raw.hasCPUReading,
                cpuUsage: raw.cpuUsage,
                memoryBytes: raw.memoryBytes,
                threadCount: raw.threadCount,
                launchTime: nil
            )
        }

        lock.withLock {
            previousSample = readings
            previousDate = now
        }

        let sortedProcesses = processFamilies.sorted {
            if $0.cpuUsage == $1.cpuUsage {
                return $0.memoryBytes > $1.memoryBytes
            }
            return $0.cpuUsage > $1.cpuUsage
        }
        let cpuUsage = systemCPUUsage()
        let memoryUsed = sortedProcesses.reduce(UInt64(0)) { $0 + $1.memoryBytes }
        let memoryTotal = ProcessInfo.processInfo.physicalMemory
        let groupCount = Set(sortedProcesses.map(\.groupKey)).count

        return ActivitySnapshot(
            sampledAt: now,
            cpuUsage: cpuUsage,
            memoryUsed: min(memoryUsed, memoryTotal),
            memoryTotal: memoryTotal,
            processCount: sortedProcesses.count,
            groupCount: groupCount,
            processes: sortedProcesses
        )
    }

    private func allPIDs() -> [Int32] {
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else { return [] }

        let capacity = Int(byteCount) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: capacity)
        let actualByteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard actualByteCount > 0 else { return [] }

        return pids.prefix(Int(actualByteCount) / MemoryLayout<pid_t>.stride).map { Int32($0) }
    }

    private func taskInfo(for pid: Int32) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTASKINFO, 0, pointer, Int32(MemoryLayout<proc_taskinfo>.stride))
        }
        guard result == Int32(MemoryLayout<proc_taskinfo>.stride) else { return nil }
        return info
    }

    private func bsdInfo(for pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, Int32(MemoryLayout<proc_bsdinfo>.stride))
        }
        guard result == Int32(MemoryLayout<proc_bsdinfo>.stride) else { return nil }
        return info
    }

    private func processPath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return nil }
            return String(cString: baseAddress)
        }
    }

    private func processName(pid: Int32, path: String?) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let result = proc_name(pid, &buffer, UInt32(buffer.count))
        if result > 0 {
            return buffer.withUnsafeBufferPointer { pointer in
                guard let baseAddress = pointer.baseAddress else { return path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Process \(pid)" }
                return String(cString: baseAddress)
            }
        }
        return path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Process \(pid)"
    }

    private func appBundlePath(containing path: String?) -> String? {
        guard let path else { return nil }
        let components = URL(fileURLWithPath: path).pathComponents
        guard let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return NSString.path(withComponents: Array(components.prefix(through: appIndex)))
    }

    private func normalizedGroupName(for name: String) -> String {
        var normalized = name
        let removableSuffixes = [
            " Helper (Renderer)", " Helper (GPU)", " Helper (Plugin)", " Helper",
            " Helper.app", "-helper", "_helper", " service", "-service", "_service"
        ]
        for suffix in removableSuffixes {
            if normalized.localizedCaseInsensitiveContains(suffix), let range = normalized.range(of: suffix, options: [.caseInsensitive, .backwards]) {
                normalized.removeSubrange(range.lowerBound..<normalized.endIndex)
            }
        }

        if normalized.lowercased().hasPrefix("google chrome") { return "Google Chrome" }
        if normalized.lowercased().hasPrefix("cursor") { return "Cursor" }
        if normalized.lowercased().hasPrefix("codex") { return "Codex" }
        if normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return name }
        return normalized
    }

    private func resolveFamily(for process: RawActivityProcess, processByPID: [Int32: RawActivityProcess]) -> ProcessFamily {
        if let systemFamily = systemFamily(for: process.name) {
            return systemFamily
        }

        if let knownFamily = knownAppFamily(for: process.name, path: process.path) {
            return knownFamily
        }

        if let runningAppName = process.runningAppName, let knownFamily = knownAppFamily(for: runningAppName, path: process.path) {
            return knownFamily
        }

        if let bundlePath = process.bundlePath {
            return appFamily(bundlePath: bundlePath, fallbackName: process.runningAppName ?? normalizedGroupName(for: process.name))
        }

        if let ancestorFamily = ancestorAppFamily(for: process, processByPID: processByPID) {
            return ancestorFamily
        }

        let groupName = normalizedGroupName(for: process.name)
        if let knownFamily = knownAppFamily(for: groupName, path: process.path) {
            return knownFamily
        }

        return ProcessFamily(
            key: "process:\(groupName.lowercased())",
            name: groupName,
            bundlePath: nil,
            iconPath: process.path,
            symbolName: nil
        )
    }

    private func ancestorAppFamily(for process: RawActivityProcess, processByPID: [Int32: RawActivityProcess]) -> ProcessFamily? {
        var visited = Set<Int32>()
        var parentPID = process.parentPID
        for _ in 0..<8 {
            guard parentPID > 1, visited.insert(parentPID).inserted, let parent = processByPID[parentPID] else { return nil }
            if let knownFamily = knownAppFamily(for: parent.name, path: parent.path) {
                return knownFamily
            }
            if let runningAppName = parent.runningAppName, let knownFamily = knownAppFamily(for: runningAppName, path: parent.path) {
                return knownFamily
            }
            if let bundlePath = parent.bundlePath {
                return appFamily(bundlePath: bundlePath, fallbackName: parent.runningAppName ?? normalizedGroupName(for: parent.name))
            }
            parentPID = parent.parentPID
        }
        return nil
    }

    private func appFamily(bundlePath: String, fallbackName: String) -> ProcessFamily {
        let name = Bundle(path: bundlePath)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle(path: bundlePath)?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? fallbackName
        return ProcessFamily(
            key: "app:\(bundlePath)",
            name: normalizedGroupName(for: name),
            bundlePath: bundlePath,
            iconPath: bundlePath,
            symbolName: nil
        )
    }

    private func knownAppFamily(for name: String, path: String?) -> ProcessFamily? {
        let normalized = name.lowercased()
        let normalizedPath = path?.lowercased() ?? ""
        let families: [(prefixes: [String], pathContains: [String], name: String, symbolName: String?)] = [
            (["google chrome", "chrome_crashpad"], ["/google chrome.app/"], "Google Chrome", nil),
            (["cursor"], ["/cursor.app/"], "Cursor", nil),
            (["code", "code helper"], ["/visual studio code.app/", "/.vscode/"], "Visual Studio Code", nil),
            (["codex", "codex computer use", "codex service", "codex-service", "codexbar"], ["/codexbar.app/", "/bin/macos-aarch64/codex", "/openai.chatgpt-"], "Codex", "terminal"),
            (["opencode"], ["/opencode"], "opencode", "terminal"),
            (["node", "next-server", "npm"], ["/node", "/next-server"], "Node.js", "curlybraces"),
            (["sourcekit", "swift-frontend", "swiftc", "sourcekitservice"], ["/xcode.app/", "/sourcekit"], "Swift Toolchain", "swift"),
            (["mediaanalysisd", "media-indexer"], ["/mediaanalysis"], "Media Analysis", "photo.on.rectangle.angled")
        ]

        guard let match = families.first(where: { family in
            family.prefixes.contains(where: { normalized.hasPrefix($0) })
                || family.pathContains.contains(where: { normalizedPath.contains($0) })
        }) else { return nil }
        let appPath = applicationPath(named: match.name)
        return ProcessFamily(
            key: "family:\(match.name.lowercased())",
            name: match.name,
            bundlePath: appPath,
            iconPath: appPath,
            symbolName: match.symbolName
        )
    }

    private func applicationPath(named name: String) -> String? {
        let candidates = [
            "/Applications/\(name).app",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/\(name).app").path
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func systemFamily(for name: String) -> ProcessFamily? {
        let normalized = name.lowercased()
        if normalized.hasPrefix("mdworker") || normalized == "mds" || normalized == "mds_stores" || normalized == "mdwrite" {
            return ProcessFamily(key: "system:spotlight", name: "Spotlight Indexing", bundlePath: nil, iconPath: nil, symbolName: "magnifyingglass")
        }
        if normalized == "windowserver" {
            return ProcessFamily(key: "system:windowserver", name: "WindowServer", bundlePath: nil, iconPath: nil, symbolName: "display")
        }
        if normalized == "coreaudiod" || normalized.contains("audio") {
            return ProcessFamily(key: "system:audio", name: "Audio", bundlePath: nil, iconPath: nil, symbolName: "speaker.wave.2")
        }
        if normalized == "bird" || normalized == "cloudd" || normalized == "cloudphotod" {
            return ProcessFamily(key: "system:cloud", name: "Cloud Sync", bundlePath: nil, iconPath: nil, symbolName: "icloud")
        }
        return nil
    }

    private func systemCPUUsage() -> Double {
        guard let current = readSystemCPU() else { return 0 }
        return lock.withLock {
            defer { previousSystemCPU = current }
            guard let previous = previousSystemCPU else { return 0 }
            let totalDelta = current.totalTicks - previous.totalTicks
            let idleDelta = current.idleTicks - previous.idleTicks
            guard totalDelta > 0 else { return 0 }
            return min(max((1 - Double(idleDelta) / Double(totalDelta)) * 100, 0), 100)
        }
    }

    private func readSystemCPU() -> SystemCPUReading? {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount = mach_msg_type_number_t(0)
        var processorCount = natural_t(0)
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfo,
            &cpuInfoCount
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(Int(cpuInfoCount) * MemoryLayout<integer_t>.stride))
        }

        let stride = Int(CPU_STATE_MAX)
        var idleTicks: UInt64 = 0
        var totalTicks: UInt64 = 0
        for cpu in 0..<Int(processorCount) {
            let offset = cpu * stride
            let user = UInt64(cpuInfo[offset + Int(CPU_STATE_USER)])
            let system = UInt64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(cpuInfo[offset + Int(CPU_STATE_IDLE)])
            let nice = UInt64(cpuInfo[offset + Int(CPU_STATE_NICE)])
            idleTicks += idle
            totalTicks += user + system + idle + nice
        }
        return SystemCPUReading(totalTicks: totalTicks, idleTicks: idleTicks)
    }

}

private struct ProcessCPUReading: Sendable {
    let cpuTime: Double
}

private struct SystemCPUReading: Sendable {
    let totalTicks: UInt64
    let idleTicks: UInt64
}

private struct RawActivityProcess: Sendable {
    let pid: Int32
    let parentPID: Int32
    let name: String
    let path: String?
    let bundlePath: String?
    let runningAppName: String?
    let cpuUsage: Double
    let hasCPUReading: Bool
    let memoryBytes: UInt64
    let threadCount: Int
}

private struct ProcessFamily: Sendable {
    let key: String
    let name: String
    let bundlePath: String?
    let iconPath: String?
    let symbolName: String?
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
