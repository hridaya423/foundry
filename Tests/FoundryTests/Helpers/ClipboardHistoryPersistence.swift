import Foundation
@testable import Foundry

struct ClipboardHistoryPersistence: ClipboardHistoryPersisting, Sendable {
    let url: URL
    init(url: URL) { self.url = url }
    func load() throws -> [ClipboardHistoryItem] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do { return try JSONDecoder().decode([ClipboardHistoryItem].self, from: Data(contentsOf: url)) }
        catch { throw ClipboardHistoryPersistenceError.corruptArchive(error) }
    }
    func save(_ items: [ClipboardHistoryItem]) throws {
        var temporaryURL: URL?
        defer {
            if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
            temporaryURL = temp
            try JSONEncoder().encode(items).write(to: temp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp, backupItemName: nil, options: .usingNewMetadataOnly)
        } catch { throw ClipboardHistoryPersistenceError.writeFailed(error) }
    }
    func imageData(signature _: String) throws -> Data? { nil }
}
