import Foundation

enum ClipboardHistoryPersistenceError: Error { case corruptArchive(Error); case writeFailed(Error) }
struct ClipboardHistoryPersistence {
    let url: URL
    init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/foundry/clipboard-history.json")) { self.url = url }
    func load() throws -> [ClipboardHistoryItem] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do { return try JSONDecoder().decode([ClipboardHistoryItem].self, from: Data(contentsOf: url)) }
        catch { throw ClipboardHistoryPersistenceError.corruptArchive(error) }
    }
    func save(_ items: [ClipboardHistoryItem]) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
            try JSONEncoder().encode(items).write(to: temp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp, backupItemName: nil, options: .usingNewMetadataOnly)
        } catch { throw ClipboardHistoryPersistenceError.writeFailed(error) }
    }
}
