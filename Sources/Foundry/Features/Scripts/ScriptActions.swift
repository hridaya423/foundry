import AppKit
import Foundation
import FoundryDomain
import FoundryServices

struct RunScriptAction: ResultAction, Equatable {
    let path: String
    let arguments: [String]
    let mode: ScriptOutputMode

    var icon: String? { "terminal" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let directory = (path as NSString).deletingLastPathComponent
        if ctx.scriptDirectories.isTrusted(directory) == false {
            guard await ctx.confirmScriptDirectory(directory) else {
                return ctx.finish(
                    .denied(message: String(localized: "Scripts in this folder are not trusted")),
                    feedback: .info(String(localized: "Script not run"))
                )
            }
            ctx.scriptDirectories.setTrusted(true, for: directory)
        }
        let name = (path as NSString).lastPathComponent
        do {
            let result = try await ProcessRunner.run(path: path, arguments: arguments, timeout: ctx.scriptTimeout,
                outputLimit: ctx.scriptOutputLimit, currentDirectoryURL: URL(fileURLWithPath: directory))
            let lastLine = { (text: String) in text.split(whereSeparator: \.isNewline).last.map(String.init) }
            if result.timedOut {
                return ctx.finish(.failure(message: String(localized: "\(name) timed out after \(Int(ctx.scriptTimeout)) s"), retryable: true),
                    feedback: .failure(String(localized: "\(name) timed out")))
            }
            guard result.succeeded else {
                let message = lastLine(result.stderr) ?? lastLine(result.stdout) ?? "\(name) exited with code \(result.exitCode)"
                return ctx.finish(.failure(message: message, retryable: true), feedback: .failure(message))
            }
            switch mode {
            case .silent:
                return .success(message: nil)
            case .compact, .inline:
                return ctx.finish(.success(message: lastLine(result.stdout) ?? "Ran \(name)"), feedback: .success(lastLine(result.stdout) ?? "Ran \(name)"))
            case .fullOutput:
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry \(name) output.txt")
                try Data((result.stdout + result.stderr).utf8).write(to: url, options: .atomic)
                _ = ctx.openURL(url)
                return .success(message: String(localized: "Opened output of \(name)"))
            }
        } catch {
            if isExecutionCancellation(error) { return .cancelled }
            return ctx.finish(.failure(message: String(localized: "Could not run \(name): \(error.localizedDescription)"), retryable: true),
                feedback: .failure(String(localized: "Could not run \(name)")))
        }
    }

    /// The ConfirmBar spec for first-run trust of a script directory.
    static func trustSpec(for directory: String) -> PanelPromptSpec {
        .confirmation(
            title: "Run scripts from “\((directory as NSString).lastPathComponent)”?",
            message: """
                Scripts in \(directory) can run any command as you. Only trust folders whose scripts you wrote or \
                reviewed. Foundry will not ask again for this folder.
                """,
            confirmLabel: "Trust and Run"
        )
    }
}
