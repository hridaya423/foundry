import Foundation

public struct CommandIcon: Codable, Hashable, Sendable {
    public let fallback: String
    public let filePath: String?
    public let systemName: String?
    public let thumbnailURL: URL?

    public init(fallback: String, filePath: String? = nil, systemName: String? = nil, thumbnailURL: URL? = nil) {
        self.fallback = fallback
        self.filePath = filePath
        self.systemName = systemName
        self.thumbnailURL = thumbnailURL
    }
}

public struct CommandSearchRequest: Sendable {
    public let query: String
    public let customAliases: [String: [String]]
    public let sensitivity: SearchSensitivity
    public let deadline: ContinuousClock.Instant

    public init(
        query: String,
        customAliases: [String: [String]] = [:],
        sensitivity: SearchSensitivity = .medium,
        deadline: ContinuousClock.Instant = ContinuousClock().now.advanced(by: .seconds(30))
    ) {
        self.query = query
        self.customAliases = customAliases
        self.sensitivity = sensitivity
        self.deadline = deadline
    }

    public var isExpired: Bool {
        ContinuousClock().now >= deadline
    }
}
