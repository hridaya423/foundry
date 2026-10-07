import Foundation

struct StoredSnippet: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var content: String
    var keyword: String
    var tags: [String]
    var isPinned: Bool
    var updatedAt: Date
    var useCount: Int
    var lastUsedAt: Date?

    init(id: String = UUID().uuidString, title: String = "", content: String = "", keyword: String = "", tags: [String] = [], isPinned: Bool = false, updatedAt: Date = Date(), useCount: Int = 0, lastUsedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.keyword = keyword
        self.tags = tags
        self.isPinned = isPinned
        self.updatedAt = updatedAt
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        keyword = try container.decodeIfPresent(String.self, forKey: .keyword) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        useCount = try container.decodeIfPresent(Int.self, forKey: .useCount) ?? 0
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    }

    mutating func recordUse() {
        useCount += 1
        lastUsedAt = Date()
    }
}

protocol SnippetStore: Sendable {
    var url: URL { get }
    func load() -> [StoredSnippet]
    @discardableResult
    func save(_ snippets: [StoredSnippet]) -> Result<Void, Error>
}

final class FileSnippetStore: SnippetStore, @unchecked Sendable {
    let url: URL

    init(url: URL = ConfigService.configURL.deletingLastPathComponent().appendingPathComponent("snippets.json")) {
        self.url = url
    }

    func load() -> [StoredSnippet] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([StoredSnippet].self, from: data)) ?? []
    }

    @discardableResult
    func save(_ snippets: [StoredSnippet]) -> Result<Void, Error> {
        let folder = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snippets)
            try data.write(to: url, options: .atomic)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
