import XCTest
@testable import Foundry

final class CodexOAuthCallbackServerTests: XCTestCase {
    func testWaitForCallbackEndsWhenItsTaskIsCancelled() async {
        let server = CodexOAuthCallbackServer()
        defer { server.stop() }
        let task = Task { try await server.waitForCallback() }
        task.cancel()
        let result = await task.result
        XCTAssertThrowsError(try result.get())
    }

    func testCallbackOnLoopbackWithTheRightPathIsDelivered() async throws {
        let server = CodexOAuthCallbackServer()
        defer { server.stop() }
        let port = try await server.start()
        let callbackTask = Task { try await server.waitForCallback() }
        try await Task.sleep(for: .milliseconds(100))

        let (_, stray) = try await URLSession.shared.data(from: XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/favicon.ico")))
        XCTAssertEqual((stray as? HTTPURLResponse)?.statusCode, 404)

        let (_, real) = try await URLSession.shared.data(from: XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/auth/callback?code=abc&state=xyz")))
        XCTAssertEqual((real as? HTTPURLResponse)?.statusCode, 200)

        let callback = try await callbackTask.value
        XCTAssertEqual(callback.code, "abc")
        XCTAssertEqual(callback.state, "xyz")
        XCTAssertEqual(callback.path, "/auth/callback")
    }
}
