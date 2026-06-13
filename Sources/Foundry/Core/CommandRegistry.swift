import Foundation

struct CommandResult: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: CommandIcon
    let score: Double
    let primaryAction: CommandAction
    let secondaryActions: [CommandAction]
}

struct CommandIcon: Hashable, Sendable {
    let fallback: String
    let filePath: String?
    let systemName: String?

    init(fallback: String, filePath: String? = nil, systemName: String? = nil) {
        self.fallback = fallback
        self.filePath = filePath
        self.systemName = systemName
    }
}

struct CommandAction: Hashable, Sendable {
    let id: String
    let title: String
    let kind: CommandActionKind

    static func == (lhs: CommandAction, rhs: CommandAction) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum CommandActionKind: Hashable, Sendable {
    case openApp(path: String, name: String)
    case openFile(path: String)
    case openURL(String)
    case openConfigFolder
    case runProcess(path: String, arguments: [String])
    case quit
    case log(String)
}

protocol CommandProvider: Sendable {
    var id: String { get }
    func results(matching query: String) async -> [CommandResult]
}

final class CommandRegistry: @unchecked Sendable {
    private let providers: [CommandProvider]
    private let usageRanking: UsageRankingStore
    private let indexingStatus: IndexingStatusStore

    init(providers: [CommandProvider], usageRanking: UsageRankingStore, indexingStatus: IndexingStatusStore) {
        self.providers = providers
        self.usageRanking = usageRanking
        self.indexingStatus = indexingStatus
    }

    static func defaultRegistry(config: ConfigService, diagnostics: DiagnosticsService) -> CommandRegistry {
        let usageRanking = UsageRankingStore(diagnostics: diagnostics)
        let indexingStatus = IndexingStatusStore()
        return CommandRegistry(
            providers: [
                AppSearchProvider(diagnostics: diagnostics),
                FileSearchProvider(diagnostics: diagnostics, indexingStatus: indexingStatus),
                SystemCommandProvider(diagnostics: diagnostics),
                BuiltInCommandProvider(config: config, diagnostics: diagnostics)
            ],
            usageRanking: usageRanking,
            indexingStatus: indexingStatus
        )
    }

    func results(matching query: String) async -> [CommandResult] {
        var allResults: [CommandResult] = []

        for provider in providers {
            guard Task.isCancelled == false else { return [] }
            allResults.append(contentsOf: await provider.results(matching: query))
        }

        return allResults
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

    func statusSummary(resultCount: Int, fallback: String) -> String {
        let resultLabel = resultCount == 1 ? "1 result" : "\(resultCount) results"
        guard let status = indexingStatus.summary() else {
            return resultCount > 0 ? resultLabel : fallback
        }
        return resultCount > 0 ? "\(resultLabel) · \(status)" : status
    }
}
