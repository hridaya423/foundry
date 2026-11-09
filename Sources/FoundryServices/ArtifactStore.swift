import Foundation
import os

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

public final class ArtifactStore: Sendable {
    private let fileManager: FileManager
    private static let reservations = OSAllocatedUnfairLock(initialState: [String: UUID]())
    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    public func stage(for destination: URL) throws -> StagedArtifact {
        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = destination.deletingPathExtension().lastPathComponent
        let suffix = destination.pathExtension.isEmpty ? "" : ".\(destination.pathExtension)"
        let stagedName = ".\(stem).foundry-\(UUID().uuidString)\(suffix)"
        let url = directory.appendingPathComponent(stagedName)
        let reservation = UUID()
        try Self.reservations.withLock {
            let key = destination.standardizedFileURL.path
            guard $0[key] == nil else { throw ArtifactStoreError.destinationExists }
            guard fileManager.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            $0[key] = reservation
        }
        return StagedArtifact(url: url, destination: destination, reservation: reservation)
    }

    @discardableResult
    public func commit(_ staged: StagedArtifact, validating validator: ((URL) throws -> Bool)? = nil) throws -> URL {
        defer { discard(staged) }
        guard fileManager.fileExists(atPath: staged.url.path) else { throw CocoaError(.fileNoSuchFile) }
        if let validator, try validator(staged.url) == false { throw ArtifactStoreError.validationFailed }
        do {
            try Self.reservations.withLock { _ in
                try fileManager.moveItem(at: staged.url, to: staged.destination)
            }
        }
        catch CocoaError.fileWriteFileExists { throw ArtifactStoreError.destinationExists }
        return staged.destination
    }

    public func discard(_ staged: StagedArtifact) {
        BestEffort.attempt("staged artifact cleanup") { try fileManager.removeItem(at: staged.url) }
        Self.reservations.withLock {
            let key = staged.destination.standardizedFileURL.path
            guard $0[key] == staged.reservation else { return }
            $0.removeValue(forKey: key)
        }
    }
}
