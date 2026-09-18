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
    public let category: String
    public let icon: CommandIcon

    public init(
        id: String,
        sourceID: String,
        title: String,
        subtitle: String?,
        category: String,
        icon: CommandIcon
    ) {
        self.id = id
        self.sourceID = sourceID
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.icon = icon
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
    public let isDestructive: Bool
    public let confirmation: CommandConfirmationPolicy

    public init(
        id: String,
        title: String,
        isDestructive: Bool,
        confirmation: CommandConfirmationPolicy
    ) {
        self.id = id
        self.title = title
        self.isDestructive = isDestructive
        self.confirmation = confirmation
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
    public let descriptors: [CommandDescriptor]
    public let providerFailures: [String]

    public init(generation: Int, descriptors: [CommandDescriptor], providerFailures: [String]) {
        self.generation = generation
        self.descriptors = descriptors
        self.providerFailures = providerFailures
    }
}
