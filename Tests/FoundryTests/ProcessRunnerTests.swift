import XCTest
@testable import Foundry

final class ProcessRunnerTests: XCTestCase {
    func testSynchronousRunnerDrainsBothStreams() {
        let result = ProcessRunner.runSynchronously(
            path: "/bin/sh",
            arguments: ["-c", "yes output | head -c 200000"],
            timeout: 5
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.exitCode, 0)
        XCTAssertEqual(result?.timedOut, false)
        XCTAssertGreaterThan(result?.stdout.count ?? 0, 100_000)
    }

    func testSynchronousRunnerEscalatesTimedOutProcess() {
        let result = ProcessRunner.runSynchronously(
            path: "/bin/sh",
            arguments: ["-c", "trap '' TERM; while true; do :; done"],
            timeout: 0.1
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.timedOut, true)
        XCTAssertEqual(result?.cancelled, false)
    }

    func testSynchronousRunnerTerminatesDescendants() {
        let result = ProcessRunner.runSynchronously(
            path: "/bin/sh",
            arguments: ["-c", "sleep 30 & wait"],
            timeout: 0.1
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.timedOut, true)
    }

    func testAsyncRunnerTerminatesChildWhenCancelled() async {
        let task = Task {
            try await ProcessRunner.run(
                path: "/bin/sh",
                arguments: ["-c", "sleep 30"],
                timeout: 60
            )
        }

        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled process unexpectedly completed")
        } catch ProcessRunnerError.cancelled {
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }
    }
}
