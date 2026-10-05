import AppKit
import Combine
import Foundation
#if canImport(FoundationModels)
import FoundationModels
import Observation
#endif

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case shortcut
    case tryIt
    case preferences
    case permissions
    case ai
    case done
}

enum SpotlightShortcut {
    static let symbolicHotKeyID = "64"
    static let suiteName = "com.apple.symbolichotkeys"

    static func isEnabled(symbolicHotKeys: [String: Any]?) -> Bool {
        guard let entry = symbolicHotKeys?[symbolicHotKeyID] as? [String: Any] else { return true }
        if let enabled = entry["enabled"] as? Bool { return enabled }
        if let enabled = entry["enabled"] as? Int { return enabled != 0 }
        return true
    }

    static func isEnabledOnThisMac() -> Bool {
        let defaults = UserDefaults(suiteName: suiteName)
        return isEnabled(symbolicHotKeys: defaults?.dictionary(forKey: "AppleSymbolicHotKeys"))
    }

    static func setEnabled(_ enabled: Bool, suiteName: String = suiteName, reloadPreferences: () -> Void = reloadPreferences) -> Bool {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return false }
        var hotkeys = defaults.dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
        var entry = hotkeys[symbolicHotKeyID] as? [String: Any] ?? [:]
        entry["enabled"] = enabled
        hotkeys[symbolicHotKeyID] = entry
        defaults.set(hotkeys, forKey: "AppleSymbolicHotKeys")
        defaults.synchronize()
        reloadPreferences()
        return true
    }

    static func disableOnThisMac() -> Bool {
        setEnabled(false)
    }

    // SystemUIServer caches symbolic hotkeys through cfprefsd; restarting the
    // prefs daemon forces every client to re-read without a logout.
    static func reloadPreferences() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["cfprefsd"]
        try? process.run()
    }

    static let keyboardShortcutsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
}

@MainActor
@Observable
final class OnboardingState {
    static let completedVersionKey = "foundry.onboarding.completedVersion"
    static let stepKey = "foundry.onboarding.step"

    private(set) var step: OnboardingStep
    private(set) var didTryPanel = false
    private(set) var spotlightHoldsCommandSpace = false
    var isWaitingForSpotlight = false

    let panel: CommandPanelState
    let permissions: PermissionHealthState
    var onFinish: (() -> Void)?
    private let defaults: UserDefaults
    private let version: String
    private var spotlightPoll: Timer?

    init(panel: CommandPanelState, permissions: PermissionHealthState, defaults: UserDefaults = .standard, version: String = OnboardingState.currentVersion) {
        self.panel = panel
        self.permissions = permissions
        self.defaults = defaults
        self.version = version
        self.step = OnboardingStep(rawValue: defaults.integer(forKey: Self.stepKey)) ?? .welcome
        panel.onResultExecuted = { [weak self] in self?.panelDidRunCommand() }
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static func shouldShowAutomatically(defaults: UserDefaults = .standard, configExistedAtLaunch: Bool) -> Bool {
        defaults.string(forKey: completedVersionKey) == nil && configExistedAtLaunch == false
    }

    var canGoBack: Bool { step != .welcome }

    func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return finish() }
        go(to: next)
    }

    func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        go(to: previous)
    }

    func go(to next: OnboardingStep) {
        step = next
        defaults.set(next.rawValue, forKey: Self.stepKey)
    }

    func finish() {
        stopWaitingForSpotlight()
        defaults.set(version, forKey: Self.completedVersionKey)
        defaults.removeObject(forKey: Self.stepKey)
        onFinish?()
    }

    func restart() {
        go(to: .welcome)
        didTryPanel = false
    }

    func panelDidRunCommand() {
        guard step == .tryIt, didTryPanel == false else { return }
        didTryPanel = true
    }

    private var spotlightTicks = 0

    func useCommandSpace(spotlightEnabled: @escaping @Sendable () -> Bool = SpotlightShortcut.isEnabledOnThisMac, disableSpotlight: () -> Bool = SpotlightShortcut.disableOnThisMac) {
        guard spotlightEnabled() else {
            spotlightHoldsCommandSpace = false
            panel.setHotkey(.commandSpace)
            return
        }
        spotlightTicks = 0
        isWaitingForSpotlight = true
        if disableSpotlight() == false {
            spotlightHoldsCommandSpace = true
        }
        spotlightPoll?.invalidate()
        spotlightPoll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.spotlightPollTick(spotlightEnabled: spotlightEnabled)
            }
        }
    }

    func spotlightPollTick(spotlightEnabled: () -> Bool) {
        guard spotlightEnabled() else {
            spotlightHoldsCommandSpace = false
            stopWaitingForSpotlight()
            panel.setHotkey(.commandSpace)
            return
        }
        spotlightTicks += 1
        if spotlightTicks >= 10 {
            spotlightHoldsCommandSpace = true
        }
    }

    func openSpotlightShortcutSettings() {
        NSWorkspace.shared.open(SpotlightShortcut.keyboardShortcutsURL)
    }

    func stopWaitingForSpotlight() {
        spotlightPoll?.invalidate()
        spotlightPoll = nil
        isWaitingForSpotlight = false
    }

    var menuBarIconOn: Bool { panel.showMenuBarIcon }
    func setMenuBarIcon(_ on: Bool) { panel.setMenuBarIconVisible(on) }

    var clipboardCaptureOn: Bool { panel.clipboardCaptureEnabled }
    func setClipboardCapture(_ on: Bool) { panel.setClipboardEnabled(on) }

    enum AIChoice {
        case appleIntelligence, localModel, later, off
    }

    static var appleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26, *), case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    func detectLocalModel() async -> AIProviderKind? {
        let candidates: [(AIProviderKind, String)] = [
            (.ollama, "http://127.0.0.1:11434/api/tags"),
            (.openAICompatible, "http://127.0.0.1:1234/v1/models")
        ]
        for (kind, urlString) in candidates {
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 0.4
            if (try? await URLSession.shared.data(for: request)) != nil {
                return kind
            }
        }
        return nil
    }

    func chooseAI(_ choice: AIChoice) {
        switch choice {
        case .appleIntelligence:
            makeDefault(kind: .appleFoundationModels)
        case .localModel:
            let kind = detectedLocalKind ?? .ollama
            if let profile = panel.aiSettings.aiProfiles.first(where: { $0.kind == kind }) {
                if profile.enabled == false { panel.aiSettings.setAIProfileEnabled(true, id: profile.id) }
                panel.aiSettings.setDefaultAIProfile(profile.id)
            } else {
                makeDefault(kind: .ollama)
            }
        case .later:
            break
        case .off:
            panel.setCommandEnabled(false, for: "foundry.ai")
        }
        advance()
    }

    private(set) var detectedLocalKind: AIProviderKind?

    func refreshLocalModelDetection() {
        Task { @MainActor [weak self] in
            self?.detectedLocalKind = await self?.detectLocalModel() ?? nil
        }
    }

    private func makeDefault(kind: AIProviderKind) {
        guard let profile = panel.aiSettings.aiProfiles.first(where: { $0.kind == kind && $0.enabled }) else { return }
        panel.aiSettings.setDefaultAIProfile(profile.id)
    }
}
