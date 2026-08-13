import AppKit
import AVFoundation
import SwiftUI

struct CameraPreviewView: View {
    @ObservedObject var state: CameraPreviewState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.05))

                if state.status == .starting || state.status == .active {
                    CameraPreviewSurface(session: state.session)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                if let message = state.status.message {
                    VStack(spacing: 10) {
                        if state.status == .requestingPermission || state.status == .starting {
                            ProgressView()
                                .controlSize(.large)
                        } else {
                            Image(systemName: "camera")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(FoundryTheme.secondaryText)
                        }
                        Text(message)
                            .font(FoundryTheme.body(size: 15, weight: .semibold))
                            .foregroundStyle(FoundryTheme.primaryText)

                        if state.status == .denied {
                            HStack(spacing: 8) {
                                Button("Open Privacy Settings") { state.openPrivacySettings() }
                                Button("Retry") { state.retry() }
                            }
                            .buttonStyle(PressableButtonStyle())
                            .font(FoundryTheme.body(size: 12, weight: .semibold))
                        } else if state.status != .requestingPermission && state.status != .starting && state.status != .active && state.status != .idle {
                            Button("Retry") { state.retry() }
                                .buttonStyle(PressableButtonStyle())
                                .font(FoundryTheme.body(size: 12, weight: .semibold))
                        }
                    }
                    .padding(24)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Live camera preview")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .onAppear { state.start() }
        .onDisappear { state.stop() }
    }
}

struct CameraPreviewSurface: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.previewLayer.session = session
    }
}

final class PreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        previewLayer.frame = bounds
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}
