import Darwin
import Foundation

struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
    let cancelled: Bool

    var succeeded: Bool {
        exitCode == 0 && timedOut == false && cancelled == false
    }
}

enum ProcessRunnerError: Error, Equatable {
    case launchFailed(String)
    case cancelled
}

enum ProcessRunner {
    static func run(
        path: String,
        arguments: [String],
        timeout: TimeInterval = 10,
        outputLimit: Int = 2 * 1024 * 1024
    ) async throws -> ProcessResult {
        let control = ManagedProcessControl()
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        continuation.resume(returning: try runSynchronously(
                            path: path,
                            arguments: arguments,
                            timeout: timeout,
                            outputLimit: outputLimit,
                            control: control
                        ))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            control.requestTermination(cancelled: true)
        }

        if Task.isCancelled || result.cancelled {
            throw ProcessRunnerError.cancelled
        }
        return result
    }

    static func runSynchronously(
        path: String,
        arguments: [String],
        timeout: TimeInterval = 2,
        outputLimit: Int = 2 * 1024 * 1024
    ) -> ProcessResult? {
        try? runSynchronously(
            path: path,
            arguments: arguments,
            timeout: timeout,
            outputLimit: outputLimit,
            control: ManagedProcessControl()
        )
    }

    private static func runSynchronously(
        path: String,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int,
        control: ManagedProcessControl
    ) throws -> ProcessResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutBuffer = LimitedDataBuffer(limit: outputLimit)
        let stderrBuffer = LimitedDataBuffer(limit: outputLimit)
        let termination = DispatchSemaphore(value: 0)

        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty == false { stdoutBuffer.append(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty == false { stderrBuffer.append(data) }
        }
        process.terminationHandler = { _ in termination.signal() }

        control.attach(process)
        guard control.shouldTerminate == false else {
            clearHandlers(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
            throw ProcessRunnerError.cancelled
        }

        do {
            try process.run()
        } catch {
            clearHandlers(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }
        control.configureProcessGroup()

        if control.shouldTerminate {
            control.requestTermination(cancelled: true)
        }

        if timeout > 0, termination.wait(timeout: .now() + timeout) == .timedOut {
            control.requestTermination(cancelled: false)
            _ = termination.wait(timeout: .now() + 0.75)
        }

        if process.isRunning {
            control.forceTerminateIfRunning()
            process.waitUntilExit()
        }

        clearHandlers(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
        stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

        let flags = control.flags
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutBuffer.data, as: UTF8.self),
            stderr: String(decoding: stderrBuffer.data, as: UTF8.self),
            timedOut: flags.timedOut,
            cancelled: flags.cancelled
        )
    }

    private static func clearHandlers(stdoutPipe: Pipe, stderrPipe: Pipe) {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
    }
}

private final class ManagedProcessControl: @unchecked Sendable {
    struct Flags: Sendable {
        let timedOut: Bool
        let cancelled: Bool
    }

    private let lock = NSLock()
    private var process: Process?
    private var processGroupID: Int32 = -1
    private var timedOut = false
    private var cancelled = false

    var shouldTerminate: Bool {
        lock.withLock { timedOut || cancelled }
    }

    var flags: Flags {
        lock.withLock { Flags(timedOut: timedOut, cancelled: cancelled) }
    }

    func attach(_ process: Process) {
        let terminate = lock.withLock { () -> Bool in
            self.process = process
            return timedOut || cancelled
        }
        if terminate { process.terminate() }
    }

    func configureProcessGroup() {
        let pid = lock.withLock {
            guard let process, process.processIdentifier > 0 else { return Int32(-1) }
            return process.processIdentifier
        }
        guard pid > 0 else { return }
        guard setpgid(pid, pid) == 0 else { return }
        lock.withLock { processGroupID = pid }
    }

    func requestTermination(cancelled: Bool) {
        let process = lock.withLock { () -> Process? in
            if cancelled {
                self.cancelled = true
            } else {
                self.timedOut = true
            }
            return self.process
        }
        guard let process, process.isRunning else { return }
        process.terminate()
        let groupID = lock.withLock { processGroupID }
        if groupID > 0 { kill(-groupID, SIGTERM) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) {
            self.forceTerminateIfRunning()
        }
    }

    func forceTerminateIfRunning() {
        let values: (pid: Int32?, groupID: Int32) = lock.withLock {
            guard process?.isRunning == true else { return (nil, Int32(-1)) }
            return (process?.processIdentifier, processGroupID)
        }
        if values.groupID > 0 {
            kill(-values.groupID, SIGKILL)
        }
        if let pid = values.pid, pid > 0 {
            kill(pid, SIGKILL)
        }
    }
}

private final class LimitedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var storage = Data()

    init(limit: Int) {
        self.limit = max(limit, 1)
    }

    var data: Data {
        lock.withLock { storage }
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard storage.count < limit else { return }
        storage.append(data.prefix(limit - storage.count))
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
