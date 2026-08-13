import Foundation

public struct StagedArtifact: Sendable, Equatable {
    public let url: URL
    public let destination: URL
    public init(url: URL, destination: URL) { self.url = url; self.destination = destination }
}

public enum ArtifactStoreError: Error, Equatable {
    case destinationExists
    case validationFailed
}

public final class ArtifactStore: @unchecked Sendable {
    private let fileManager: FileManager
    private static let commitLock = NSLock()
    private static let reservations = Reservations()
    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    public func stage(for destination: URL) throws -> StagedArtifact {
        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(".\(destination.lastPathComponent).foundry-\(UUID().uuidString)")
        try Self.commitLock.withLock {
            let key = destination.standardizedFileURL.path
            guard Self.reservations.destinations.insert(key).inserted else { throw ArtifactStoreError.destinationExists }
            guard fileManager.createFile(atPath: url.path, contents: nil) else {
                Self.reservations.destinations.remove(key)
                throw CocoaError(.fileWriteUnknown)
            }
        }
        return StagedArtifact(url: url, destination: destination)
    }

    @discardableResult
    public func commit(_ staged: StagedArtifact, validating validator: ((URL) throws -> Bool)? = nil) throws -> URL {
        defer {
            try? fileManager.removeItem(at: staged.url)
            _ = Self.commitLock.withLock { Self.reservations.destinations.remove(staged.destination.standardizedFileURL.path) }
        }
        guard fileManager.fileExists(atPath: staged.url.path) else { throw CocoaError(.fileNoSuchFile) }
        if let validator, try validator(staged.url) == false { throw ArtifactStoreError.validationFailed }
        do {
            try Self.commitLock.withLock {
                try fileManager.moveItem(at: staged.url, to: staged.destination)
            }
        }
        catch CocoaError.fileWriteFileExists { throw ArtifactStoreError.destinationExists }
        return staged.destination
    }
}

private final class Reservations: @unchecked Sendable {
    var destinations = Set<String>()
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try body()
    }
}
