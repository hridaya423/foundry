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

enum LibraryPersistence {
    static var snippetsURL: URL {
        ConfigService.configURL.deletingLastPathComponent().appendingPathComponent("snippets.json")
    }

    static func loadSnippets() -> [StoredSnippet] {
        load([StoredSnippet].self, from: snippetsURL) ?? []
    }

    @discardableResult
    static func saveSnippets(_ snippets: [StoredSnippet]) -> Result<Void, Error> {
        save(snippets, to: snippetsURL)
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, to url: URL) -> Result<Void, Error> {
        let folder = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
