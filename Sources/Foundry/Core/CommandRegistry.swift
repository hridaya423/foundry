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
    case openDeveloperTools
    case openSettings
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

    init(providers: [CommandProvider], usageRanking: UsageRankingStore, diagnostics: DiagnosticsService) {
        self.providers = providers
        self.usageRanking = usageRanking
        self.diagnostics = diagnostics
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
                AppleNotesProvider(),
                LibraryProvider(),
                MediaDownloadProvider(),
                SystemCommandProvider(diagnostics: diagnostics),
                BuiltInCommandProvider(config: config, diagnostics: diagnostics)
            ],
            usageRanking: usageRanking,
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

    func homeResults() async -> [CommandResult] {
        var allResults: [CommandResult] = []
        await withTaskGroup(of: [CommandResult].self) { group in
            for provider in providers {
                group.addTask {
                    await provider.defaultResults()
                }
            }

            for await results in group {
                allResults.append(contentsOf: results)
            }
        }

        let sorted = allResults.sorted { lhs, rhs in
                let lhsScore = usageRanking.adjustedScore(for: lhs)
                let rhsScore = usageRanking.adjustedScore(for: rhs)
                if lhsScore == rhsScore {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhsScore > rhsScore
            }

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
