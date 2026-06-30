@preconcurrency import AVFoundation
import Foundation

@MainActor
final class CameraPreviewState: ObservableObject {
    @Published var status = ""
    nonisolated(unsafe) let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "foundry.camera.session")
    private var configured = false

    func start() {
        Task {
            let permission = await cameraPermission()
            guard permission else {
                status = "Camera access denied"
                return
            }
            status = ""
            configureIfNeeded()
            queue.async { [session] in
                if session.isRunning == false {
                    session.startRunning()
                }
            }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
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

    private func configureIfNeeded() {
        guard configured == false else { return }
        configured = true

        queue.async { [weak self] in
            guard let self else { return }
            session.beginConfiguration()
            session.sessionPreset = .high
            defer { session.commitConfiguration() }

            guard let device = AVCaptureDevice.default(for: .video) else {
                Task { @MainActor in self.status = "No camera available" }
                return
            }
            guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                Task { @MainActor in self.status = "Could not open camera" }
                return
            }
            session.addInput(input)
        }
    }
}
