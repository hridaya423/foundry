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
    case rebuildFileIndex
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
    private let diagnostics: DiagnosticsService

    init(providers: [CommandProvider], usageRanking: UsageRankingStore, indexingStatus: IndexingStatusStore, diagnostics: DiagnosticsService) {
        self.providers = providers
        self.usageRanking = usageRanking
        self.indexingStatus = indexingStatus
        self.diagnostics = diagnostics
    }

    static func defaultRegistry(
        config: ConfigService,
        diagnostics: DiagnosticsService,
        fileSearchProvider: FileSearchProvider? = nil,
        indexingStatus: IndexingStatusStore? = nil
    ) -> CommandRegistry {
        let usageRanking = UsageRankingStore(diagnostics: diagnostics)
        let indexingStatus = indexingStatus ?? IndexingStatusStore()
        let fileSearchProvider = fileSearchProvider ?? FileSearchProvider(diagnostics: diagnostics, indexingStatus: indexingStatus)
        return CommandRegistry(
            providers: [
                AppSearchProvider(diagnostics: diagnostics),
                fileSearchProvider,
                SystemCommandProvider(diagnostics: diagnostics),
                BuiltInCommandProvider(config: config, diagnostics: diagnostics)
            ],
            usageRanking: usageRanking,
            indexingStatus: indexingStatus,
            diagnostics: diagnostics
        )
    }

    func results(matching query: String) async -> [CommandResult] {
        var allResults: [CommandResult] = []
        var timings: [ProviderSearchTiming] = []

        await withTaskGroup(of: ProviderSearchResult.self) { group in
            for provider in providers {
                group.addTask {
                    let startedAt = Date().timeIntervalSinceReferenceDate
                    let results = await provider.results(matching: query)
                    let elapsedMilliseconds = (Date().timeIntervalSinceReferenceDate - startedAt) * 1_000
                    return ProviderSearchResult(providerID: provider.id, results: results, elapsedMilliseconds: elapsedMilliseconds)
                }
            }

            for await providerResult in group {
                guard Task.isCancelled == false else {
                    group.cancelAll()
                    return
                }
                allResults.append(contentsOf: providerResult.results)
                timings.append(ProviderSearchTiming(providerID: providerResult.providerID, elapsedMilliseconds: providerResult.elapsedMilliseconds))
            }
        }

        guard Task.isCancelled == false else { return [] }

        logSearchTimings(timings)

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

    private func logSearchTimings(_ timings: [ProviderSearchTiming]) {
        guard timings.isEmpty == false else { return }
        let summary = timings
            .sorted { $0.providerID < $1.providerID }
            .map { timing in
                "\(timing.providerID)=\(String(format: "%.1f", timing.elapsedMilliseconds))ms"
            }
            .joined(separator: " ")
        diagnostics.log("Search providers: \(summary)")
    }
}

private struct ProviderSearchResult: Sendable {
    let providerID: String
    let results: [CommandResult]
    let elapsedMilliseconds: Double
}

private struct ProviderSearchTiming {
    let providerID: String
    let elapsedMilliseconds: Double
}
