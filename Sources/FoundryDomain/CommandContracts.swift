import Foundation

public enum ActionFeedback: Equatable, Sendable {
    case info(String)
    case success(String)
    case failure(String)

    public var message: String {
        switch self {
        case let .info(message), let .success(message), let .failure(message):
            message
        }
    }

}

public enum CommandAvailability: Codable, Equatable, Hashable, Sendable {
    case available
    case unavailable(reason: String)
}

public enum CommandExecutionPolicy: String, Codable, CaseIterable, Sendable {
    case readOnly
    case localMutation
    case systemMutation
    case network
    case destructive
}

public struct CommandCapabilities: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int

    public static let search = Self(rawValue: 1 << 0)
    public static let defaultResult = Self(rawValue: 1 << 1)
    public static let configurable = Self(rawValue: 1 << 2)
    public static let cancellable = Self(rawValue: 1 << 3)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum CommandProviderSearchTier: String, Codable, CaseIterable, Sendable {
    case immediate
    case deferred
}

public struct CommandProviderSearchPolicy: Codable, Equatable, Hashable, Sendable {
    public let tier: CommandProviderSearchTier
    public let includesSupplementalResults: Bool

    public init(
        tier: CommandProviderSearchTier = .immediate,
        includesSupplementalResults: Bool = false
    ) {
        self.tier = tier
        self.includesSupplementalResults = includesSupplementalResults
    }

    private enum CodingKeys: String, CodingKey {
        case tier
        case includesSupplementalResults
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            tier: try container.decodeIfPresent(CommandProviderSearchTier.self, forKey: .tier) ?? .immediate,
            includesSupplementalResults: try container.decodeIfPresent(Bool.self, forKey: .includesSupplementalResults) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tier, forKey: .tier)
        try container.encode(includesSupplementalResults, forKey: .includesSupplementalResults)
    }
}

public struct CommandDescriptor: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let sourceID: String
    public let title: String
    public let subtitle: String?
    public let keywords: [String]
    public let category: String
    public let icon: CommandIcon
    public let availability: CommandAvailability
    public let defaultActionID: String
    public let argumentSchema: [String: String]
    public let capabilities: CommandCapabilities
    public let executionPolicy: CommandExecutionPolicy

    public init(
        id: String,
        sourceID: String,
        title: String,
        subtitle: String?,
        keywords: [String],
        category: String,
        icon: CommandIcon,
        availability: CommandAvailability,
        defaultActionID: String,
        argumentSchema: [String: String],
        capabilities: CommandCapabilities,
        executionPolicy: CommandExecutionPolicy
    ) {
        self.id = id
        self.sourceID = sourceID
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.category = category
        self.icon = icon
        self.availability = availability
        self.defaultActionID = defaultActionID
        self.argumentSchema = argumentSchema
        self.capabilities = capabilities
        self.executionPolicy = executionPolicy
    }
}

public struct CommandInvocation: Codable, Equatable, Sendable {
    public let commandID: String
    public let arguments: [String: String]
    public let source: CommandInvocationSource
    public let context: [String: String]
    public let cancellationID: UUID

    public init(
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

public struct CommandHotkey: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var displayName: String

    public init(keyCode: UInt32, modifiers: UInt32, displayName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayName = displayName
    }
}

public enum CommandInvocationSource: String, Codable, Sendable {
    case launcher
    case hotkey
    case actionPanel
    case widget
    case external
}

public enum CommandConfirmationPolicy: String, Codable, Sendable {
    case never
    case destructive
    case always
}

public struct CommandActionDescriptor: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let symbol: String?
    public let keyboardEquivalent: String?
    public let isDestructive: Bool
    public let confirmation: CommandConfirmationPolicy
    public let executionRequestID: String

    public init(
        id: String,
        title: String,
        symbol: String?,
        keyboardEquivalent: String?,
        isDestructive: Bool,
        confirmation: CommandConfirmationPolicy,
        executionRequestID: String
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.keyboardEquivalent = keyboardEquivalent
        self.isDestructive = isDestructive
        self.confirmation = confirmation
        self.executionRequestID = executionRequestID
    }
}

public enum ProviderPermissionState: String, Codable, Sendable {
    case unknown
    case notRequired
    case granted
    case denied
}

public struct ProviderHealthSnapshot: Codable, Equatable, Hashable, Sendable {
    public let providerID: String
    public let requestCount: Int
    public let successCount: Int
    public let failureCount: Int
    public let timeoutCount: Int
    public let cancellationCount: Int
    public let emptyResponseCount: Int
    public let latencyP50Milliseconds: Double?
    public let latencyP95Milliseconds: Double?
    public let lastFailure: String?
    public let lastFailureAt: Date?
    public let permissionState: ProviderPermissionState

    public init(
        providerID: String,
        requestCount: Int,
        successCount: Int,
        failureCount: Int,
        timeoutCount: Int = 0,
        cancellationCount: Int = 0,
        emptyResponseCount: Int,
        latencyP50Milliseconds: Double?,
        latencyP95Milliseconds: Double?,
        lastFailure: String?,
        lastFailureAt: Date?,
        permissionState: ProviderPermissionState
    ) {
        self.providerID = providerID
        self.requestCount = requestCount
        self.successCount = successCount
        self.failureCount = failureCount
        self.timeoutCount = timeoutCount
        self.cancellationCount = cancellationCount
        self.emptyResponseCount = emptyResponseCount
        self.latencyP50Milliseconds = latencyP50Milliseconds
        self.latencyP95Milliseconds = latencyP95Milliseconds
        self.lastFailure = lastFailure
        self.lastFailureAt = lastFailureAt
        self.permissionState = permissionState
    }

    private enum CodingKeys: String, CodingKey {
        case providerID
        case requestCount
        case successCount
        case failureCount
        case timeoutCount
        case cancellationCount
        case emptyResponseCount
        case latencyP50Milliseconds
        case latencyP95Milliseconds
        case lastFailure
        case lastFailureAt
        case permissionState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            providerID: try container.decode(String.self, forKey: .providerID),
            requestCount: try container.decode(Int.self, forKey: .requestCount),
            successCount: try container.decode(Int.self, forKey: .successCount),
            failureCount: try container.decode(Int.self, forKey: .failureCount),
            timeoutCount: try container.decodeIfPresent(Int.self, forKey: .timeoutCount) ?? 0,
            cancellationCount: try container.decodeIfPresent(Int.self, forKey: .cancellationCount) ?? 0,
            emptyResponseCount: try container.decode(Int.self, forKey: .emptyResponseCount),
            latencyP50Milliseconds: try container.decodeIfPresent(Double.self, forKey: .latencyP50Milliseconds),
            latencyP95Milliseconds: try container.decodeIfPresent(Double.self, forKey: .latencyP95Milliseconds),
            lastFailure: try container.decodeIfPresent(String.self, forKey: .lastFailure),
            lastFailureAt: try container.decodeIfPresent(Date.self, forKey: .lastFailureAt),
            permissionState: try container.decode(ProviderPermissionState.self, forKey: .permissionState)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providerID, forKey: .providerID)
        try container.encode(requestCount, forKey: .requestCount)
        try container.encode(successCount, forKey: .successCount)
        try container.encode(failureCount, forKey: .failureCount)
        try container.encode(timeoutCount, forKey: .timeoutCount)
        try container.encode(cancellationCount, forKey: .cancellationCount)
        try container.encode(emptyResponseCount, forKey: .emptyResponseCount)
        try container.encodeIfPresent(latencyP50Milliseconds, forKey: .latencyP50Milliseconds)
        try container.encodeIfPresent(latencyP95Milliseconds, forKey: .latencyP95Milliseconds)
        try container.encodeIfPresent(lastFailure, forKey: .lastFailure)
        try container.encodeIfPresent(lastFailureAt, forKey: .lastFailureAt)
        try container.encode(permissionState, forKey: .permissionState)
    }
}

public struct CommandProviderDescriptor: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let version: String
    public let availability: CommandAvailability
    public let requiredPermissions: [String]
    public let supportedContexts: [String]
    public let searchPolicy: CommandProviderSearchPolicy
    public let health: ProviderHealthSnapshot?

    public init(
        id: String,
        version: String,
        availability: CommandAvailability,
        requiredPermissions: [String],
        supportedContexts: [String],
        searchPolicy: CommandProviderSearchPolicy,
        health: ProviderHealthSnapshot?
    ) {
        self.id = id
        self.version = version
        self.availability = availability
        self.requiredPermissions = requiredPermissions
        self.supportedContexts = supportedContexts
        self.searchPolicy = searchPolicy
        self.health = health
    }
}

public struct CommandPreference: Codable, Equatable, Sendable {
    public var isEnabled = true
    public var favoriteRank: Int?
    public var aliases: [String] = []
    public var globalHotkey: CommandHotkey?
    public var fallbackEligible = true
    public var preferredPrimaryActionID: String?

    public init(
        isEnabled: Bool = true,
        favoriteRank: Int? = nil,
        aliases: [String] = [],
        globalHotkey: CommandHotkey? = nil,
        fallbackEligible: Bool = true,
        preferredPrimaryActionID: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.favoriteRank = favoriteRank
        self.aliases = aliases
        self.globalHotkey = globalHotkey
        self.fallbackEligible = fallbackEligible
        self.preferredPrimaryActionID = preferredPrimaryActionID
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case favoriteRank
        case aliases
        case globalHotkey
        case fallbackEligible
        case preferredPrimaryActionID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            favoriteRank: try container.decodeIfPresent(Int.self, forKey: .favoriteRank),
            aliases: try container.decodeIfPresent([String].self, forKey: .aliases) ?? [],
            globalHotkey: try container.decodeIfPresent(CommandHotkey.self, forKey: .globalHotkey),
            fallbackEligible: try container.decodeIfPresent(Bool.self, forKey: .fallbackEligible) ?? true,
            preferredPrimaryActionID: try container.decodeIfPresent(String.self, forKey: .preferredPrimaryActionID)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(favoriteRank, forKey: .favoriteRank)
        try container.encode(aliases, forKey: .aliases)
        try container.encodeIfPresent(globalHotkey, forKey: .globalHotkey)
        try container.encode(fallbackEligible, forKey: .fallbackEligible)
        try container.encodeIfPresent(preferredPrimaryActionID, forKey: .preferredPrimaryActionID)
    }
}

public struct CommandCatalogSnapshot: Equatable, Sendable {
    public let generation: Int
    public let createdAt: Date
    public let descriptors: [CommandDescriptor]
    public let providerFailures: [String]

    public init(generation: Int, createdAt: Date, descriptors: [CommandDescriptor], providerFailures: [String]) {
        self.generation = generation
        self.createdAt = createdAt
        self.descriptors = descriptors
        self.providerFailures = providerFailures
    }
}
