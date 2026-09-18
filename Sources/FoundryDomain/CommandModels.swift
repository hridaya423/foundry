import Foundation

public struct CommandIcon: Codable, Hashable, Sendable {
    public let fallback: String
    public let filePath: String?
    public let systemName: String?
    public let thumbnailURL: URL?
    public let remoteIconURL: URL?

    public init(fallback: String, filePath: String? = nil, systemName: String? = nil, thumbnailURL: URL? = nil, remoteIconURL: URL? = nil) {
        self.fallback = fallback
        self.filePath = filePath
        self.systemName = systemName
        self.thumbnailURL = thumbnailURL
        self.remoteIconURL = remoteIconURL
    }
}

public struct CommandSearchRequest: Sendable {
    public let query: String
    public let customAliases: [String: [String]]
    public let sensitivity: SearchSensitivity

    public init(
        query: String,
        customAliases: [String: [String]] = [:],
        sensitivity: SearchSensitivity = .medium,
    ) {
        self.query = query
        self.customAliases = customAliases
        self.sensitivity = sensitivity
    }
}
