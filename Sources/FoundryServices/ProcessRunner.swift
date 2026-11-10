import Darwin
import Foundation
import os

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool
    public let cancelled: Bool

    public var succeeded: Bool {
        exitCode == 0 && timedOut == false && cancelled == false
    }
}

public struct ProcessOutputLine: Sendable, Equatable {
    public enum Stream: Sendable, Equatable {
        case stdout
        case stderr
    }

    public let stream: Stream
    public let line: String

    public init(stream: Stream, line: String) {
        self.stream = stream
        self.line = line
    }
}

public enum ProcessRunnerError: Error, Equatable {
    case launchFailed(String)
    case cancelled
}

public protocol ProcessRunning: Sendable {
    func run(path: String, arguments: [String], timeout: TimeInterval, outputLimit: Int, environment: [String: String]?, currentDirectoryURL: URL?,
        onOutput: (@Sendable (ProcessOutputLine) -> Void)?) async throws -> ProcessResult
}

public struct SystemProcessRunner: ProcessRunning, Sendable {
    public init() {}
    public func run(
        path: String,
        arguments: [String],
        timeout: TimeInterval = 10,
        outputLimit: Int = 2 * 1024 * 1024,
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        onOutput: (@Sendable (ProcessOutputLine) -> Void)? = nil
    ) async throws -> ProcessResult {
        try await ProcessRunner.run(
            path: path,
            arguments: arguments,
            timeout: timeout,
            outputLimit: outputLimit,
            environment: environment,
            currentDirectoryURL: currentDirectoryURL,
            onOutput: onOutput
        )
    }
}

public enum ProcessRunner {
    public static func run(
        path: String,
        arguments: [String],
        timeout: TimeInterval = 10,
        outputLimit: Int = 2 * 1024 * 1024,
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        onOutput: (@Sendable (ProcessOutputLine) -> Void)? = nil
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
                             environment: environment,
                             currentDirectoryURL: currentDirectoryURL,
                            onOutput: onOutput,
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

    public static func runSynchronously(
        path: String,
        arguments: [String],
        timeout: TimeInterval = 2,
        outputLimit: Int = 2 * 1024 * 1024,
        onOutput: (@Sendable (ProcessOutputLine) -> Void)? = nil
    ) -> ProcessResult? {
        BestEffort.attempt("run \(path)") {
            try runSynchronously(
                path: path,
                arguments: arguments,
                timeout: timeout,
                outputLimit: outputLimit,
                onOutput: onOutput,
                control: ManagedProcessControl()
            )
        }
    }

    private static func runSynchronously(
        path: String,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int,
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        onOutput: (@Sendable (ProcessOutputLine) -> Void)?,
        control: ManagedProcessControl
    ) throws -> ProcessResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutBuffer = LimitedDataBuffer(limit: outputLimit)
        let stderrBuffer = LimitedDataBuffer(limit: outputLimit)
        let stdoutLines = ProcessOutputLineBuffer(stream: .stdout, limit: outputLimit, handler: onOutput)
        let stderrLines = ProcessOutputLineBuffer(stream: .stderr, limit: outputLimit, handler: onOutput)
        let termination = DispatchSemaphore(value: 0)

        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty == false {
                stdoutBuffer.append(data)
                stdoutLines.append(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty == false {
                stderrBuffer.append(data)
                stderrLines.append(data)
            }
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
        let stdoutRemainder = drainWithoutWaiting(stdoutPipe.fileHandleForReading)
        let stderrRemainder = drainWithoutWaiting(stderrPipe.fileHandleForReading)
        stdoutBuffer.append(stdoutRemainder)
        stderrBuffer.append(stderrRemainder)
        stdoutLines.append(stdoutRemainder)
        stderrLines.append(stderrRemainder)
        stdoutLines.finish()
        stderrLines.finish()

        let flags = control.flags
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutBuffer.data, as: UTF8.self),
            stderr: String(decoding: stderrBuffer.data, as: UTF8.self),
            timedOut: flags.timedOut,
            cancelled: flags.cancelled
        )
    }

    /// Reads what is already in the pipe: a background child the command left behind may hold it open for much longer.
    private static func drainWithoutWaiting(_ handle: FileHandle) -> Data {
        let descriptor = handle.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else { return data }
            data.append(buffer, count: count)
        }
    }

    private static func clearHandlers(stdoutPipe: Pipe, stderrPipe: Pipe) {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
    }
}

private final class ManagedProcessControl: Sendable {
    struct Flags: Sendable {
        let timedOut: Bool
        let cancelled: Bool
    }

    private struct State {
        var process: Process?
        var processGroupID: Int32 = -1
        var timedOut = false
        var cancelled = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var shouldTerminate: Bool {
        state.withLock { $0.timedOut || $0.cancelled }
    }

    var flags: Flags {
        state.withLock { Flags(timedOut: $0.timedOut, cancelled: $0.cancelled) }
    }

    func attach(_ process: Process) {
        state.withLock {
            $0.process = process
        }
    }

    func configureProcessGroup() {
        let pid = state.withLock { state -> Int32 in
            guard let process = state.process, process.processIdentifier > 0 else { return Int32(-1) }
            return process.processIdentifier
        }
        guard pid > 0 else { return }
        guard getpgid(pid) == pid || setpgid(pid, pid) == 0 else { return }
        state.withLock { $0.processGroupID = pid }
    }

    func requestTermination(cancelled: Bool) {
        let process = state.withLock { state -> Process? in
            if cancelled {
                state.cancelled = true
            } else {
                state.timedOut = true
            }
            return state.process
        }
        guard let process, process.isRunning else { return }
        process.terminate()
        let groupID = state.withLock { $0.processGroupID }
        if groupID > 0 { kill(-groupID, SIGTERM) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) {
            self.forceTerminateIfRunning()
        }
    }

    func forceTerminateIfRunning() {
        let values: (pid: Int32?, groupID: Int32) = state.withLock { state in
            guard state.process?.isRunning == true else { return (nil, Int32(-1)) }
            return (state.process?.processIdentifier, state.processGroupID)
        }
        if values.groupID > 0 {
            kill(-values.groupID, SIGKILL)
        }
        if let pid = values.pid, pid > 0 {
            kill(pid, SIGKILL)
        }
    }
}

private final class LimitedDataBuffer: Sendable {
    private let limit: Int
    private let storage = OSAllocatedUnfairLock(initialState: Data())

    init(limit: Int) {
        self.limit = max(limit, 1)
    }

    var data: Data {
        storage.withLock { $0 }
    }

    func append(_ data: Data) {
        storage.withLock { storage in
            guard storage.count < limit else { return }
            storage.append(data.prefix(limit - storage.count))
        }
    }
}

private final class ProcessOutputLineBuffer: Sendable {
    private struct State {
        var pending = Data()
        var finished = false
    }

    private let stream: ProcessOutputLine.Stream
    private let limit: Int
    private let handler: (@Sendable (ProcessOutputLine) -> Void)?
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(stream: ProcessOutputLine.Stream, limit: Int, handler: (@Sendable (ProcessOutputLine) -> Void)?) {
        self.stream = stream
        self.limit = max(limit, 1)
        self.handler = handler
    }

    func append(_ data: Data) {
        state.withLock { state in
            state.pending.append(data)
            if state.pending.count > limit {
                state.pending = state.pending.suffix(limit)
            }
            emitCompleteLines(&state)
            if state.finished { emitRemainder(&state) }
        }
    }

    func finish() {
        state.withLock { state in
            state.finished = true
            emitRemainder(&state)
        }
    }

    private func emitCompleteLines(_ state: inout State) {
        while let newline = state.pending.firstIndex(of: UInt8(ascii: "\n")) {
            emitLine(state.pending[..<newline])
            state.pending.removeSubrange(...newline)
        }
    }

    private func emitRemainder(_ state: inout State) {
        guard state.pending.isEmpty == false else { return }
        emitLine(state.pending)
        state.pending.removeAll()
    }

    private func emitLine(_ data: Data.SubSequence) {
        var line = data
        if line.last == UInt8(ascii: "\r") { line = line.dropLast() }
        guard line.isEmpty == false else { return }
        handler?(ProcessOutputLine(stream: stream, line: String(decoding: line, as: UTF8.self)))
    }
}
