import XCTest
import FoundryServices

final class ArtifactStoreTests: XCTestCase {
    func testStagesInDestinationDirectoryAndCommitsAfterValidation() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("result.txt")
        let store = ArtifactStore()

        let staged = try store.stage(for: destination)
        XCTAssertTrue(staged.url.path.hasPrefix(directory.path + "/."))
        try Data("complete".utf8).write(to: staged.url)
        let committed = try store.commit(staged, validating: { url in
            (try? Data(contentsOf: url)) == Data("complete".utf8)
        })

        XCTAssertEqual(committed, destination)
        XCTAssertEqual(try String(contentsOf: destination), "complete")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.url.path))
    }

    func testFailedValidationCleansStagingAndLeavesDestinationAbsent() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("result.txt")
        let store = ArtifactStore()
        let staged = try store.stage(for: destination)
        try Data("partial".utf8).write(to: staged.url)

        XCTAssertThrowsError(try store.commit(staged, validating: { _ in false }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testCollisionDoesNotReplaceExistingOutput() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("result.txt")
        try Data("old".utf8).write(to: destination)
        let store = ArtifactStore()
        let staged = try store.stage(for: destination)
        try Data("new".utf8).write(to: staged.url)

        XCTAssertThrowsError(try store.commit(staged))
        XCTAssertEqual(try String(contentsOf: destination), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.url.path))
    }

    func testTwoStoreInstancesReserveTheSameDestination() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("result.txt")
        let first = try ArtifactStore().stage(for: destination)

        XCTAssertThrowsError(try ArtifactStore().stage(for: destination)) { error in
            XCTAssertEqual(error as? ArtifactStoreError, .destinationExists)
        }
        try ArtifactStore().commit(first)
    }

    func testDiscardIsIdempotentAndReleasesDestinationReservation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-Artifact-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("output.txt")
        let store = ArtifactStore()
        let staged = try store.stage(for: destination)

        store.discard(staged)
        store.discard(staged)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.url.path))
        XCTAssertNoThrow(try store.stage(for: destination))
    }

    func testStaleDiscardCannotReleaseAReplacementReservation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-Artifact-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("output.txt")
        let store = ArtifactStore()
        let stale = try store.stage(for: destination)
        store.discard(stale)
        let current = try store.stage(for: destination)

        store.discard(stale)

        XCTAssertThrowsError(try ArtifactStore().stage(for: destination)) { error in
            XCTAssertEqual(error as? ArtifactStoreError, .destinationExists)
        }
        store.discard(current)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-artifact-").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
