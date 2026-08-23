import AppKit
import Foundation
import FoundryServices

@MainActor
final class AgentMonitorState: ObservableObject {
    @Published private(set) var sessions: [AgentSessionCard] = []
    @Published private(set) var socketListening = false
    @Published private(set) var integrationStatuses: [AgentBridgeProvider: AgentIntegrationStatus] = [:]
    @Published private(set) var integrationError: String?

    private let sessionStore = AgentSessionStore()
    private let titleService = AgentTitleService()
    private let diagnostics: DiagnosticsService
    private var collector: any AgentMonitorCollecting
    private let socketServer = AgentEventSocketServer()
    private let integrationInstaller: AgentIntegrationInstaller
    private var pollingTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var titleTasks: [String: Task<Void, Never>] = [:]
    private var titleTaskIDs: [String: UUID] = [:]
    private var refreshRequested = false
    private var isRefreshing = false
    private var lifecycleGeneration = 0
    private var socketStarted = false

    init(
        integrationInstaller: AgentIntegrationInstaller = AgentIntegrationInstaller(),
        collector: any AgentMonitorCollecting = AgentMonitorCollector(),
        diagnostics: DiagnosticsService = DiagnosticsService()
    ) {
        self.integrationInstaller = integrationInstaller
        self.collector = collector
        self.diagnostics = diagnostics
        refreshIntegrationStatuses()
    }

    var visibleSessions: [AgentSessionCard] {
        Array(sessions.prefix(4))
    }

    var hiddenCount: Int {
        let active = sessions.filter { $0.status.isActive }
        return max(0, active.count - min(active.count, 1))
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
        startSocket()
        if pollingTask == nil {
            collector = AgentMonitorCollector()
        }
        refresh()
        guard pollingTask == nil else { return }
        pollingTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                do {
                    try await Task.sleep(for: FoundryPollingPolicy.current.agentsInterval)
                } catch {
                    return
                }
                guard Task.isCancelled == false else { return }
                self?.refresh()
            }
        }
    }

    func startSocket() {
        if socketStarted == false {
            socketStarted = socketServer.start { [weak self] envelope in
                guard let self else { return .rejected(error: "Agent monitor is unavailable") }
                return await self.ingest(envelope)
            }
            socketListening = socketStarted
        }
    }

    func stopPolling() {
        lifecycleGeneration += 1
        pollingTask?.cancel()
        pollingTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        titleTasks.values.forEach { $0.cancel() }
        titleTasks.removeAll()
        titleTaskIDs.removeAll()
        refreshRequested = false
        isRefreshing = false
    }

    func stop() {
        stopPolling()
        socketServer.stop()
        socketStarted = false
        socketListening = false
    }

    func integrationStatus(for provider: AgentBridgeProvider) -> AgentIntegrationStatus {
        integrationStatuses[provider] ?? integrationInstaller.status(for: provider)
    }

    func refreshIntegrationStatuses() {
        integrationStatuses = Dictionary(uniqueKeysWithValues: AgentBridgeProvider.allCases.map { provider in
            (provider, integrationInstaller.status(for: provider))
        })
    }

    func installIntegration(for provider: AgentBridgeProvider) {
        integrationError = nil
        do {
            try integrationInstaller.install(provider)
            refreshIntegrationStatuses()
        } catch {
            integrationError = error.localizedDescription
        }
    }

    func refresh() {
        refreshRequested = true
        guard isRefreshing == false else { return }

        isRefreshing = true
        refreshRequested = false
        let generation = lifecycleGeneration
        let collector = collector
        let diagnostics = self.diagnostics
        let span = diagnostics.startSpan("agents.refresh")
        refreshTask = Task { [weak self] in
            defer { diagnostics.endSpan(span) }
            let found = await Task.detached(priority: .utility) {
                collector.collect()
            }.value
            guard let self,
                  Task.isCancelled == false,
                  self.lifecycleGeneration == generation else { return }
            let merged = await self.sessionStore.reconcileObserved(found)
            self.sessions = merged
            self.requestMissingTitles(for: merged)
            self.isRefreshing = false
            self.refreshTask = nil
            if self.refreshRequested {
                self.refresh()
            }
        }
    }

    private func requestMissingTitles(for cards: [AgentSessionCard]) {
        for card in cards where card.needsTitleGeneration {
            guard titleTasks[card.id] == nil else { continue }
            let taskID = UUID()
            titleTaskIDs[card.id] = taskID
            titleTasks[card.id] = Task { [weak self] in
                defer {
                    if let self, self.titleTaskIDs[card.id] == taskID {
                        self.titleTaskIDs[card.id] = nil
                        self.titleTasks[card.id] = nil
                    }
                }
                guard let self else { return }
                guard let title = await self.titleService.title(for: card.id, prompt: card.title) else { return }
                guard Task.isCancelled == false else { return }
                let key = card.key ?? AgentSessionKey(provider: card.provider, rawSessionID: card.id)
                await self.sessionStore.updateTitle(title, for: key)
                let updatedSessions = await self.sessionStore.snapshot()
                if self.sessions != updatedSessions { self.sessions = updatedSessions }
            }
        }
    }

    private func ingest(_ envelope: AgentEventEnvelope) async -> AgentEventAck {
        let update = await sessionStore.apply(envelope)
        if sessions != update.cards { sessions = update.cards }
        guard update.accepted else {
            return .rejected(requestID: envelope.requestID, error: update.error ?? "Agent event rejected")
        }
        return .accepted(requestID: envelope.requestID)
    }

    func open(_ session: AgentSessionCard) {
        switch session.openTarget {
        case let .application(name, path, argument):
            guard session.capabilities.contains(.jumpApplication) else { return }
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
            guard session.capabilities.contains(.jumpTerminal) else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                return
            }
            let fullCommand = [cwd.map { "cd \($0.shellQuoted)" }, command].compactMap { $0 }.joined(separator: " && ")
            runAppleScript("tell application \"Terminal\" to do script \(fullCommand.appleScriptQuoted)\ntell application \"Terminal\" to activate")
        case let .deepLink(url):
            guard session.capabilities.contains(.jumpTask) else { return }
            NSWorkspace.shared.open(url)
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
    var title: String
    var subtitle: String
    var project: String?
    var workingDirectory: String?
    var model: String?
    var status: AgentSessionStatus
    var startedAt: Date?
    var updatedAt: Date?
    var openTarget: AgentOpenTarget
    var key: AgentSessionKey?
    var origin: AgentSessionOrigin
    var capabilities: AgentSessionCapabilities
    var parentSessionID: String?
    var attentionReason: AgentAttentionReason?
    var terminalLocator: AgentTerminalLocator?
    var needsTitleGeneration: Bool
    var isGeneratedTitle: Bool

    init(
        id: String,
        provider: AgentProviderKind,
        title: String,
        subtitle: String,
        project: String?,
        workingDirectory: String? = nil,
        model: String?,
        status: AgentSessionStatus,
        startedAt: Date?,
        updatedAt: Date?,
        openTarget: AgentOpenTarget,
        key: AgentSessionKey? = nil,
        origin: AgentSessionOrigin = .processFallback,
        capabilities: AgentSessionCapabilities = [.observe],
        parentSessionID: String? = nil,
        attentionReason: AgentAttentionReason? = nil,
        terminalLocator: AgentTerminalLocator? = nil,
        needsTitleGeneration: Bool = false,
        isGeneratedTitle: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.title = title
        self.subtitle = subtitle
        self.project = project
        self.workingDirectory = workingDirectory
        self.model = model
        self.status = status
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.openTarget = openTarget
        self.key = key
        self.origin = origin
        self.capabilities = capabilities
        self.parentSessionID = parentSessionID
        self.attentionReason = attentionReason
        self.terminalLocator = terminalLocator
        self.needsTitleGeneration = needsTitleGeneration
        self.isGeneratedTitle = isGeneratedTitle
    }
}

enum AgentProviderKind: String, Codable, Hashable, Sendable {
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

    var symbol: String {
        switch self {
        case .opencode: "chevron.left.forwardslash.chevron.right"
        case .claude: "bubble.left.and.bubble.right"
        case .cursor: "cursorarrow.rays"
        case .codex: "sparkles"
        case .gemini: "diamond"
        case .aider: "hammer"
        case .goose: "bird"
        case .amp: "bolt"
        case .qwen: "q.circle"
        case .t3code: "t.square"
        case .synara: "waveform"
        case .devin: "person.crop.circle"
        case .factory: "building.2"
        }
    }

}

enum AgentSessionStatus: String, Codable, Hashable, Sendable {
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
    case deepLink(URL)
}

private extension String {
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    var appleScriptQuoted: String {
        "\"" + replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
