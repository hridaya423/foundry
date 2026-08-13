@preconcurrency import AVFoundation
import Foundation

enum CameraAuthorization: Equatable, Sendable {
    case authorized, notDetermined, denied, restricted
}

enum CameraPermissionResult: Equatable, Sendable {
    case granted, denied, restricted
}

enum CameraCaptureError: Error, Equatable, Sendable {
    case denied
    case restricted
    case noDevice
    case configuration
    case cancelled
    case startFailed
}

@MainActor
protocol CameraCapturing: AnyObject {
    var session: AVCaptureSession { get }
    func authorization() -> CameraAuthorization
    func requestPermission() async -> CameraPermissionResult
    func start() async -> Result<Void, CameraCaptureError>
    func stop()
}

final class CameraCaptureService: CameraCapturing, @unchecked Sendable {
    private let captureState: CaptureState

    nonisolated var session: AVCaptureSession { captureState.session }
    private let queue = DispatchQueue(label: "foundry.camera.capture")

    init(session: AVCaptureSession = AVCaptureSession()) {
        captureState = CaptureState(session: session)
    }

    func authorization() -> CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        @unknown default: .denied
        }
    }

    func requestPermission() async -> CameraPermissionResult {
        switch authorization() {
        case .authorized: return .granted
        case .restricted: return .restricted
        case .denied: return .denied
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        }
    }

    nonisolated func start() async -> Result<Void, CameraCaptureError> {
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: .failure(.cancelled)); return
                }
                let token = self.captureState.generation + 1
                self.captureState.generation = token
                if self.captureState.session.isRunning {
                    continuation.resume(returning: .success(())); return
                }
                switch self.configureIfNeeded() {
                case .noDevice:
                    continuation.resume(returning: .failure(.noDevice)); return
                case .configuration:
                    continuation.resume(returning: .failure(.configuration)); return
                case .configured:
                    break
                }
                self.captureState.runningContinuation = continuation
                self.captureState.session.startRunning()
                guard self.captureState.generation == token else {
                    self.captureState.runningContinuation = nil
                    continuation.resume(returning: .failure(.cancelled)); return
                }
                self.captureState.runningContinuation = nil
                continuation.resume(returning: self.captureState.session.isRunning ? .success(()) : .failure(.startFailed))
            }
        }
    }

    nonisolated func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.captureState.generation += 1
            self.captureState.runningContinuation?.resume(returning: .failure(.cancelled))
            self.captureState.runningContinuation = nil
            if self.captureState.session.isRunning { self.captureState.session.stopRunning() }
        }
    }

    private enum ConfigurationResult { case configured, noDevice, configuration }

    private nonisolated func configureIfNeeded() -> ConfigurationResult {
        guard !captureState.configured else { return .configured }
        guard let device = AVCaptureDevice.default(for: .video) else { return .noDevice }
        guard let input = try? AVCaptureDeviceInput(device: device), captureState.session.canAddInput(input) else { return .configuration }
        captureState.session.beginConfiguration()
        defer { captureState.session.commitConfiguration() }
        if captureState.session.canSetSessionPreset(.hd1280x720) { captureState.session.sessionPreset = .hd1280x720 }
        captureState.session.addInput(input)
        captureState.configured = true
        return .configured
    }

    private final class CaptureState: @unchecked Sendable {
        let session: AVCaptureSession
        var configured = false
        var generation = 0
        var runningContinuation: CheckedContinuation<Result<Void, CameraCaptureError>, Never>?

        init(session: AVCaptureSession) {
            self.session = session
        }
    }
}
