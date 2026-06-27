import Darwin
import Foundation
import IOKit.ps

struct SystemMetrics: Sendable, Equatable {
    var cpuPercent: Double
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var memoryPercent: Double
    var batteryPercent: Int?
    var isCharging: Bool
    var hasBattery: Bool
    var diskFreeBytes: Int64
    var diskTotalBytes: Int64
    var uptimeSeconds: TimeInterval
    var thermal: ProcessInfo.ThermalState
    var localIPAddress: String?
    var loadAverage1m: Double

    static let placeholder = SystemMetrics(
        cpuPercent: 0,
        memoryUsed: 0,
        memoryTotal: ProcessInfo.processInfo.physicalMemory,
        memoryPercent: 0,
        batteryPercent: nil,
        isCharging: false,
        hasBattery: false,
        diskFreeBytes: 0,
        diskTotalBytes: 0,
        uptimeSeconds: ProcessInfo.processInfo.systemUptime,
        thermal: .nominal,
        localIPAddress: nil,
        loadAverage1m: 0
    )
}

final class SystemMetricsSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var previousCPU: SystemCPUTicks?

    init() {
        previousCPU = readCPUTicks()
    }

    func sample() -> SystemMetrics {
        let memory = memoryUsage()
        let battery = batteryInfo()
        let disk = diskCapacity()
        let memoryPercent = memory.total == 0 ? 0 : Double(memory.used) / Double(memory.total) * 100

        return SystemMetrics(
            cpuPercent: cpuUsage(),
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            memoryPercent: memoryPercent,
            batteryPercent: battery.percent,
            isCharging: battery.charging,
            hasBattery: battery.hasBattery,
            diskFreeBytes: disk.free,
            diskTotalBytes: disk.total,
            uptimeSeconds: ProcessInfo.processInfo.systemUptime,
            thermal: ProcessInfo.processInfo.thermalState,
            localIPAddress: localIPAddress(),
            loadAverage1m: loadAverage()
        )
    }

    private func cpuUsage() -> Double {
        guard let current = readCPUTicks() else { return 0 }
        lock.lock()
        defer { lock.unlock() }
        let previous = previousCPU
        previousCPU = current
        guard let previous else { return 0 }
        let totalDelta = current.total >= previous.total ? current.total - previous.total : 0
        let idleDelta = current.idle >= previous.idle ? current.idle - previous.idle : 0
        guard totalDelta > 0 else { return 0 }
        return min(max((1 - Double(idleDelta) / Double(totalDelta)) * 100, 0), 100)
    }

    private func readCPUTicks() -> SystemCPUTicks? {
        var cpuInfo: processor_info_array_t?
        var infoCount = mach_msg_type_number_t(0)
        var processorCount = natural_t(0)
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfo,
            &infoCount
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let stride = Int(CPU_STATE_MAX)
        var idle: UInt64 = 0
        var total: UInt64 = 0
        for cpu in 0..<Int(processorCount) {
            let offset = cpu * stride
            let user = UInt64(cpuInfo[offset + Int(CPU_STATE_USER)])
            let system = UInt64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            let idleTicks = UInt64(cpuInfo[offset + Int(CPU_STATE_IDLE)])
            let nice = UInt64(cpuInfo[offset + Int(CPU_STATE_NICE)])
            idle += idleTicks
            total += user + system + idleTicks + nice
        }
        return SystemCPUTicks(total: total, idle: idle)
    }

    private func memoryUsage() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }

        var rawPageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &rawPageSize) == KERN_SUCCESS else { return (0, total) }
        let pageSize = UInt64(rawPageSize)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        return (min(used, total), total)
    }

    private func batteryInfo() -> (percent: Int?, charging: Bool, hasBattery: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return (nil, false, false)
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int
            let maximum = description[kIOPSMaxCapacityKey] as? Int
            let charging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            let percent: Int?
            if let current, let maximum, maximum > 0 {
                percent = Int((Double(current) / Double(maximum) * 100).rounded())
            } else {
                percent = current
            }
            return (percent, charging, true)
        }

        return (nil, false, false)
    }

    private func diskCapacity() -> (free: Int64, total: Int64) {
        let url = URL(fileURLWithPath: "/")
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            return (values.volumeAvailableCapacityForImportantUsage ?? 0, Int64(values.volumeTotalCapacity ?? 0))
        }
        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
           let free = attributes[.systemFreeSize] as? NSNumber,
           let total = attributes[.systemSize] as? NSNumber {
            return (free.int64Value, total.int64Value)
        }
        return (0, 0)
    }

    private func localIPAddress() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        var fallback: String?
        for pointer in sequence(first: firstInterface, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name != "lo0" else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = host.withUnsafeBufferPointer { buffer in
                    String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                }
                if name == "en0" { return ip }
                fallback = fallback ?? ip
            }
        }
        return fallback
    }

    private func loadAverage() -> Double {
        var averages = [Double](repeating: 0, count: 3)
        return getloadavg(&averages, 3) > 0 ? averages[0] : 0
    }
}

private struct SystemCPUTicks: Sendable {
    let total: UInt64
    let idle: UInt64
}
