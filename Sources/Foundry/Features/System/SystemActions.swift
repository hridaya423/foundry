import AppKit
import CoreAudio
import Foundation
import FoundryDomain
import FoundryServices
import os

protocol KeepAwakeProcessHandle: AnyObject {
    var isRunning: Bool { get }
    func stop()
}

final class KeepAwakeProcessOwner: Sendable {
    private let process = OSAllocatedUnfairLock<(any KeepAwakeProcessHandle)?>(uncheckedState: nil)

    var isActive: Bool {
        process.withLockUnchecked { $0?.isRunning == true }
    }

    func toggle(launch: () throws -> any KeepAwakeProcessHandle) throws -> Bool {
        try process.withLockUnchecked { process in
            if let running = process, running.isRunning {
                running.stop()
                process = nil
                return false
            }
            process = nil
            let launched = try launch()
            process = launched
            return true
        }
    }

    func stop() {
        process.withLockUnchecked { process in
            if process?.isRunning == true { process?.stop() }
            process = nil
        }
    }
}

final class NativeKeepAwakeProcess: KeepAwakeProcessHandle {
    private let process: Process

    init() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = Self.arguments(parentProcessID: ProcessInfo.processInfo.processIdentifier)
        try process.run()
        self.process = process
    }

    static func arguments(parentProcessID: Int32) -> [String] {
        ["-dimsu", "-w", String(parentProcessID)]
    }

    var isRunning: Bool { process.isRunning }

    func stop() {
        process.terminate()
    }
}

enum KeepAwakeController {
    private static let owner = KeepAwakeProcessOwner()

    static func toggle() throws -> Bool {
        try owner.toggle { try NativeKeepAwakeProcess() }
    }

    static func isActive() -> Bool {
        owner.isActive
    }

    static func stop() {
        owner.stop()
    }
}

enum AudioDeviceController {
    static func setDevice(id: AudioDeviceID, kind: AudioDeviceKind) throws {
        var device = id
        var address = AudioObjectPropertyAddress(
            mSelector: kind == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device)
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

struct TerminateProcessAction: ResultAction, Equatable {
    let pid: Int32

    var icon: String? { "xmark.circle" }
    var style: ActionStyle { .destructive }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        do {
            if kill(pid, SIGTERM) == 0 {
                ctx.diagnostics.log("Terminated process \(pid)")
                return ctx.finish(.success(message: String(localized: "Terminated process")), feedback: .success(String(localized: "Terminated process")))
            } else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
            }
        } catch {
            if isExecutionCancellation(error) {
                return .cancelled
            }
            ctx.diagnostics.log("Failed to terminate process \(pid): \(error.localizedDescription)")
            return ctx.finish(
                .failure(message: String(localized: "Could not terminate process"), retryable: true),
                 feedback: .failure(String(localized: "Could not terminate process")))
        }
    }
}

struct QuitApplicationAction: ResultAction, Equatable {
    let bundleID: String?
    let name: String

    var icon: String? { "app.badge.xmark" }
    var style: ActionStyle { .destructive }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let running = NSWorkspace.shared.runningApplications.first {
            ($0.bundleIdentifier == bundleID && bundleID != nil)
                || $0.localizedName == name
        }
        if let running {
            if running.terminate() || running.forceTerminate() {
                ctx.diagnostics.log("Quit \(name)")
                return ctx.finish(.success(message: String(localized: "Quit \(name)")), feedback: .success(String(localized: "Quit \(name)")))
            } else {
                ctx.diagnostics.log("Failed to quit \(name)")
                return ctx.finish(
                    .failure(message: String(localized: "Could not quit \(name)"), retryable: true),
                     feedback: .failure(String(localized: "Could not quit \(name)")))
            }
        } else {
            ctx.diagnostics.log("\(name) is not running")
            return .failure(message: String(localized: "\(name) is not running"), retryable: false)
        }
    }
}

struct ForceQuitApplicationAction: ResultAction, Equatable {
    let bundleID: String?
    let name: String

    var icon: String? { "exclamationmark.octagon" }
    var style: ActionStyle { .destructive }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        guard let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID && bundleID != nil
            || $0.localizedName == name }) else {
            return .failure(message: String(localized: "\(name) is not running"), retryable: false)
        }
        return running.forceTerminate()
            ? ctx.finish(.success(message: String(localized: "Force quit \(name)")), feedback: .success(String(localized: "Force quit \(name)")))
            : ctx.finish(
                .failure(message: String(localized: "Could not force quit \(name)"), retryable: true),
                 feedback: .failure(String(localized: "Could not force quit \(name)")))
    }
}

struct HideApplicationAction: ResultAction, Equatable {
    let bundleID: String
    let name: String

    var icon: String? { "eye.slash" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let hidden = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map { $0.hide() }.contains(true)
        if hidden {
            return ctx.finish(
                .success(message: String(localized: "Hid \(name)")),
                feedback: .success(String(localized: "Hid \(name)"))
            )
        }
        return .failure(message: String(localized: "\(name) is not running"), retryable: false)
    }
}

struct QuitAllApplicationsAction: ResultAction, Equatable {
    var icon: String? { "app.badge.xmark" }
    var style: ActionStyle { .destructive }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let spared: Set<String> = [Bundle.main.bundleIdentifier ?? "", "com.apple.finder"]
        let targets = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && spared.contains($0.bundleIdentifier ?? "") == false }
        let quit = targets.filter { $0.terminate() }.count
        return ctx.finish(
            .success(message: String(localized: "Asked \(quit) apps to quit")),
             feedback: .success(String(localized: "Asked \(quit) apps to quit")))
    }
}

struct ToggleKeepAwakeAction: ResultAction, Equatable {
    var icon: String? { "cup.and.saucer.fill" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        do {
            let state = try KeepAwakeController.toggle()
            ctx.diagnostics.log(state ? "Keep Awake enabled" : "Keep Awake disabled")
            return ctx.finish(.success(message: state ? "Keep Awake enabled" : "Keep Awake disabled"),
                feedback: .success(state ? "Keep Awake enabled" : "Keep Awake disabled"))
        } catch {
            ctx.diagnostics.log("Could not update Keep Awake: \(error.localizedDescription)")
            return ctx.finish(
                .failure(message: String(localized: "Could not update Keep Awake"), retryable: true),
                 feedback: .failure(String(localized: "Could not update Keep Awake")))
        }
    }
}

struct EmptyTrashAction: ResultAction, Equatable {
    var icon: String? { "trash.slash" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let prompt = await ctx.panel.requestPrompt(.confirmation(
            title: "Empty the Trash?",
            message: "Items in the Trash are permanently deleted. This cannot be undone.",
            confirmLabel: "Empty Trash",
            isDestructive: true
        ))
        guard prompt.confirmed else { return .cancelled }
        do {
            let result = try await ProcessRunner.run(
                path: "/usr/bin/osascript",
                arguments: ["-e", "tell application \"Finder\" to empty trash"],
                timeout: 60
            )
            guard result.succeeded else {
                return .failure(message: String(localized: "Finder could not empty the Trash"), retryable: true)
            }
            ctx.diagnostics.log("Emptied trash")
            ctx.emit(.feedback(.success("Trash emptied")))
            return .success(message: String(localized: "Trash emptied"))
        } catch {
            ctx.diagnostics.log("Empty Trash failed: \(error.localizedDescription)")
            return ctx.finish(.failure(message: String(localized: "Could not empty the Trash"), retryable: true))
        }
    }
}

struct ToggleDesktopIconsAction: ResultAction, Equatable {
    var icon: String? { "macwindow.on.rectangle" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let current = await BestEffort.attempt("read Finder CreateDesktop") {
            try await ProcessRunner.run(
                path: "/usr/bin/defaults",
                arguments: ["read", "com.apple.finder", "CreateDesktop"],
                timeout: 5
            )
        }
        let currentlyShown = current?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) != "0"
        let next = currentlyShown ? "0" : "1"
        do {
            _ = try await ProcessRunner.run(
                path: "/usr/bin/defaults",
                arguments: ["write", "com.apple.finder", "CreateDesktop", "-bool", next == "1" ? "true" : "false"],
                timeout: 5
            )
            _ = try await ProcessRunner.run(path: "/usr/bin/killall", arguments: ["Finder"], timeout: 5)
            let message = currentlyShown ? "Desktop icons hidden" : "Desktop icons shown"
            ctx.diagnostics.log(message)
            ctx.emit(.feedback(.success(message)))
            return .success(message: message)
        } catch {
            ctx.diagnostics.log("Desktop icon toggle failed: \(error.localizedDescription)")
            return ctx.finish(.failure(message: String(localized: "Could not toggle desktop icons"), retryable: true))
        }
    }
}

struct TerminatePortAction: ResultAction, Equatable {
    let port: Int

    init(_ port: Int) { self.port = port }

    var icon: String? { "network" }
    var style: ActionStyle { .destructive }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        do {
            let lookup = try await ProcessRunner.run(path: "/usr/sbin/lsof", arguments: ["-ti", "tcp:\(port)"], timeout: 3)
            let pids = lookup.stdout.split(whereSeparator: \.isNewline).map(String.init)
            guard lookup.succeeded, pids.isEmpty == false else {
                let message = "No process is listening on port \(port)"
                ctx.diagnostics.log(message)
                return ctx.finish(.failure(message: message, retryable: true), feedback: .failure(message))
            }
            var failed = false
            for pid in pids {
                let result = try await ProcessRunner.run(path: "/bin/kill", arguments: [pid], timeout: 3)
                failed = failed || !result.succeeded
            }
            let message = failed ? "Couldn't stop the process on port \(port)" : "Stopped port \(port)"
            ctx.diagnostics.log(message)
            return ctx.finish(failed ? .failure(message: message, retryable: true) : .success(message: message),
                feedback: failed ? .failure(message) : .success(message))
        } catch {
            if isExecutionCancellation(error) {
                return .cancelled
            }
            ctx.diagnostics.log("Failed to stop port \(port): \(error.localizedDescription)")
            return ctx.finish(.failure(message: String(localized: "Couldn't stop the process on port \(port)"), retryable: true),
                feedback: .failure(String(localized: "Couldn't stop the process on port \(port)")))
        }
    }
}

struct SetAudioDeviceAction: ResultAction, Equatable {
    let id: UInt32
    let kind: AudioDeviceKind

    var icon: String? { "speaker.wave.2.fill" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        do {
            try AudioDeviceController.setDevice(id: id, kind: kind)
            ctx.diagnostics.log("Updated \(kind == .output ? "output" : "input") audio device")
            return ctx.finish(.success(message: String(localized: "Audio device updated")), feedback: .success(String(localized: "Audio device updated")))
        } catch {
            ctx.diagnostics.log("Failed to switch audio device: \(error.localizedDescription)")
            return ctx.finish(
                .failure(message: String(localized: "Could not switch audio device"), retryable: true),
                 feedback: .failure(String(localized: "Could not switch audio device")))
        }
    }
}

struct RebuildAppAction: ResultAction, Equatable {
    var icon: String? { "hammer.fill" }
    var style: ActionStyle { .destructive }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        #if DEBUG
        guard let sourceRoot = SourceRootLocator.locate() else {
            ctx.diagnostics.log("Cannot rebuild Foundry: source root is unavailable")
            return .failure(message: String(localized: "Cannot rebuild Foundry"), retryable: false)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.currentDirectoryURL = sourceRoot
        process.arguments = ["-lc", "INSTALL_APP=1 ./scripts/build-app.sh", "foundry-rebuild"]
        do {
            try process.run()
            ctx.diagnostics.log("Started Foundry app rebuild")
            return .success(message: String(localized: "Started Foundry app rebuild"))
        } catch {
            ctx.diagnostics.log("Failed to rebuild Foundry app: \(error.localizedDescription)")
            return .failure(message: String(localized: "Failed to rebuild Foundry app"), retryable: true)
        }
        #else
        ctx.diagnostics.log("Cannot rebuild Foundry outside a debug build")
        return .failure(message: String(localized: "Cannot rebuild Foundry"), retryable: false)
        #endif
    }
}

struct RunProcessAction: ResultAction, Equatable {
    let path: String
    let arguments: [String]

    var icon: String? { "terminal" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        do {
            let result = try await ProcessRunner.run(path: path, arguments: arguments)
            let shortcut = path == ShortcutsProvider.cliPath ? arguments.last : nil
            guard result.succeeded else {
                ctx.diagnostics.log("Failed to run \(path)")
                return .failure(
                    message: shortcut.map { "“\($0)” failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))" } ?? "Failed to run " +
                        "process", retryable: true)
            }
            return .success(message: shortcut.map { "Ran “\($0)”" } ?? "Process completed")
        } catch {
            if isExecutionCancellation(error) {
                return .cancelled
            }
            ctx.diagnostics.log("Failed to run \(path): \(error.localizedDescription)")
            return .failure(message: String(localized: "Failed to run process"), retryable: true)
        }
    }
}
