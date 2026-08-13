import Foundation
import FoundryDomain

enum CommandRoute: Codable, Equatable, Sendable {
    case quickAI(initialPrompt: String)
    case emojiPicker
    case fileShelf
    case clipboardHistory
    case snippets
    case fileConversion(path: String?)
    case camera
    case translator(text: String?, language: String?)
    case developerTools(tool: String?)
    case settings
    case home
    case mediaDownloads
}

struct CommandExecutionRequest: Sendable {
    let invocation: CommandInvocation
    let action: CommandAction

    init(
        commandID: String,
        action: CommandAction,
        source: CommandInvocationSource = .launcher,
        arguments: [String: String] = [:],
        context: [String: String] = [:],
        cancellationID: UUID = UUID()
    ) {
        invocation = CommandInvocation(
            commandID: commandID,
            arguments: arguments,
            source: source,
            context: context,
            cancellationID: cancellationID
        )
        self.action = action
    }
}

extension CommandExecutionRequest {
    var pasteRequest: (value: String, cursorOffset: Int, snippetID: String?)? {
        guard case let .pasteText(value, cursorOffset, snippetID) = action.kind else { return nil }
        return (value, cursorOffset, snippetID)
    }
}

enum CommandExecutionEvent: Sendable {
    case status(String)
    case downloadProgress(MediaDownloadProgress)
    case feedback(ActionFeedback)
}

enum CommandOutcome: Codable, Equatable, Sendable {
    case success(message: String?)
    case failure(message: String, retryable: Bool)
    case denied(message: String)
    case cancelled
    case open(route: CommandRoute)
    case stayOpen(message: String?)
    case refreshResults(message: String?)
    case copied(content: String)
    case pasted(content: String)
    case fileResults([URL])
    case followUp(actionIDs: [String])

    var shouldDismissPanel: Bool {
        switch self {
        case .open, .stayOpen, .refreshResults, .cancelled, .denied:
            false
        case .failure(_, let retryable):
            !retryable
        case .success, .copied, .pasted, .fileResults:
            true
        case .followUp:
            false
        }
    }
}

extension CommandOutcome {
    var isSuccessful: Bool {
        switch self {
        case .success, .copied, .pasted, .fileResults:
            true
        default:
            false
        }
    }
}

@MainActor
protocol CommandExecuting {
    func execute(
        _ request: CommandExecutionRequest,
        emit: @escaping @MainActor @Sendable (CommandExecutionEvent) -> Void
    ) async -> CommandOutcome

    func cancel(_ cancellationID: UUID)
}
