import Foundation

enum SearchRoute: String, CaseIterable, Hashable, Sendable {
    case calculator
    case translation
    case mediaDownload
    case notesSearch
    case aiResponse
    case macUtility
    case browserTab
    case browserBookmark
    case browserHistory
    case developerTool
}

struct CommandResult: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: CommandIcon
    let searchAliases: [String]
    let searchKeywords: [String]
    let route: SearchRoute?
    let primaryAction: CommandAction
    let secondaryActions: [CommandAction]

    init(
        id: String,
        title: String,
        subtitle: String?,
        icon: CommandIcon,
        searchAliases: [String] = [],
        searchKeywords: [String] = [],
        route: SearchRoute? = nil,
        primaryAction: CommandAction,
        secondaryActions: [CommandAction]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.searchAliases = searchAliases
        self.searchKeywords = searchKeywords
        self.route = route
        self.primaryAction = primaryAction
        self.secondaryActions = secondaryActions
    }
}

struct CommandIcon: Codable, Hashable, Sendable {
    let fallback: String
    let filePath: String?
    let systemName: String?
    let thumbnailURL: URL?

    init(fallback: String, filePath: String? = nil, systemName: String? = nil, thumbnailURL: URL? = nil) {
        self.fallback = fallback
        self.filePath = filePath
        self.systemName = systemName
        self.thumbnailURL = thumbnailURL
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
    case openQuickAI(prompt: String)
    case openApp(path: String, name: String)
    case openURL(String)
    case openConfigFolder
    case revealInFinder(path: String)
    case copyToClipboard(String)
    case pasteText(String)
    case createSnippetFromClipboard
    case importSnippets
    case downloadMedia(url: String)
    case chooseMediaDownloadFolder
    case openActivityMonitor
    case openEmojiPicker
    case openFileShelf
    case openClipboardHistory
    case openSnippets
    case openFileConverter(path: String? = nil)
    case openCamera
    case openTranslator(text: String? = nil, language: String? = nil)
    case openDeveloperTools(tool: String? = nil)
    case openSettings
    case openDashboard
    case terminateProcess(pid: Int32)
    case quitApplication(bundleID: String?, name: String)
    case toggleKeepAwake
    case terminatePort(Int)
    case setAudioDevice(id: UInt32, kind: AudioDeviceKind)
    case resetRanking(commandID: String)
    case rebuildApp
    case runProcess(path: String, arguments: [String])
    case quit
    case log(String)
}

enum AudioDeviceKind: Hashable, Sendable {
    case output
    case input
}

protocol CommandProvider: Sendable {
    var id: String { get }
    func results(matching query: String) async -> [CommandResult]
    func results(matching query: String, customAliases: [String: [String]]) async -> [CommandResult]
    func results(matching query: String, customAliases: [String: [String]], sensitivity: SearchSensitivity) async -> [CommandResult]
    func defaultResults() async -> [CommandResult]
}

extension CommandProvider {
    func results(matching query: String, customAliases: [String: [String]]) async -> [CommandResult] {
        await results(matching: query)
    }

    func results(matching query: String, customAliases: [String: [String]], sensitivity: SearchSensitivity) async -> [CommandResult] {
        await results(matching: query, customAliases: customAliases)
    }

    func defaultResults() async -> [CommandResult] { [] }
}

final class CommandRegistry: @unchecked Sendable {
    private let providers: [CommandProvider]
    private let usageRanking: UsageRankingStore
    private let diagnostics: DiagnosticsService
    private let providerHealth: ProviderHealthStore
    private let configService: ConfigService?
    private let catalogCache = CommandCatalogCache()

    init(providers: [CommandProvider], usageRanking: UsageRankingStore, diagnostics: DiagnosticsService, providerHealth: ProviderHealthStore = ProviderHealthStore(), configService: ConfigService? = nil) {
        self.providers = providers
        self.usageRanking = usageRanking
        self.diagnostics = diagnostics
        self.providerHealth = providerHealth
        self.configService = configService
    }

    static func defaultRegistry(
        config: ConfigService,
        diagnostics: DiagnosticsService
    ) -> CommandRegistry {
        let usageRanking = UsageRankingStore(diagnostics: diagnostics)
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
                LibraryProvider(),
                MediaDownloadProvider(),
                SystemCommandProvider(diagnostics: diagnostics),
                BuiltInCommandProvider(config: config, diagnostics: diagnostics)
            ],
            usageRanking: usageRanking,
            diagnostics: diagnostics,
            configService: config
        )
    }

    func results(matching query: String) async -> [CommandResult] {
        await results(matching: query, customAliases: customAliases)
    }

    func immediateResults(matching query: String) async -> [CommandResult] {
        let activeProviders = enabledProviders.filter { immediateProviderIDs.contains($0.id) }
        let (providerCandidates, _) = await collectCandidates(query: query, providers: activeProviders, aliases: customAliases)
        var candidates = providerCandidates.filter { isCommandEnabled($0.result) }
        let sensitivity = configService?.current.searchSensitivity ?? .medium

        if let browserProvider = enabledProviders.compactMap({ $0 as? BrowserProvider }).first {
            candidates.append(contentsOf: browserProvider.cachedResults(matching: query, sensitivity: sensitivity).enumerated().map { index, result in
                RankCandidate(result: result, providerID: browserProvider.id, sourceOrder: index)
            })
        }

        return Array(ordered(deduplicated(candidates), query: query).prefix(12))
    }

    func completeResults(matching query: String, initialResults: [CommandResult]) async -> [CommandResult] {
        let deferredProviders = enabledProviders.filter { immediateProviderIDs.contains($0.id) == false }
        let (providerCandidates, timings) = await collectCandidates(query: query, providers: deferredProviders, aliases: customAliases)
        var candidates = initialResults.enumerated().map { index, result in
            RankCandidate(result: result, providerID: "foundry.immediate", sourceOrder: index)
        }
        candidates.append(contentsOf: providerCandidates)
        let sensitivity = configService?.current.searchSensitivity ?? .medium

        if let browserProvider = deferredProviders.compactMap({ $0 as? BrowserProvider }).first {
            let existingIDs = Set(candidates.map { $0.result.id })
            candidates.append(contentsOf: browserProvider.cachedResults(matching: query, sensitivity: sensitivity).enumerated().compactMap { index, result in
                existingIDs.contains(result.id) ? nil : RankCandidate(result: result, providerID: browserProvider.id, sourceOrder: index)
            })
        }

        candidates = deduplicated(candidates.filter { isCommandEnabled($0.result) })
        if candidates.isEmpty {
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
        return Array(ordered(candidates, query: query).prefix(12))
    }

    func results(matching query: String, customAliases: [String: [String]]) async -> [CommandResult] {
        let activeProviders = enabledProviders
        let (providerCandidates, timings) = await collectCandidates(query: query, providers: activeProviders, aliases: customAliases)
        var allCandidates = providerCandidates

        guard Task.isCancelled == false else { return [] }

        if let browserProvider = activeProviders.compactMap({ $0 as? BrowserProvider }).first {
            let sensitivity = configService?.current.searchSensitivity ?? .medium
            let cachedResults = browserProvider.cachedResults(matching: query, sensitivity: sensitivity)
            allCandidates.append(contentsOf: cachedResults.enumerated().map { index, result in
                RankCandidate(result: result, providerID: browserProvider.id, sourceOrder: index)
            })
            if allCandidates.isEmpty {
                let fallbackResults = await browserProvider.fallbackResults(matching: query, sensitivity: sensitivity)
                allCandidates.append(contentsOf: fallbackResults.enumerated().map { index, result in
                    RankCandidate(result: result, providerID: browserProvider.id, sourceOrder: index)
                })
            }
        }

        allCandidates = deduplicated(allCandidates.filter { isCommandEnabled($0.result) })

        if allCandidates.isEmpty {
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

        return ordered(allCandidates, query: query)
            .prefix(12)
            .map { $0 }
    }

    func homeResults() async -> [CommandResult] {
        let activeProviders = enabledProviders
        var allCandidates: [RankCandidate] = []
        await withTaskGroup(of: [CommandResult].self) { group in
            for provider in activeProviders {
                group.addTask {
                    let startedAt = Date().timeIntervalSinceReferenceDate
                    let results = await provider.defaultResults()
                    let elapsedMilliseconds = (Date().timeIntervalSinceReferenceDate - startedAt) * 1_000
                    await self.providerHealth.recordRequest(providerID: provider.id, elapsedMilliseconds: elapsedMilliseconds, resultCount: results.count)
                    return results
                }
            }

            for await results in group {
                allCandidates.append(contentsOf: results.enumerated().map { index, result in
                    RankCandidate(result: result, providerID: "", sourceOrder: index)
                })
            }
        }

        let sorted = ordered(allCandidates.filter { isCommandEnabled($0.result) }, query: nil)

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

    func resetRanking(for resultID: String) {
        usageRanking.resetRanking(for: resultID)
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

    private func collectCandidates(
        query: String,
        providers: [CommandProvider],
        aliases: [String: [String]]
    ) async -> ([RankCandidate], [ProviderSearchTiming]) {
        let sensitivity = configService?.current.searchSensitivity ?? .medium
        return await withTaskGroup(of: ProviderSearchResult.self, returning: ([RankCandidate], [ProviderSearchTiming]).self) { group in
            for provider in providers {
                group.addTask {
                    let startedAt = Date().timeIntervalSinceReferenceDate
                    let results = await provider.results(matching: query, customAliases: aliases, sensitivity: sensitivity)
                    let elapsedMilliseconds = (Date().timeIntervalSinceReferenceDate - startedAt) * 1_000
                    await self.providerHealth.recordRequest(providerID: provider.id, elapsedMilliseconds: elapsedMilliseconds, resultCount: results.count)
                    return ProviderSearchResult(providerID: provider.id, results: results, elapsedMilliseconds: elapsedMilliseconds)
                }
            }

            var candidates: [RankCandidate] = []
            var timings: [ProviderSearchTiming] = []
            for await providerResult in group {
                guard Task.isCancelled == false else {
                    group.cancelAll()
                    return ([], [])
                }
                candidates.append(contentsOf: providerResult.results.enumerated().map { index, result in
                    RankCandidate(result: result, providerID: providerResult.providerID, sourceOrder: index)
                })
                timings.append(ProviderSearchTiming(providerID: providerResult.providerID, elapsedMilliseconds: providerResult.elapsedMilliseconds))
            }
            return (candidates, timings)
        }
    }

    private func deduplicated(_ candidates: [RankCandidate]) -> [RankCandidate] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.result.id).inserted }
    }

    private var enabledProviders: [CommandProvider] {
        providers.filter { provider in
            configService?.current.providerEnabled[provider.id] != false
        }
    }

    private var immediateProviderIDs: Set<String> {
        [
            "foundry.apps",
            "foundry.builtin",
            "foundry.calculator",
            "foundry.developer-tools",
            "foundry.library",
            "foundry.mac-utilities",
            "foundry.system"
        ]
    }

    private var customAliases: [String: [String]] {
        Dictionary(uniqueKeysWithValues: (configService?.current.commandPreferences ?? [:]).compactMap { commandID, preference in
            preference.aliases.isEmpty ? nil : (commandID, preference.aliases)
        })
    }

    private func isCommandEnabled(_ result: CommandResult) -> Bool {
        configService?.current.commandPreferences[result.id]?.isEnabled != false
    }

    private func ordered(_ candidates: [RankCandidate], query: String?) -> [CommandResult] {
        candidates
            .map { candidate in
                let preference = configService?.current.commandPreferences[candidate.result.id]
                let match = query.flatMap { query in
                    SearchScoring.match(
                        query: query,
                        title: candidate.result.title,
                        subtitle: candidate.result.subtitle,
                        keywords: candidate.result.searchKeywords,
                        aliases: candidate.result.searchAliases + (preference?.aliases ?? []),
                        sensitivity: configService?.current.searchSensitivity ?? .medium
                    )
                }
                return RankedResult(
                    candidate: candidate,
                    preference: preference,
                    match: match,
                    usageBoost: query.flatMap { usageRanking.usageBoost(for: candidate.result.id, query: $0) } ?? 0
                )
            }
            .sorted { (lhs: RankedResult, rhs: RankedResult) in
                if query == nil, lhs.preference?.favoriteRank != rhs.preference?.favoriteRank {
                    switch (lhs.preference?.favoriteRank, rhs.preference?.favoriteRank) {
                    case let (lhsRank?, rhsRank?):
                        if lhsRank != rhsRank { return lhsRank < rhsRank }
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    default:
                        break
                    }
                }

                if let lhsMatch = lhs.match, let rhsMatch = rhs.match, lhsMatch != rhsMatch {
                    let lhsIsBetter = SearchScoring.isBetter(lhsMatch, than: rhsMatch)
                    let rhsIsBetter = SearchScoring.isBetter(rhsMatch, than: lhsMatch)
                    if SearchScoring.areComparable(lhsMatch, rhsMatch), lhs.usageBoost != rhs.usageBoost {
                        return lhs.usageBoost > rhs.usageBoost
                    }
                    if lhsIsBetter || rhsIsBetter {
                        return lhsIsBetter
                    }
                } else if lhs.match != nil, rhs.match == nil {
                    return true
                } else if lhs.match == nil, rhs.match != nil {
                    return false
                }

                if lhs.usageBoost != rhs.usageBoost {
                    return lhs.usageBoost > rhs.usageBoost
                }
                if lhs.candidate.providerID != rhs.candidate.providerID {
                    return lhs.candidate.providerID < rhs.candidate.providerID
                }
                if lhs.candidate.result.title.localizedCaseInsensitiveCompare(rhs.candidate.result.title) != .orderedSame {
                    return lhs.candidate.result.title.localizedCaseInsensitiveCompare(rhs.candidate.result.title) == .orderedAscending
                }
                if lhs.candidate.result.id != rhs.candidate.result.id {
                    return lhs.candidate.result.id < rhs.candidate.result.id
                }
                return lhs.candidate.sourceOrder < rhs.candidate.sourceOrder
            }
            .map(\.candidate.result)
    }
}

private struct RankCandidate {
    let result: CommandResult
    let providerID: String
    let sourceOrder: Int
}

private struct RankedResult {
    let candidate: RankCandidate
    let preference: CommandPreference?
    let match: SearchMatch?
    let usageBoost: Double
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

private actor CommandCatalogCache {
    private var cachedSnapshot: CommandCatalogSnapshot?
    private var inFlight: Task<CommandCatalogSnapshot, Never>?
    private var nextGeneration = 0

    func snapshot(forceRefresh: Bool, providers: [CommandProvider]) async -> CommandCatalogSnapshot {
        if forceRefresh == false, let cachedSnapshot {
            return cachedSnapshot
        }

        if let inFlight {
            return await inFlight.value
        }

        nextGeneration += 1
        let generation = nextGeneration
        let task = Task.detached(priority: .userInitiated) {
            var descriptors: [CommandDescriptor] = []
            await withTaskGroup(of: [CommandDescriptor].self) { group in
                for provider in providers {
                    group.addTask {
                        let results = await provider.defaultResults()
                        return results.map { $0.descriptor(providerID: provider.id) }
                    }
                }

                for await providerDescriptors in group {
                    descriptors.append(contentsOf: providerDescriptors)
                }
            }

            return CommandCatalogSnapshot(
                generation: generation,
                createdAt: Date(),
                descriptors: descriptors.sorted { lhs, rhs in
                    lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                },
                providerFailures: []
            )
        }
        inFlight = task
        let result = await task.value
        cachedSnapshot = result
        inFlight = nil
        return result
    }
}
