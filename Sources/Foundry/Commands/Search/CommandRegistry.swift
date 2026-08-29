import Foundation
import FoundryDomain
import FoundryServices

final class CommandRegistry: @unchecked Sendable {
    private let providers: [CommandProvider]
    private let usageRanking: UsageRankingStore
    private let diagnostics: DiagnosticsService
    private let providerHealth: ProviderHealthStore
    private let providerScheduler: CommandProviderScheduler
    private let ranker: CommandRanker
    private let configService: ConfigService?
    private let catalogCache: CommandCatalogCache

    init(providers: [CommandProvider], usageRanking: UsageRankingStore, diagnostics: DiagnosticsService, providerHealth: ProviderHealthStore = ProviderHealthStore(), configService: ConfigService? = nil) {
        self.providers = providers
        self.usageRanking = usageRanking
        self.diagnostics = diagnostics
        self.providerHealth = providerHealth
        self.providerScheduler = CommandProviderScheduler(diagnostics: diagnostics, providerHealth: providerHealth)
        self.ranker = CommandRanker(usageRanking: usageRanking, configService: configService)
        self.configService = configService
        self.catalogCache = CommandCatalogCache(scheduler: providerScheduler)
    }

    static func defaultRegistry(
        config: ConfigService,
        diagnostics: DiagnosticsService,
        snippetStore: any SnippetStore = FileSnippetStore(),
        usageRanking: UsageRankingStore? = nil
    ) -> CommandRegistry {
        return CommandRegistry(
            providers: [
                AppSearchProvider(diagnostics: diagnostics),
                CalculatorProvider(),
                DeveloperToolsProvider(),
                MacUtilitiesProvider(),
                TranslationProvider(),
                AIProvider(config: config, diagnostics: diagnostics),
                AppleNotesProvider(),
                BrowserProvider(),
                LibraryProvider(store: snippetStore),
                MediaDownloadProvider(),
                CameraCommandProvider(),
                SystemCommandProvider(diagnostics: diagnostics),
                WindowManagementProvider(),
                BuiltInCommandProvider(config: config, diagnostics: diagnostics)
            ],
            usageRanking: usageRanking ?? UsageRankingStore(diagnostics: diagnostics),
            diagnostics: diagnostics,
            configService: config
        )
    }

    func results(matching query: String) async -> [CommandResult] {
        await results(matching: query, customAliases: customAliases)
    }

    func immediateResults(matching query: String) async -> [CommandResult] {
        await immediateSearchPhase(matching: query).results
    }

    func immediateSearchPhase(matching query: String) async -> CommandSearchPhase {
        let activeProviders = enabledProviders.filter {
            $0.searchPolicy.tier == .immediate && $0.isActive(for: query)
        }
        let (providerCandidates, timings) = await collectCandidates(query: query, providers: activeProviders, aliases: customAliases, timeout: .milliseconds(80))
        var candidates = providerCandidates.filter { isCommandEnabled($0.result) }
        let sensitivity = configService?.current.searchSensitivity ?? .medium

        for provider in supplementalProviders {
            candidates.append(contentsOf: provider.supplementalResults(matching: query, sensitivity: sensitivity).enumerated().map { index, result in
                RankCandidate(result: result, providerID: provider.id, sourceOrder: index)
            })
        }

        candidates = mediaOnlyCandidates(candidates, isMediaQuery: isMediaQuery(query))

        return CommandSearchPhase(
            results: Array(ranker.ordered(ranker.deduplicated(candidates), query: query).prefix(Self.resultLimit(for: query))),
            completedProviderIDs: Set(timings.compactMap { timing in
                timing.status == .success ? timing.providerID : nil
            })
        )
    }

    func completeResults(
        matching query: String,
        initialResults: [CommandResult],
        completedProviderIDs: Set<String> = []
    ) async -> [CommandResult] {
        let activeProviders = enabledProviders.filter { $0.isActive(for: query) }
        let providers = activeProviders.filter { provider in
            provider.searchPolicy.tier == .deferred || completedProviderIDs.contains(provider.id) == false
        }
        let (providerCandidates, timings) = await collectCandidates(query: query, providers: providers, aliases: customAliases, timeout: .milliseconds(250))
        var candidates = initialResults.enumerated().map { index, result in
            RankCandidate(result: result, providerID: "foundry.immediate", sourceOrder: index)
        }
        candidates.append(contentsOf: providerCandidates)
        let sensitivity = configService?.current.searchSensitivity ?? .medium
        var existingIDs = Set(candidates.map { $0.result.id })

        for provider in supplementalProviders {
            candidates.append(contentsOf: provider.supplementalResults(matching: query, sensitivity: sensitivity).enumerated().compactMap { index, result in
                guard existingIDs.insert(result.id).inserted else { return nil }
                return RankCandidate(result: result, providerID: provider.id, sourceOrder: index)
            })
        }

        candidates = ranker.deduplicated(candidates.filter { isCommandEnabled($0.result) })
        let mediaQuery = isMediaQuery(query)
        candidates = mediaOnlyCandidates(candidates, isMediaQuery: mediaQuery)
        if candidates.isEmpty && mediaQuery == false {
            for provider in activeProviders {
                guard isFallbackEligible(for: provider) else { continue }
                let fallbackResults = (try? await provider.fallbackResults(matching: query, sensitivity: sensitivity)) ?? []
                let eligibleResults = fallbackResults.filter { isFallbackEligible(for: $0) && isCommandEnabled($0) }
                candidates.append(contentsOf: eligibleResults.enumerated().map { index, result in
                    RankCandidate(result: result, providerID: provider.id, sourceOrder: index)
                })
                if eligibleResults.isEmpty == false { break }
            }
        }
        if candidates.isEmpty && mediaQuery == false {
            let prompt = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if prompt.isEmpty == false {
                candidates.append(RankCandidate(result: CommandResult(
                    id: "foundry.quick.\(AIRequestIdentifier.make(prompt: prompt, backend: .appleFoundationModels))",
                    title: "Ask AI about \(prompt)",
                    subtitle: "Open the research assistant",
                    icon: CommandIcon(fallback: "AI", systemName: "sparkles"),
                    primaryAction: CommandAction(id: "ai.quick", title: "Ask AI", kind: .openQuickAI(prompt: prompt)),
                    secondaryActions: []
                ), providerID: "foundry.ai", sourceOrder: 0))
            }
        }

        logSearchTimings(timings)
        return Array(ranker.ordered(candidates, query: query).prefix(Self.resultLimit(for: query)))
    }

    func results(matching query: String, customAliases: [String: [String]]) async -> [CommandResult] {
        let activeProviders = enabledProviders.filter { $0.isActive(for: query) }
        let (providerCandidates, timings) = await collectCandidates(query: query, providers: activeProviders, aliases: customAliases, timeout: .milliseconds(250))
        var allCandidates = providerCandidates

        guard Task.isCancelled == false else { return [] }

        let sensitivity = configService?.current.searchSensitivity ?? .medium
        for provider in supplementalProviders {
            allCandidates.append(contentsOf: provider.supplementalResults(matching: query, sensitivity: sensitivity).enumerated().map { index, result in
                RankCandidate(result: result, providerID: provider.id, sourceOrder: index)
            })
        }
        let mediaQuery = isMediaQuery(query)
        allCandidates = mediaOnlyCandidates(allCandidates, isMediaQuery: mediaQuery)
        if allCandidates.isEmpty && mediaQuery == false {
            for provider in activeProviders {
                guard isFallbackEligible(for: provider) else { continue }
                let fallbackResults = (try? await provider.fallbackResults(matching: query, sensitivity: sensitivity)) ?? []
                let eligibleResults = fallbackResults.filter { isFallbackEligible(for: $0) }
                allCandidates.append(contentsOf: eligibleResults.enumerated().map { index, result in
                    RankCandidate(result: result, providerID: provider.id, sourceOrder: index)
                })
                if eligibleResults.isEmpty == false { break }
            }
        }

        allCandidates = ranker.deduplicated(allCandidates.filter { isCommandEnabled($0.result) })

        if allCandidates.isEmpty && mediaQuery == false {
            let prompt = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if prompt.isEmpty == false {
                allCandidates.append(RankCandidate(result: CommandResult(
                    id: "foundry.quick.\(AIRequestIdentifier.make(prompt: prompt, backend: .appleFoundationModels))",
                    title: "Ask AI about \(prompt)",
                    subtitle: "Open the research assistant",
                    icon: CommandIcon(fallback: "AI", systemName: "sparkles"),
                    primaryAction: CommandAction(id: "ai.quick", title: "Ask AI", kind: .openQuickAI(prompt: prompt)),
                    secondaryActions: []
                ), providerID: "foundry.ai", sourceOrder: 0))
            }
        }

        logSearchTimings(timings)

        return ranker.ordered(allCandidates, query: query)
            .prefix(Self.resultLimit(for: query))
            .map { $0 }
    }

    func homeResults() async -> [CommandResult] {
        let activeProviders = enabledProviders
        var allCandidates: [RankCandidate] = []
        await withTaskGroup(of: [CommandResult].self) { group in
            let deadline = ContinuousClock().now.advanced(by: .milliseconds(400))
            for provider in activeProviders {
                group.addTask {
                    let span = self.diagnostics.startSpan("home.provider.\(provider.id)")
                    defer { self.diagnostics.endSpan(span) }
                    let outcome = await self.providerScheduler.defaults(for: provider, deadline: deadline)
                    return outcome.value ?? []
                }
            }

            for await results in group {
                allCandidates.append(contentsOf: results.enumerated().map { index, result in
                    RankCandidate(result: result, providerID: "", sourceOrder: index)
                })
            }
        }

        let sorted = ranker.ordered(allCandidates.filter { isCommandEnabled($0.result) }, query: nil)

        let apps = sorted.filter { result in
            if case .openApp = result.primaryAction.kind { return true }
            return false
        }
        let commands = sorted.filter { result in
            if case .openApp = result.primaryAction.kind { return false }
            return true
        }

        return Array(apps.prefix(6) + commands.prefix(5))
    }

    func recordExecution(resultID: String, query: String? = nil) {
        usageRanking.recordExecution(resultID: resultID, query: query)
    }

    func statusSummary(resultCount: Int, fallback: String) -> String {
        let resultLabel = resultCount == 1 ? "1 result" : "\(resultCount) results"
        return resultCount > 0 ? resultLabel : fallback
    }

    func commandDescriptors() async -> [CommandDescriptor] {
        await commandCatalog().descriptors
    }

    func commandCatalog(forceRefresh: Bool = false) async -> CommandCatalogSnapshot {
        await catalogCache.snapshot(forceRefresh: forceRefresh, providers: providers)
    }

    func providerDescriptors() async -> [CommandProviderDescriptor] {
        let health = await providerHealth.snapshots(for: providers.map(\.id))
        return providers.map { provider in
            let descriptor = provider.descriptor
            return CommandProviderDescriptor(
                id: descriptor.id,
                version: descriptor.version,
                availability: descriptor.availability,
                requiredPermissions: descriptor.requiredPermissions,
                supportedContexts: descriptor.supportedContexts,
                searchPolicy: descriptor.searchPolicy,
                health: health[descriptor.id]
            )
        }
    }

    func providerHealthSnapshots() async -> [ProviderHealthSnapshot] {
        let snapshots = await providerHealth.snapshots(for: providers.map(\.id))
        return providers.compactMap { snapshots[$0.id] }
    }

    func recordProviderFailure(providerID: String, message: String) async {
        await providerHealth.recordFailure(providerID: providerID, message: message)
    }

    func commandResult(for commandID: String) async -> CommandResult? {
        let deadline = ContinuousClock().now.advanced(by: .milliseconds(400))
        return await withTaskGroup(of: CommandResult?.self, returning: CommandResult?.self) { group in
            for provider in enabledProviders {
                group.addTask { [providerScheduler] in
                    let outcome = await providerScheduler.defaults(for: provider, deadline: deadline)
                    return outcome.value?.first { $0.id == commandID }
                }
            }

            for await result in group {
                if let result, isCommandEnabled(result) {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    private func logSearchTimings(_ timings: [ProviderSearchTiming]) {
        guard timings.isEmpty == false else { return }
        let summary = timings
            .sorted { $0.providerID < $1.providerID }
            .map { timing in
                let suffix: String
                switch timing.status {
                case .success:
                    suffix = ""
                case .timedOut:
                    suffix = " timeout"
                case .cancelled:
                    suffix = " cancelled"
                case .busy:
                    suffix = " busy"
                case let .failed(message):
                    suffix = " failed=\(message)"
                }
                return "\(timing.providerID)=\(String(format: "%.1f", timing.elapsedMilliseconds))ms\(suffix)"
            }
            .joined(separator: " ")
        diagnostics.log("Search providers: \(summary)")
    }

    private func collectCandidates(
        query: String,
        providers: [CommandProvider],
        aliases: [String: [String]],
        timeout: Duration
    ) async -> ([RankCandidate], [ProviderSearchTiming]) {
        let sensitivity = configService?.current.searchSensitivity ?? .medium
        return await providerScheduler.search(
            query: query,
            providers: providers,
            aliases: aliases,
            sensitivity: sensitivity,
            timeout: timeout
        )
    }

    private var enabledProviders: [CommandProvider] {
        providers.filter { provider in
            configService?.current.providerEnabled[provider.id] != false
        }
    }

    private var customAliases: [String: [String]] {
        Dictionary(uniqueKeysWithValues: (configService?.current.commandPreferences ?? [:]).compactMap { commandID, preference in
            preference.aliases.isEmpty ? nil : (commandID, preference.aliases)
        })
    }

    private var supplementalProviders: [CommandProvider] {
        enabledProviders.filter { $0.searchPolicy.includesSupplementalResults }
    }

    private func isCommandEnabled(_ result: CommandResult) -> Bool {
        configService?.current.commandPreferences[result.id]?.isEnabled != false
    }

    private func isMediaQuery(_ query: String) -> Bool {
        MediaDownloadProvider.mediaURLs(in: query).isEmpty == false
    }

    private func mediaOnlyCandidates(_ candidates: [RankCandidate], isMediaQuery: Bool) -> [RankCandidate] {
        guard isMediaQuery else { return candidates }
        return candidates.filter { $0.result.route == .mediaDownload }
    }

    private func isFallbackEligible(for provider: CommandProvider) -> Bool {
        provider.descriptor.availability == .available
    }

    private func isFallbackEligible(for result: CommandResult) -> Bool {
        configService?.current.commandPreferences[result.id]?.fallbackEligible != false
    }

    private static func resultLimit(for query: String) -> Int {
        WindowLayoutQuery.isOverview(query) ? WindowLayoutQuery.overviewResultLimit : 12
    }

}

struct CommandSearchPhase: Sendable {
    let results: [CommandResult]
    let completedProviderIDs: Set<String>
}

private actor CommandCatalogCache {
    private let scheduler: CommandProviderScheduler
    private var cachedSnapshot: CommandCatalogSnapshot?
    private var inFlight: Task<CommandCatalogSnapshot, Never>?
    private var nextGeneration = 0

    init(scheduler: CommandProviderScheduler) {
        self.scheduler = scheduler
    }

    func snapshot(forceRefresh: Bool, providers: [CommandProvider]) async -> CommandCatalogSnapshot {
        if forceRefresh == false, let cachedSnapshot {
            return cachedSnapshot
        }

        if let inFlight {
            return await inFlight.value
        }

        nextGeneration += 1
        let generation = nextGeneration
        let scheduler = scheduler
        let task = Task {
            var descriptors: [CommandDescriptor] = []
            var providerFailures: [String] = []
            let deadline = ContinuousClock().now.advanced(by: .milliseconds(400))
            await withTaskGroup(of: CatalogProviderResult.self) { group in
                for provider in providers {
                    group.addTask {
                        let outcome = await scheduler.defaults(for: provider, deadline: deadline)
                        let failure: String?
                        switch outcome.status {
                        case .success:
                            failure = nil
                        case .timedOut:
                            failure = "timed out"
                        case .cancelled:
                            failure = "cancelled"
                        case .busy:
                            failure = "busy"
                        case let .failed(message):
                            failure = message
                        }
                        return CatalogProviderResult(
                            providerID: provider.id,
                            descriptors: (outcome.value ?? []).map { $0.descriptor(providerID: provider.id) },
                            failure: failure
                        )
                    }
                }

                for await providerResult in group {
                    descriptors.append(contentsOf: providerResult.descriptors)
                    if let failure = providerResult.failure {
                        providerFailures.append("\(providerResult.providerID): \(failure)")
                    }
                }
            }

            return CommandCatalogSnapshot(
                generation: generation,
                createdAt: Date(),
                descriptors: descriptors.sorted { lhs, rhs in
                    lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                },
                providerFailures: providerFailures.sorted()
            )
        }
        inFlight = task
        let result = await task.value
        cachedSnapshot = result
        inFlight = nil
        return result
    }
}

private struct CatalogProviderResult: Sendable {
    let providerID: String
    let descriptors: [CommandDescriptor]
    let failure: String?
}
