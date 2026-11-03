import AppKit
@preconcurrency import ApplicationServices
import Foundation
import Observation

enum PermissionKind: String, CaseIterable, Identifiable {
    case accessibility
    case screenRecording
    case automation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .automation: "Automation"
        }
    }

    var purpose: String {
        switch self {
        case .accessibility: "Paste into apps, expand snippets, and arrange windows."
        case .screenRecording: "Read text from anywhere on the screen."
        case .automation: "Read Notes and browser tabs. macOS asks the first time you use them."
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .screenRecording: "text.viewfinder"
        case .automation: "gearshape.2"
        }
    }

    var settingsURL: URL {
        switch self {
        case .accessibility: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .screenRecording: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .automation: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        }
    }
}

enum PermissionStatus: Equatable {
    case granted
    case notGranted
    case askedOnUse

    var label: String {
        switch self {
        case .granted: "Allowed"
        case .notGranted: "Not allowed"
        case .askedOnUse: "Asked when needed"
        }
    }
}

@MainActor
@Observable
final class PermissionHealthState {
    private(set) var statuses: [PermissionKind: PermissionStatus] = [:]
    private let accessibilityTrusted: () -> Bool
    private let localState: LocalStateStore
    private let prompt: () -> Void
    private let open: (URL) -> Void
    private let screenCaptureAllowed: () -> Bool
    private let requestScreenCapture: () -> Void
    private var poll: Timer?

    init(accessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        localState: LocalStateStore = .shared,
        prompt: @escaping () -> Void = { PermissionHealthState.promptForAccessibility() },
        open: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        screenCaptureAllowed: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        requestScreenCapture: @escaping () -> Void = { _ = CGRequestScreenCaptureAccess() }) {
        self.accessibilityTrusted = accessibilityTrusted
        self.localState = localState
        self.prompt = prompt
        self.open = open
        self.screenCaptureAllowed = screenCaptureAllowed
        self.requestScreenCapture = requestScreenCapture
        refresh()
    }

    nonisolated static func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func status(for kind: PermissionKind, accessibilityTrusted: Bool, screenCapture: Bool = false) -> PermissionStatus {
        switch kind {
        case .accessibility: accessibilityTrusted ? .granted : .notGranted
        case .screenRecording: screenCapture ? .granted : .notGranted
        case .automation: .askedOnUse
        }
    }

    func status(for kind: PermissionKind) -> PermissionStatus {
        statuses[kind] ?? .notGranted
    }

    func refresh() {
        let trusted = accessibilityTrusted()
        let screen = screenCaptureAllowed()
        let next = Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map {
            ($0, Self.status(for: $0, accessibilityTrusted: trusted, screenCapture: screen))
        })
        if next != statuses { statuses = next }
    }

    func request(_ kind: PermissionKind) {
        switch kind {
        case .accessibility:
            guard accessibilityTrusted() == false else { break }
            if localState.get(\.accessibilityPrompted) {
                open(kind.settingsURL)
            } else {
                localState.set(\.accessibilityPrompted, true)
                prompt()
            }
        case .screenRecording:
            guard screenCaptureAllowed() == false else { break }
            if localState.get(\.screenRecordingPrompted) {
                open(kind.settingsURL)
            } else {
                localState.set(\.screenRecordingPrompted, true)
                requestScreenCapture()
            }
        case .automation:
            open(kind.settingsURL)
        }
        refresh()
    }

    func startPolling() {
        guard poll == nil else { return }
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopPolling() {
        poll?.invalidate()
        poll = nil
    }
}
