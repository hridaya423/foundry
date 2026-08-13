import XCTest
@testable import Foundry
import FoundryServices

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

    func testRunnerBoundsNewlineFreeOutputLines() {
        let limit = 1024
        let result = ProcessRunner.runSynchronously(
            path: "/bin/sh",
            arguments: ["-c", "head -c 5000000 /dev/zero | tr '\\0' x"],
            timeout: 5,
            outputLimit: limit
        )

        XCTAssertEqual(result?.exitCode, 0)
        XCTAssertLessThanOrEqual(result?.stdout.utf8.count ?? .max, limit)
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

    func testRunnerUsesEnvironmentAndCurrentDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory
        let runner = SystemProcessRunner()
        let result = try await runner.run(path: "/bin/sh", arguments: ["-c", "printf '%s:%s' \"$FOUNDRY_TEST\" \"$PWD\""], environment: ["FOUNDRY_TEST": "present"], currentDirectoryURL: directory)
        XCTAssertTrue(result.stdout.hasPrefix("present:"))
        XCTAssertEqual(URL(fileURLWithPath: String(result.stdout.dropFirst("present:".count))).standardizedFileURL, directory.standardizedFileURL)
    }

    func testNonzeroExitIsDistinguishedFromLaunchFailure() async throws {
        let runner = SystemProcessRunner()
        let result = try await runner.run(path: "/bin/sh", arguments: ["-c", "exit 7"])
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.timedOut)
        XCTAssertFalse(result.cancelled)
    }

    func testLaunchFailureIsThrown() async {
        do {
            _ = try await SystemProcessRunner().run(path: "/not/a/real/executable", arguments: [])
            XCTFail("launch should fail")
        } catch ProcessRunnerError.launchFailed {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
