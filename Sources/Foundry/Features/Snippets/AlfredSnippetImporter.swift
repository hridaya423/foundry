import Foundation

struct AlfredSnippetImporter {
    let preferencesRoot: URL?

    private struct File: Decodable {
        struct Snippet: Decodable {
            let name: String?
            let snippet: String
            let keyword: String?
        }
        let alfredsnippet: Snippet
    }

    func snippets() -> [StoredSnippet] {
        guard let root = preferencesRoot?.appendingPathComponent("snippets"),
              let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "json" }
            .sorted { $0.path < $1.path }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
                let content = file.alfredsnippet.snippet
                guard content.isEmpty == false else { return nil }
                let title = file.alfredsnippet.name.flatMap { $0.isEmpty ? nil : $0 } ?? String(content.prefix(40))
                return StoredSnippet(title: title, content: content, keyword: file.alfredsnippet.keyword ?? "", tags: ["Alfred"])
            }
    }
}
