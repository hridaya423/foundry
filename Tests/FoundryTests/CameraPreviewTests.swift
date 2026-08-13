import AVFoundation
import XCTest
@testable import Foundry

@MainActor
final class CameraPreviewTests: XCTestCase {
    func testStateShowsDistinctPermissionFailures() async {
        for (authorization, expected) in [(CameraAuthorization.denied, CameraPreviewState.Status.denied), (.restricted, .restricted)] {
            let camera = TestCamera(authorization: authorization)
            let state = CameraPreviewState(camera: camera)
            state.start()
            await eventually { state.status == expected }
        }
    }

    func testStateStartsOnlyAfterCameraReportsActive() async {
        let camera = TestCamera()
        let state = CameraPreviewState(camera: camera)
        state.start()
        await eventually { state.status == .active }
        XCTAssertEqual(camera.startCount, 1)
    }

    func testRetryAfterConfigurationFailureDoesNotDuplicateInputs() async {
        let camera = TestCamera(startResults: [.failure(.configuration), .success(())])
        let state = CameraPreviewState(camera: camera)
        state.start()
        await eventually { state.status == .failed(.configuration) }
        state.retry()
        await eventually { state.status == .active }
        XCTAssertEqual(camera.startCount, 2)
    }

    func testStartIsIdempotentAndStopInvalidatesPendingStart() async {
        let camera = TestCamera(delayedStart: true)
        let state = CameraPreviewState(camera: camera)
        state.start(); state.start()
        await camera.waitForStart()
        state.stop()
        camera.finishStart()
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(state.status, .idle)
        XCTAssertEqual(camera.stopCount, 1)
    }

    func testNoDeviceIsTyped() async {
        let camera = TestCamera(startResults: [.failure(.noDevice)])
        let state = CameraPreviewState(camera: camera)
        state.start()
        await eventually { state.status == .noDevice }
    }

    private func eventually(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("condition did not become true")
    }
}

@MainActor
private final class TestCamera: CameraCapturing {
    let session = AVCaptureSession()
    var authorizationStatus: CameraAuthorization
    var startResults: [Result<Void, CameraCaptureError>]
    var delayedStart: Bool
    var continuation: CheckedContinuation<Result<Void, CameraCaptureError>, Never>?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var startEnteredContinuation: CheckedContinuation<Void, Never>?

    init(authorization: CameraAuthorization = .authorized, startResults: [Result<Void, CameraCaptureError>] = [.success(())], delayedStart: Bool = false) {
        self.authorizationStatus = authorization; self.startResults = startResults; self.delayedStart = delayedStart
    }
    func authorization() -> CameraAuthorization { authorizationStatus }
    func requestPermission() async -> CameraPermissionResult { .granted }
    func start() async -> Result<Void, CameraCaptureError> {
        startCount += 1
        startEnteredContinuation?.resume()
        startEnteredContinuation = nil
        if delayedStart { return await withCheckedContinuation { continuation = $0 } }
        return startResults.isEmpty ? .success(()) : startResults.removeFirst()
    }
    func stop() { stopCount += 1; continuation?.resume(returning: .failure(.cancelled)); continuation = nil }
    func finishStart() { continuation?.resume(returning: .success(())); continuation = nil }
    func waitForStart() async {
        if startCount > 0 { return }
        await withCheckedContinuation { startEnteredContinuation = $0 }
    }
}
