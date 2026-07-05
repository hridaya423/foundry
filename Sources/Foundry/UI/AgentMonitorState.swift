import AppKit
import Foundation

@MainActor
final class AgentMonitorState: ObservableObject {
    @Published private(set) var sessions: [AgentSessionCard] = []

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?

    var visibleSessions: [AgentSessionCard] {
        Array(sessions.prefix(4))
    }

    var hiddenCount: Int {
        max(0, sessions.count - visibleSessions.count)
    }

    var needsInputCount: Int {
        sessions.filter { $0.status == .needsInput }.count
    }

    var liveCount: Int {
        sessions.filter { $0.status.isLive }.count
    }

    var reviewCount: Int {
        sessions.filter { $0.status == .reviewReady }.count
    }

    var summary: String {
        guard sessions.isEmpty == false else { return "No agents running" }
        if liveCount > 0 { return "\(liveCount) live · \(sessions.count) tracked" }
        return "\(sessions.count) recent agent\(sessions.count == 1 ? "" : "s")"
    }

    func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let found = await Task.detached(priority: .utility) {
                AgentMonitorService.collect()
            }.value
            guard Task.isCancelled == false else { return }
            self?.sessions = found
        }
    }

    func open(_ session: AgentSessionCard) {
        switch session.openTarget {
        case let .application(name, path, argument):
            if let path {
                let configuration = NSWorkspace.OpenConfiguration()
                if let argument { configuration.arguments = [argument] }
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration)
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
                let configuration = NSWorkspace.OpenConfiguration()
                if let argument { configuration.arguments = [argument] }
                NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/\(name).app"))
            }
        case let .terminal(command, cwd):
            let fullCommand = [cwd.map { "cd \($0.shellQuoted)" }, command].compactMap { $0 }.joined(separator: " && ")
            runAppleScript("tell application \"Terminal\" to do script \(fullCommand.appleScriptQuoted)\ntell application \"Terminal\" to activate")
        }
    }

    private func runAppleScript(_ source: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        try? process.run()
    }
}

struct AgentSessionCard: Identifiable, Hashable, Sendable {
    let id: String
    let provider: AgentProviderKind
    let title: String
    let subtitle: String
    let project: String?
    let model: String?
    let status: AgentSessionStatus
    let startedAt: Date?
    let updatedAt: Date?
    let openTarget: AgentOpenTarget
}

enum AgentProviderKind: String, Hashable, Sendable {
    case opencode = "OpenCode"
    case claude = "Claude"
    case cursor = "Cursor"
    case codex = "Codex"
    case gemini = "Gemini"
    case aider = "Aider"
    case goose = "Goose"
    case amp = "Amp"
    case qwen = "Qwen"
    case t3code = "T3 Code"
    case synara = "Synara"
    case devin = "Devin"
    case factory = "Factory"

    var logoURL: URL? {
        switch self {
        case .opencode:
            favicon("opencode.ai")
        case .claude:
            favicon("claude.ai")
        case .cursor:
            favicon("cursor.com")
        case .codex:
            favicon("openai.com")
        case .gemini:
            favicon("gemini.google.com")
        case .aider:
            favicon("aider.chat")
        case .goose:
            favicon("block.github.io")
        case .amp:
            favicon("ampcode.com")
        case .qwen:
            favicon("chat.qwen.ai")
        case .t3code:
            favicon("t3.codes")
        case .synara:
            favicon("trysynara.com")
        case .devin:
            favicon("devin.ai")
        case .factory:
            favicon("factory.ai")
        }
    }

    private func favicon(_ domain: String) -> URL? {
        URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=64")
    }
}

enum AgentSessionStatus: String, Hashable, Sendable {
    case working = "Working"
    case needsInput = "Needs input"
    case reviewReady = "Review ready"
    case planning = "Planning"
    case idle = "Idle"
    case completed = "Completed"
    case failed = "Failed"
    case running = "Running"
    case recent = "Recent"

    var isActive: Bool {
        self == .working || self == .needsInput || self == .running || self == .reviewReady || self == .planning
    }

    var isLive: Bool {
        self == .working || self == .running
    }

    var sortPriority: Int {
        switch self {
        case .needsInput: 0
        case .working, .running: 1
        case .reviewReady: 2
        case .planning: 3
        case .failed: 4
        case .completed: 5
        case .idle, .recent: 6
        }
    }
}

enum AgentOpenTarget: Hashable, Sendable {
    case application(name: String, path: String? = nil, argument: String? = nil)
    case terminal(command: String, cwd: String? = nil)
}

private extension String {
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    var appleScriptQuoted: String {
        "\"" + replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
