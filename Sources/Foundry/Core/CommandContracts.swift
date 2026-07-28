import Foundation

enum CommandAvailability: Codable, Equatable, Hashable, Sendable {
    case available
    case unavailable(reason: String)
}

enum CommandExecutionPolicy: String, Codable, CaseIterable, Sendable {
    case readOnly
    case localMutation
    case systemMutation
    case network
    case destructive
}

struct CommandCapabilities: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int

    static let search = Self(rawValue: 1 << 0)
    static let defaultResult = Self(rawValue: 1 << 1)
    static let configurable = Self(rawValue: 1 << 2)
    static let cancellable = Self(rawValue: 1 << 3)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct CommandDescriptor: Codable, Equatable, Hashable, Sendable {
    let id: String
    let sourceID: String
    let title: String
    let subtitle: String?
    let keywords: [String]
    let category: String
    let icon: CommandIcon
    let availability: CommandAvailability
    let defaultActionID: String
    let argumentSchema: [String: String]
    let capabilities: CommandCapabilities
    let executionPolicy: CommandExecutionPolicy
}

struct CommandInvocation: Codable, Equatable, Sendable {
    let commandID: String
    let arguments: [String: String]
    let source: CommandInvocationSource
    let context: [String: String]
    let cancellationID: UUID

    init(
        commandID: String,
        arguments: [String: String] = [:],
        source: CommandInvocationSource = .launcher,
        context: [String: String] = [:],
        cancellationID: UUID = UUID()
    ) {
        self.commandID = commandID
        self.arguments = arguments
        self.source = source
        self.context = context
        self.cancellationID = cancellationID
    }
}

enum CommandInvocationSource: String, Codable, Sendable {
    case launcher
    case hotkey
    case actionPanel
    case widget
    case external
}

enum CommandOutcome: Codable, Equatable, Sendable {
    case success(message: String?)
    case failure(message: String, retryable: Bool)
    case cancelled
    case open(mode: String)
    case copied(content: String)
    case pasted(content: String)
    case fileResults([URL])
    case followUp(actionIDs: [String])
}

enum CommandConfirmationPolicy: String, Codable, Sendable {
    case never
    case destructive
    case always
}

struct CommandActionDescriptor: Codable, Equatable, Hashable, Sendable {
    let id: String
    let title: String
    let symbol: String?
    let keyboardEquivalent: String?
    let isDestructive: Bool
    let confirmation: CommandConfirmationPolicy
    let executionRequestID: String
}

struct CommandProviderDescriptor: Codable, Equatable, Hashable, Sendable {
    let id: String
    let version: String
    let availability: CommandAvailability
    let requiredPermissions: [String]
    let supportedContexts: [String]
    let health: ProviderHealthSnapshot?
}

enum ProviderPermissionState: String, Codable, Sendable {
    case unknown
    case notRequired
    case granted
    case denied
}

struct ProviderHealthSnapshot: Codable, Equatable, Hashable, Sendable {
    let providerID: String
    let requestCount: Int
    let successCount: Int
    let failureCount: Int
    let emptyResponseCount: Int
    let latencyP50Milliseconds: Double?
    let latencyP95Milliseconds: Double?
    let lastFailure: String?
    let lastFailureAt: Date?
    let permissionState: ProviderPermissionState
}

actor ProviderHealthStore {
    private struct Metrics {
        var requestCount = 0
        var successCount = 0
        var failureCount = 0
        var emptyResponseCount = 0
        var latencies: [Double] = []
        var lastFailure: String?
        var lastFailureAt: Date?
        var permissionState: ProviderPermissionState = .unknown
    }

    private var metrics: [String: Metrics] = [:]

    func recordRequest(providerID: String, elapsedMilliseconds: Double, resultCount: Int) {
        var value = metrics[providerID, default: Metrics()]
        value.requestCount += 1
        value.successCount += 1
        if resultCount == 0 {
            value.emptyResponseCount += 1
        }
        value.latencies.append(max(0, elapsedMilliseconds))
        if value.latencies.count > 200 {
            value.latencies.removeFirst(value.latencies.count - 200)
        }
        metrics[providerID] = value
    }

    func recordFailure(providerID: String, message: String) {
        var value = metrics[providerID, default: Metrics()]
        value.requestCount += 1
        value.failureCount += 1
        value.lastFailure = message
        value.lastFailureAt = Date()
        metrics[providerID] = value
    }

    func setPermissionState(_ state: ProviderPermissionState, for providerID: String) {
        var value = metrics[providerID, default: Metrics()]
        value.permissionState = state
        metrics[providerID] = value
    }

    func snapshot(for providerID: String) -> ProviderHealthSnapshot {
        let value = metrics[providerID, default: Metrics()]
        return ProviderHealthSnapshot(
            providerID: providerID,
            requestCount: value.requestCount,
            successCount: value.successCount,
            failureCount: value.failureCount,
            emptyResponseCount: value.emptyResponseCount,
            latencyP50Milliseconds: Self.percentile(value.latencies, percentile: 0.50),
            latencyP95Milliseconds: Self.percentile(value.latencies, percentile: 0.95),
            lastFailure: value.lastFailure,
            lastFailureAt: value.lastFailureAt,
            permissionState: value.permissionState
        )
    }

    func snapshots(for providerIDs: [String]) -> [String: ProviderHealthSnapshot] {
        Dictionary(uniqueKeysWithValues: providerIDs.map { ($0, snapshot(for: $0)) })
    }

    private static func percentile(_ values: [Double], percentile: Double) -> Double? {
        guard values.isEmpty == false else { return nil }
        let sorted = values.sorted()
        let position = Double(sorted.count - 1) * percentile
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = min(sorted.count - 1, lowerIndex + 1)
        let fraction = position - Double(lowerIndex)
        return sorted[lowerIndex] + (sorted[upperIndex] - sorted[lowerIndex]) * fraction
    }
}

struct CommandPreference: Codable, Equatable, Sendable {
    var isEnabled = true
    var favoriteRank: Int?
    var aliases: [String] = []
    var globalHotkey: FoundryHotkey?
    var fallbackEligible = true
    var preferredPrimaryActionID: String?
}

struct CommandSettingsRowModel: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let sourceLabel: String
    let icon: CommandIcon
    let searchText: String
    let preference: CommandPreference

    init(descriptor: CommandDescriptor, preference: CommandPreference) {
        id = descriptor.id
        title = descriptor.title
        subtitle = descriptor.subtitle ?? Self.sourceLabel(for: descriptor.sourceID)
        sourceLabel = Self.sourceLabel(for: descriptor.sourceID)
        icon = descriptor.icon
        self.preference = preference
        searchText = [
            descriptor.title,
            descriptor.subtitle ?? "",
            descriptor.sourceID,
            descriptor.category,
            preference.aliases.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private static func sourceLabel(for sourceID: String) -> String {
        switch sourceID {
        case "foundry.apps": "Applications"
        case "foundry.builtin": "Foundry"
        case "foundry.system": "System"
        case "foundry.browser": "Browsers"
        default: sourceID.replacingOccurrences(of: "foundry.", with: "").capitalized
        }
    }
}

struct CommandCatalogSnapshot: Equatable, Sendable {
    let generation: Int
    let createdAt: Date
    let descriptors: [CommandDescriptor]
    let providerFailures: [String]
}

extension CommandProvider {
    var descriptor: CommandProviderDescriptor {
        CommandProviderDescriptor(
            id: id,
            version: "1",
            availability: .available,
            requiredPermissions: [],
            supportedContexts: ["search", "home"],
            health: nil
        )
    }
}

extension CommandResult {
    func descriptor(providerID: String, preference: CommandPreference? = nil) -> CommandDescriptor {
        CommandDescriptor(
            id: id,
            sourceID: providerID,
            title: title,
            subtitle: subtitle,
            keywords: preference?.aliases ?? [],
            category: providerID,
            icon: icon,
            availability: .available,
            defaultActionID: primaryAction.id,
            argumentSchema: [:],
            capabilities: [.search, .defaultResult],
            executionPolicy: primaryAction.kind.executionPolicy
        )
    }
}

extension CommandAction {
    var descriptor: CommandActionDescriptor {
        CommandActionDescriptor(
            id: id,
            title: title,
            symbol: nil,
            keyboardEquivalent: nil,
            isDestructive: kind.isDestructive,
            confirmation: kind.isDestructive ? .destructive : .never,
            executionRequestID: id
        )
    }
}

extension CommandActionKind {
    var isDestructive: Bool {
        switch self {
        case .terminateProcess, .quitApplication, .terminatePort, .rebuildApp, .quit:
            true
        default:
            false
        }
    }

    var executionPolicy: CommandExecutionPolicy {
        switch self {
        case .copyToClipboard, .openURL, .openQuickAI, .openConfigFolder, .openActivityMonitor, .openEmojiPicker, .openFileShelf, .openClipboardHistory, .openSnippets, .openFileConverter, .openCamera, .openTranslator, .openDeveloperTools, .openSettings, .openDashboard, .log:
            .readOnly
        case .openApp, .revealInFinder, .createSnippetFromClipboard, .importSnippets, .pasteText, .chooseMediaDownloadFolder, .setAudioDevice:
            .localMutation
        case .downloadMedia:
            .network
        case .terminateProcess, .quitApplication, .terminatePort, .rebuildApp, .runProcess, .toggleKeepAwake, .quit:
            .systemMutation
        }
    }
}
