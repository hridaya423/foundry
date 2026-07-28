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
    func defaultResults() async -> [CommandResult]
}

extension CommandProvider {
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
        let activeProviders = enabledProviders
        var allResults: [CommandResult] = []
        var timings: [ProviderSearchTiming] = []

        await withTaskGroup(of: ProviderSearchResult.self) { group in
            for provider in activeProviders {
                group.addTask {
                    let startedAt = Date().timeIntervalSinceReferenceDate
                    let results = await provider.results(matching: query)
                    let elapsedMilliseconds = (Date().timeIntervalSinceReferenceDate - startedAt) * 1_000
                    await self.providerHealth.recordRequest(providerID: provider.id, elapsedMilliseconds: elapsedMilliseconds, resultCount: results.count)
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

        if let browserProvider = activeProviders.compactMap({ $0 as? BrowserProvider }).first {
            allResults.append(contentsOf: browserProvider.cachedResults(matching: query))
            if allResults.isEmpty {
                allResults.append(contentsOf: await browserProvider.fallbackResults(matching: query))
            }
        }

        allResults = allResults.filter(isCommandEnabled)

        if allResults.isEmpty {
            let prompt = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if prompt.isEmpty == false {
                allResults.append(CommandResult(
                    id: "foundry.quick.\(AIRequestIdentifier.make(prompt: prompt, backend: .appleFoundationModels))",
                    title: "Ask AI about \(prompt)",
                    subtitle: "Open the research assistant",
                    icon: CommandIcon(fallback: "AI", systemName: "sparkles"),
                    score: 95,
                    primaryAction: CommandAction(id: "ai.quick", title: "Ask AI", kind: .openQuickAI(prompt: prompt)),
                    secondaryActions: []
                ))
            }
        }

        logSearchTimings(timings)

        return ordered(allResults)
            .prefix(12)
            .map { $0 }
    }

    func homeResults() async -> [CommandResult] {
        let activeProviders = enabledProviders
        var allResults: [CommandResult] = []
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
                allResults.append(contentsOf: results)
            }
        }

        let sorted = ordered(allResults.filter(isCommandEnabled))

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

    func recordExecution(resultID: String) {
        usageRanking.recordExecution(resultID: resultID)
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

    private var enabledProviders: [CommandProvider] {
        providers.filter { provider in
            configService?.current.providerEnabled[provider.id] != false
        }
    }

    private func isCommandEnabled(_ result: CommandResult) -> Bool {
        configService?.current.commandPreferences[result.id]?.isEnabled != false
    }

    private func ordered(_ results: [CommandResult]) -> [CommandResult] {
        results.sorted { lhs, rhs in
            let lhsPreference = configService?.current.commandPreferences[lhs.id]
            let rhsPreference = configService?.current.commandPreferences[rhs.id]
            switch (lhsPreference?.favoriteRank, rhsPreference?.favoriteRank) {
            case let (lhsRank?, rhsRank?):
                if lhsRank != rhsRank { return lhsRank < rhsRank }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }

            let lhsScore = usageRanking.adjustedScore(for: lhs)
            let rhsScore = usageRanking.adjustedScore(for: rhs)
            if lhsScore == rhsScore {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhsScore > rhsScore
        }
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
