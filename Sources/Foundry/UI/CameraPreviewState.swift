@preconcurrency import AVFoundation
import AppKit
import Foundation

@MainActor
final class CameraPreviewState: ObservableObject {
    enum Status: Equatable {
        case idle
        case requestingPermission
        case starting
        case active
        case denied
        case unavailable
        case failed(String)

        var message: String? {
            switch self {
            case .idle, .active:
                nil
            case .requestingPermission:
                "Requesting camera access…"
            case .starting:
                "Starting camera…"
            case .denied:
                "Camera access is denied"
            case .unavailable:
                "No camera is available"
            case let .failed(message):
                message
            }
        }
    }

    @Published private(set) var status: Status = .idle
    nonisolated(unsafe) let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "foundry.camera.session")
    private var configured = false
    private var startTask: Task<Void, Never>?

    func start() {
        guard status != .active, status != .starting, status != .requestingPermission else { return }
        startTask?.cancel()
        startTask = Task {
            status = .requestingPermission
            let permission = await cameraPermission()
            guard Task.isCancelled == false else { return }
            guard permission else {
                status = .denied
                return
            }

            status = .starting
            let configuration = await configureIfNeeded()
            guard Task.isCancelled == false else { return }
            switch configuration {
            case .configured:
                configured = true
                status = .active
            case .alreadyConfigured:
                status = .active
            case .unavailable:
                status = .unavailable
            case let .failed(message):
                status = .failed(message)
            }

            guard status == .active else { return }
            queue.async { [session] in
                if session.isRunning == false {
                    session.startRunning()
                }
            }
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        queue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
        status = .idle
    }

    func retry() {
        configured = false
        start()
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }

    private func cameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    private enum ConfigurationResult: Sendable {
        case configured
        case alreadyConfigured
        case unavailable
        case failed(String)
    }

    private func configureIfNeeded() async -> ConfigurationResult {
        guard configured == false else { return .alreadyConfigured }
        return await withCheckedContinuation { continuation in
            queue.async { [session] in
                session.beginConfiguration()
                session.sessionPreset = .high
                defer { session.commitConfiguration() }

                guard let device = AVCaptureDevice.default(for: .video) else {
                    continuation.resume(returning: .unavailable)
                    return
                }
                guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                    continuation.resume(returning: .failed("Could not open the camera"))
                    return
                }
                session.addInput(input)
                continuation.resume(returning: .configured)
            }
        }
    }

}
