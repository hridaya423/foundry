import AppKit
import AVFoundation
import Foundation

@MainActor
final class CameraPreviewState: ObservableObject {
    enum Status: Equatable {
        case idle, requestingPermission, starting, active
        case denied, restricted, noDevice
        case failed(CameraCaptureError)

        var message: String? {
            switch self {
            case .idle, .active: nil
            case .requestingPermission: "Requesting camera access…"
            case .starting: "Starting camera…"
            case .denied: "Camera access is denied"
            case .restricted: "Camera access is restricted"
            case .noDevice: "No camera is available"
            case .failed: "Could not start the camera"
            }
        }
    }

    @Published private(set) var status: Status = .idle
    let session: AVCaptureSession
    private let camera: CameraCapturing
    private var task: Task<Void, Never>?
    private var generation = 0
    private var isStarting = false

    init(camera: CameraCapturing = CameraCaptureService()) {
        self.camera = camera
        session = camera.session
    }

    func start() {
        guard !isStarting, status != .active, status != .starting, status != .requestingPermission else { return }
        isStarting = true
        generation += 1
        let token = generation
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            defer { isStarting = false }
            switch camera.authorization() {
            case .denied: status = .denied; return
            case .restricted: status = .restricted; return
            case .notDetermined:
                status = .requestingPermission
                switch await camera.requestPermission() {
                case .granted: break
                case .denied: status = .denied; return
                case .restricted: status = .restricted; return
                }
            case .authorized: break
            }
            guard !Task.isCancelled, token == generation else { return }
            status = .starting
            let result = await camera.start()
            guard !Task.isCancelled, token == generation else { return }
            switch result {
            case .success: status = .active
            case .failure(.denied): status = .denied
            case .failure(.restricted): status = .restricted
            case .failure(.noDevice): status = .noDevice
            case let .failure(error): status = .failed(error)
            }
        }
    }

    func stop() {
        generation += 1
        task?.cancel(); task = nil
        camera.stop()
        status = .idle
    }

    func retry() { start() }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }
}
