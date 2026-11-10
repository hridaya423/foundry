import Foundation

protocol ClipboardHistoryPersisting: Sendable {
    func load() throws -> [ClipboardHistoryItem]
    func save(_ items: [ClipboardHistoryItem]) throws
    /// Lazily loads image bytes for items whose payloads were not hydrated
    /// on load. Stores that keep images inline return nil.
    func imageData(signature: String) throws -> Data?
}

enum ClipboardHistoryPersistenceError: Error { case corruptArchive(Error); case writeFailed(Error) }
