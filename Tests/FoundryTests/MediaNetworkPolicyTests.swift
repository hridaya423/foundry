import Foundation
import XCTest
@testable import Foundry

final class MediaNetworkPolicyTests: XCTestCase {
    func testAcceptsPublicHostnameResolvedToPublicAddress() throws {
        let policy = MediaNetworkPolicy(locator: StaticMediaNetworkLocator(addresses: ["142.250.117.136"]))

        XCTAssertNoThrow(try policy.validate(URL(string: "https://www.youtube.com/watch?v=video")!))
    }

    func testRejectsLocalNetworkAndNonHTTPURLs() throws {
        let policy = MediaNetworkPolicy(locator: StaticMediaNetworkLocator(addresses: ["127.0.0.1"]))

        for value in ["http://127.0.0.1/video.mp4", "http://localhost/video.mp4", "file:///tmp/video.mp4"] {
            XCTAssertThrowsError(try policy.validate(URL(string: value)!)) { error in
                XCTAssertEqual(error as? MediaNetworkPolicyFailure, .blockedDestination)
            }
        }
    }

    func testRejectsPrivateLinkLocalAndMulticastAddressesResolvedByLocator() throws {
        for address in ["10.0.0.1", "169.254.1.2", "224.0.0.1", "192.168.1.10", "::ffff:127.0.0.1", "::ffff:10.0.0.1"] {
            let policy = MediaNetworkPolicy(locator: StaticMediaNetworkLocator(addresses: [address]))
            XCTAssertThrowsError(try policy.validate(URL(string: "https://media.example/video.mp4")!)) { error in
                XCTAssertEqual(error as? MediaNetworkPolicyFailure, .blockedDestination)
            }
        }
    }

    func testRedirectsAreValidatedAndBounded() throws {
        let policy = MediaNetworkPolicy(locator: StaticMediaNetworkLocator(addresses: ["93.184.216.34"]), maxRedirects: 1)
        XCTAssertThrowsError(try policy.validateRedirect(to: URL(string: "http://127.0.0.1/file")!, count: 0))
        XCTAssertThrowsError(try policy.validateRedirect(to: URL(string: "https://media.example/two")!, count: 1)) { error in
            XCTAssertEqual(error as? MediaNetworkPolicyFailure, .tooManyRedirects)
        }
    }

    func testRejectsHTTPSRedirectToHTTPButAllowsSameSecurityPublicRedirects() throws {
        let policy = MediaNetworkPolicy(locator: StaticMediaNetworkLocator(addresses: ["93.184.216.34"]))
        let https = URL(string: "https://media.example/video")!
        let http = URL(string: "http://media.example/video")!

        XCTAssertThrowsError(try policy.validateRedirect(from: https, to: http, count: 0)) { error in
            XCTAssertEqual(error as? MediaNetworkPolicyFailure, .blockedDestination)
        }
        XCTAssertNoThrow(try policy.validateRedirect(from: https, to: URL(string: "https://cdn.example/video")!, count: 0))
        XCTAssertNoThrow(try policy.validateRedirect(from: http, to: URL(string: "http://cdn.example/video")!, count: 0))
    }

    func testValidatesStatusSizeMimeAndSignature() throws {
        let policy = MediaNetworkPolicy(locator: StaticMediaNetworkLocator(addresses: ["93.184.216.34"]), maxBytes: 10)
        let response = HTTPURLResponse(url: URL(string: "https://media.example/video.mp4")!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "video/mp4", "Content-Length": "8"])!
        XCTAssertNoThrow(try policy.validate(response: response, body: Data([0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70])))
        XCTAssertThrowsError(try policy.validate(response: HTTPURLResponse(url: response.url!, statusCode: 404, httpVersion: nil, headerFields: nil)! , body: Data()))
        XCTAssertThrowsError(try policy.validate(response: response, body: Data(repeating: 0, count: 11)))
        XCTAssertThrowsError(try policy.validate(response: response, body: Data("not media".utf8)))
    }

    func testSanitizesHostileNamesAndReservesDistinctDestinationsAtomically() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let policy = MediaNetworkPolicy(locator: StaticMediaNetworkLocator(addresses: ["93.184.216.34"]))
        let first = try policy.reserveDestination(named: "../../evil:/video?.mp4", in: folder)
        let second = try policy.reserveDestination(named: "../../evil:/video?.mp4", in: folder)
        XCTAssertEqual(first.lastPathComponent, "--evil--video-.mp4")
        XCTAssertNotEqual(first, second)
    }
}

private struct StaticMediaNetworkLocator: MediaNetworkAddressLocating {
    let addresses: [String]
    func addresses(for _: String) -> [String] { addresses }
}
