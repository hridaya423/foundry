import AppKit
@preconcurrency import ApplicationServices
import Foundation
import Observation

enum PermissionKind: String, CaseIterable, Identifiable {
    case accessibility
    case automation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .automation: "Automation"
        }
    }

    var purpose: String {
        switch self {
        case .accessibility: "Paste into apps, expand snippets, and arrange windows."
        case .automation: "Read Notes and browser tabs. macOS asks the first time you use them."
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .automation: "gearshape.2"
        }
    }

    var settingsURL: URL {
        switch self {
        case .accessibility: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
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
    private var poll: Timer?

    init(accessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.accessibilityTrusted = accessibilityTrusted
        refresh()
    }

    static func status(for kind: PermissionKind, accessibilityTrusted: Bool) -> PermissionStatus {
        switch kind {
        case .accessibility: accessibilityTrusted ? .granted : .notGranted
        case .automation: .askedOnUse
        }
    }

    func status(for kind: PermissionKind) -> PermissionStatus {
        statuses[kind] ?? .notGranted
    }

    func refresh() {
        let trusted = accessibilityTrusted()
        let next = Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map { ($0, Self.status(for: $0, accessibilityTrusted: trusted)) })
        if next != statuses { statuses = next }
    }

    func request(_ kind: PermissionKind) {
        switch kind {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            if AXIsProcessTrustedWithOptions(options) == false {
                NSWorkspace.shared.open(kind.settingsURL)
            }
        case .automation:
            NSWorkspace.shared.open(kind.settingsURL)
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
