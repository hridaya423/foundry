import Darwin
import Foundation

struct ProcessInfoRow: Equatable, Sendable {
    let pid: String
    let startedAt: Date?
    let args: String

    var executableName: String {
        args.split(separator: " ").first.map { URL(fileURLWithPath: String($0)).lastPathComponent } ?? ""
    }
}

protocol ProcessSnapshotProviding: Sendable {
    func capture() -> [ProcessInfoRow]
}

final class NativeProcessSnapshotProvider: @unchecked Sendable, ProcessSnapshotProviding {
    func capture() -> [ProcessInfoRow] {
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else { return [] }

        let capacity = Int(byteCount) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: capacity)
        let actualByteCount = proc_listpids(
            UInt32(PROC_ALL_PIDS),
            0,
            &pids,
            Int32(pids.count * MemoryLayout<pid_t>.stride)
        )
        guard actualByteCount > 0 else { return [] }

        return pids
            .prefix(Int(actualByteCount) / MemoryLayout<pid_t>.stride)
            .compactMap { processInfo(pid: Int32($0)) }
    }

    static func parseArguments(from buffer: [UInt8]) -> String? {
        guard buffer.count >= MemoryLayout<Int32>.size else { return nil }
        let argumentCount = buffer.withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(as: Int32.self)
        }
        guard argumentCount >= 0 else { return nil }

        let strings = buffer.dropFirst(MemoryLayout<Int32>.size)
            .split(separator: 0, omittingEmptySubsequences: true)
            .map { String(decoding: $0, as: UTF8.self) }
        guard strings.isEmpty == false else { return nil }

        let count = min(strings.count, Int(argumentCount) + 1)
        return strings.prefix(count).joined(separator: " ")
    }

    private func processInfo(pid: Int32) -> ProcessInfoRow? {
        guard pid > 0,
              let bsdInfo = bsdInfo(for: pid),
              let path = processPath(pid: pid) else { return nil }

        let name = processName(pid: pid, path: path)
        let args = shouldReadArguments(name: name, path: path)
            ? arguments(for: pid) ?? path
            : path
        let startedAt = Date(
            timeIntervalSince1970: Double(bsdInfo.pbi_start_tvsec) + Double(bsdInfo.pbi_start_tvusec) / 1_000_000
        )
        return ProcessInfoRow(pid: String(pid), startedAt: startedAt, args: args)
    }

    private func shouldReadArguments(name: String, path: String) -> Bool {
        let normalizedName = name.lowercased()
        if ["caffeinate", "claude", "codex", "cursor", "cursor-agent", "opencode"].contains(normalizedName) {
            return true
        }
        let normalizedPath = path.lowercased()
        return normalizedPath.contains("/codex.app/")
            || normalizedPath.contains("/cursor.app/")
            || normalizedPath.contains("/codexbar.app/")
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

    private func processName(pid: Int32, path: String) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let result = proc_name(pid, &buffer, UInt32(buffer.count))
        if result > 0 {
            return buffer.withUnsafeBufferPointer { pointer in
                guard let baseAddress = pointer.baseAddress else { return URL(fileURLWithPath: path).lastPathComponent }
                return String(cString: baseAddress)
            }
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func arguments(for pid: Int32) -> String? {
        var mib = [Int32](arrayLiteral: CTL_KERN, KERN_PROCARGS2, pid)
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }
        return Self.parseArguments(from: buffer)
    }
}
