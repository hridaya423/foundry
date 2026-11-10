import CryptoKit
import XCTest
@testable import Foundry

final class FileDigestTests: XCTestCase {
    func testDigestIsRememberedUntilTheFileChanges() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-digest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let large = Data(repeating: 7, count: 96 * 1024 * 1024)
        try large.write(to: file)
        let clock = ContinuousClock()

        var first = ""
        let firstTime = try clock.measure { first = try FileDigest.sha256(at: file) }
        var second = ""
        let secondTime = try clock.measure { second = try FileDigest.sha256(at: file) }

        XCTAssertEqual(first, SHA256.hash(data: large).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(second, first)
        XCTAssertLessThan(secondTime * 20, firstTime, "the second read should not hash 96 MB again")

        try Data("changed".utf8).write(to: file)
        XCTAssertEqual(try FileDigest.sha256(at: file), SHA256.hash(data: Data("changed".utf8)).map { String(format: "%02x", $0) }.joined())
    }
}
