import Foundation

public struct StagedArtifact: Sendable, Equatable {
    public let url: URL
    public let destination: URL
    fileprivate let reservation: UUID

    fileprivate init(url: URL, destination: URL, reservation: UUID) {
        self.url = url
        self.destination = destination
        self.reservation = reservation
    }
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
        let reservation = UUID()
        try Self.commitLock.withLock {
            let key = destination.standardizedFileURL.path
            guard Self.reservations.destinations[key] == nil else { throw ArtifactStoreError.destinationExists }
            guard fileManager.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            Self.reservations.destinations[key] = reservation
        }
        return StagedArtifact(url: url, destination: destination, reservation: reservation)
    }

    @discardableResult
    public func commit(_ staged: StagedArtifact, validating validator: ((URL) throws -> Bool)? = nil) throws -> URL {
        defer { discard(staged) }
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

    public func discard(_ staged: StagedArtifact) {
        try? fileManager.removeItem(at: staged.url)
        Self.commitLock.withLock {
            let key = staged.destination.standardizedFileURL.path
            guard Self.reservations.destinations[key] == staged.reservation else { return }
            Self.reservations.destinations.removeValue(forKey: key)
        }
    }
}

private final class Reservations: @unchecked Sendable {
    var destinations: [String: UUID] = [:]
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try body()
    }
}
