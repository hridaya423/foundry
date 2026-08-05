import Foundation

struct StoredSnippet: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var content: String
    var keyword: String
    var tags: [String]
    var isPinned: Bool
    var updatedAt: Date

    init(id: String = UUID().uuidString, title: String = "", content: String = "", keyword: String = "", tags: [String] = [], isPinned: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.keyword = keyword
        self.tags = tags
        self.isPinned = isPinned
        self.updatedAt = updatedAt
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
