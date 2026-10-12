import AppKit
import Foundation
import FoundryDomain
import FoundryServices
import os

/// Resume-once gate for completion-handler APIs: the launch completion may
/// win the race against cancellation from either side.
final class ContinuationGate<Value: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Value, Never>?
        var result: Value?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func install(_ continuation: CheckedContinuation<Value, Never>) {
        let pending: Value? = state.withLock { state in
            if let result = state.result {
                state.result = nil
                return result
            }
            state.continuation = continuation
            return nil
        }
        if let pending { continuation.resume(returning: pending) }
    }

    @discardableResult
    func resume(_ result: Value) -> Bool {
        let continuation: CheckedContinuation<Value, Never>? = state.withLock { state in
            guard state.result == nil else { return nil }
            guard let installed = state.continuation else {
                state.result = result
                return nil
            }
            state.continuation = nil
            return installed
        }
        guard let continuation else { return false }
        continuation.resume(returning: result)
        return true
    }
}

/// `NSWorkspace.open(_:withApplicationAt:)` as an awaitable Bool.
func openURLs(_ urls: [URL], withAppAt appURL: URL) async -> Bool {
    await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            continuation.resume(returning: error == nil)
        }
    }
}

func isExecutionCancellation(_ error: Error) -> Bool {
    if Task.isCancelled { return true }
    return (error as? ProcessRunnerError) == .cancelled
}

struct OpenAppAction: ResultAction, Equatable {
    let path: String
    let name: String

    var icon: String? { "arrow.up.right.square" }
    var resultSection: ResultSection? { .applications }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let configuration = NSWorkspace.OpenConfiguration()
        let completion = ContinuationGate<CommandOutcome>()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                completion.install(continuation)
                if Task.isCancelled {
                    completion.resume(.cancelled)
                    return
                }
                ctx.openApplication(URL(fileURLWithPath: path), configuration) { [diagnostics = ctx.diagnostics] _, error in
                    Task { @MainActor in
                        let outcome: CommandOutcome
                        if let error {
                            diagnostics.log("Failed to launch \(name): \(error.localizedDescription)")
                            outcome = .failure(message: String(localized: "Could not open \(name)"), retryable: true)
                        } else {
                            diagnostics.log("Launched app: \(name)")
                            outcome = .success(message: String(localized: "Opened \(name)"))
                        }
                        if completion.resume(outcome), case .failure = outcome {
                            ctx.emit(.feedback(.failure("Could not open \(name)")))
                        }
                    }
                }
            }
        }, onCancel: { completion.resume(.cancelled) })
    }
}

struct OpenURLAction: ResultAction, Equatable {
    let value: String

    init(_ value: String) { self.value = value }

    var icon: String? { "arrow.up.right.square" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        guard let url = URL(string: value) else {
            ctx.diagnostics.log("Invalid URL: \(value)")
            return ctx.finish(
                .failure(message: String(localized: "That link isn't a valid URL"), retryable: false),
                 feedback: .failure(String(localized: "That link isn't a valid URL")))
        }
        if ctx.openURL(url) == false {
            return ctx.finish(
                .failure(message: String(localized: "Could not open link"), retryable: true),
                 feedback: .failure(String(localized: "Could not open link")))
        }
        return .success(message: String(localized: "Opened link"))
    }
}

struct OpenURLWithAppAction: ResultAction, Equatable {
    let url: String
    let bundleID: String

    var icon: String? { "arrow.up.right.square" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        guard let url = URL(string: self.url) else {
            return ctx.finish(
                .failure(message: String(localized: "That link isn't valid"), retryable: false),
                 feedback: .failure(String(localized: "That link isn't valid")))
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return ctx.finish(
                .failure(message: String(localized: "That app isn't installed"), retryable: false),
                 feedback: .failure(String(localized: "That app isn't installed")))
        }
        if await openURLs([url], withAppAt: appURL) == false {
            return ctx.finish(
                .failure(message: String(localized: "Could not open link with that app"), retryable: true),
                 feedback: .failure(String(localized: "Could not open link with that app")))
        }
        return .success(message: String(localized: "Opened link"))
    }
}

struct OpenConfigFolderAction: ResultAction, Equatable {
    var icon: String? { "arrow.up.right.square" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let folder = ConfigService.configURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if NSWorkspace.shared.open(folder) == false {
                return ctx.finish(
                    .failure(message: String(localized: "Could not open Foundry folder"), retryable: true),
                     feedback: .failure(String(localized: "Could not open Foundry folder")))
            }
            return .success(message: String(localized: "Opened Foundry folder"))
        } catch {
            return ctx.finish(
                .failure(message: String(localized: "Could not create Foundry folder"), retryable: true),
                 feedback: .failure(String(localized: "Could not create Foundry folder")))
        }
    }
}

struct OpenFileWithAppAction: ResultAction, Equatable {
    let path: String
    let appPath: String

    var icon: String? { "arrow.up.right.square" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        if await openURLs([URL(fileURLWithPath: path)], withAppAt: URL(fileURLWithPath: appPath)) == false {
            return ctx.finish(
                .failure(message: String(localized: "Could not open file with that app"), retryable: true),
                 feedback: .failure(String(localized: "Could not open file with that app")))
        }
        return .success(message: String(localized: "Opened file"))
    }
}
