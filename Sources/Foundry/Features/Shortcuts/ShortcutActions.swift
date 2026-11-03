import Foundation
import FoundryDomain
import FoundryServices

enum ShortcutInput: Hashable, Sendable {
    case none, text(String), clipboard
}

struct RunShortcutAction: ResultAction, Equatable {
    let name: String
    var input: ShortcutInput = .none

    var icon: String? { "square.2.layers.3d" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        var arguments = ["run", name]
        let text: String? = switch input {
        case .none: nil
        case let .text(value): value
        case .clipboard: ctx.pasteboard.string(forType: .string) ?? ""
        }
        var inputFile: URL?
        if let text {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-shortcut-input-\(UUID().uuidString).txt")
            do {
                try Data(text.utf8).write(to: file, options: .atomic)
            } catch {
                return ctx.finish(.failure(message: String(localized: "Couldn't prepare the input for “\(name)”"), retryable: true),
                    feedback: .failure(String(localized: "Couldn't prepare the input")))
            }
            inputFile = file
            arguments += ["--input-path", file.path]
        }
        defer {
            if let inputFile { BestEffort.attempt("remove shortcut input") { try FileManager.default.removeItem(at: inputFile) } }
        }
        do {
            let result = try await ProcessRunner.run(path: ShortcutsProvider.cliPath, arguments: arguments)
            guard result.succeeded else {
                let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return ctx.finish(.failure(message: String(localized: "“\(name)” failed: \(reason)"), retryable: true),
                    feedback: .failure(String(localized: "“\(name)” failed")))
            }
            return .success(message: String(localized: "Ran “\(name)”"))
        } catch {
            if isExecutionCancellation(error) { return .cancelled }
            ctx.diagnostics.log("Failed to run shortcut \(name): \(error.localizedDescription)")
            return .failure(message: String(localized: "Couldn't run “\(name)”"), retryable: true)
        }
    }
}
