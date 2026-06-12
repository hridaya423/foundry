import Foundation

struct CommandResult: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: CommandIcon
    let score: Double
    let primaryAction: CommandAction
    let secondaryActions: [CommandAction]
}

struct CommandIcon: Hashable {
    let fallback: String
    let filePath: String?
    let systemName: String?

    init(fallback: String, filePath: String? = nil, systemName: String? = nil) {
        self.fallback = fallback
        self.filePath = filePath
        self.systemName = systemName
    }
}

struct CommandAction: Hashable {
    let id: String
    let title: String
    let perform: () -> Void

    static func == (lhs: CommandAction, rhs: CommandAction) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

protocol CommandProvider {
    var id: String { get }
    func results(matching query: String) -> [CommandResult]
}

final class CommandRegistry {
    private let providers: [CommandProvider]
    private let usageRanking: UsageRankingStore

    init(providers: [CommandProvider], usageRanking: UsageRankingStore) {
        self.providers = providers
        self.usageRanking = usageRanking
    }

    static func defaultRegistry(config: ConfigService, diagnostics: DiagnosticsService) -> CommandRegistry {
        let usageRanking = UsageRankingStore(diagnostics: diagnostics)
        return CommandRegistry(
            providers: [
                AppSearchProvider(diagnostics: diagnostics),
                SystemCommandProvider(diagnostics: diagnostics),
                BuiltInCommandProvider(config: config, diagnostics: diagnostics)
            ],
            usageRanking: usageRanking
        )
    }

    func results(matching query: String) -> [CommandResult] {
        providers
            .flatMap { $0.results(matching: query) }
            .sorted { lhs, rhs in
                let lhsScore = usageRanking.adjustedScore(for: lhs)
                let rhsScore = usageRanking.adjustedScore(for: rhs)
                if lhsScore == rhsScore {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhsScore > rhsScore
            }
            .prefix(12)
            .map { $0 }
    }

    func recordExecution(resultID: String) {
        usageRanking.recordExecution(resultID: resultID)
    }
}
