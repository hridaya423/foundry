import AppKit
import Combine
import Foundation
import FoundryServices
#if canImport(FoundationModels)
import FoundationModels
import Observation
#endif

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case shortcut
    case bringYourStuff
    case done
}

struct ImportSource: Identifiable, Equatable {
    enum Kind: String { case alfred, raycast }
    let kind: Kind
    var available: Int?
    var imported: Int?
    var id: Kind { kind }
    var name: String { kind == .alfred ? "Alfred" : "Raycast" }
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
        BestEffort.attempt("reload preference cache (killall cfprefsd)") { try process.run() }
    }

    static let keyboardShortcutsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
}

@MainActor
@Observable
final class OnboardingState {
    nonisolated static let completedVersionKey = "foundry.onboarding.completedVersion"
    nonisolated static let stepKey = "foundry.onboarding.step"

    private(set) var step: OnboardingStep
    private(set) var didLaunch = false
    private(set) var openedWithoutLaunch = false
    private(set) var spotlightHoldsCommandSpace = false
    private(set) var commandSpaceHolders: [String] = []
    private(set) var commandSpaceUnreachable = false
    private(set) var importSources: [ImportSource] = []
    private(set) var chosenAI: String?
    var startsAtLogin = true
    var isWaitingForSpotlight = false

    let panel: CommandPanelState
    let permissions: PermissionHealthState
    var onFinish: (() -> Void)?
    /// Fired on every step transition and finish — activation funnel telemetry.
    var onStepChanged: ((OnboardingStep) -> Void)?
    private let localState: LocalStateStore
    private let version: String
    private var spotlightPoll: Timer?
    private let detectImportSources: () -> [ImportSource]
    private let appleIntelligence: () -> Bool
    private let registerLoginItem: (Bool) -> Void

    init(panel: CommandPanelState, permissions: PermissionHealthState, localState: LocalStateStore = .shared,
        version: String = OnboardingState.currentVersion,
        importSources: @escaping () -> [ImportSource] = OnboardingState.detectImportSources,
        appleIntelligence: @escaping () -> Bool = { OnboardingState.appleIntelligenceAvailable },
        registerLoginItem: ((Bool) -> Void)? = nil) {
        self.panel = panel
        self.permissions = permissions
        self.localState = localState
        self.version = version
        self.detectImportSources = importSources
        self.appleIntelligence = appleIntelligence
        self.registerLoginItem = registerLoginItem ?? { [weak panel] in panel?.settings.setLaunchAtLogin($0) }
        self.step = localState.get(\.onboardingStep).flatMap(OnboardingStep.init(rawValue:)) ?? .welcome
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static func shouldShowAutomatically(localState: LocalStateStore = .shared, configExistedAtLaunch: Bool) -> Bool {
        localState.get(\.onboardingCompletedVersion) == nil
            && (configExistedAtLaunch == false || localState.get(\.onboardingStep) != nil)
    }

    func markPresented() {
        localState.set(\.onboardingStep, step.rawValue)
    }

    var canGoBack: Bool { step != .welcome }

    private func neighbour(of step: OnboardingStep, forward: Bool) -> OnboardingStep? {
        guard var candidate = OnboardingStep(rawValue: step.rawValue + (forward ? 1 : -1)) else { return nil }
        if candidate == .bringYourStuff {
            if forward { importSources = detectImportSources() }
            if importSources.isEmpty { candidate = forward ? .done : .shortcut }
        }
        return candidate
    }

    func advance() {
        guard let next = neighbour(of: step, forward: true) else { return finish() }
        go(to: next)
    }

    func back() {
        guard let previous = neighbour(of: step, forward: false) else { return }
        go(to: previous)
    }

    func go(to next: OnboardingStep) {
        step = next
        if next == .bringYourStuff, importSources.isEmpty { importSources = detectImportSources() }
        if next == .done { chooseAI() }
        localState.set(\.onboardingStep, next.rawValue)
        onStepChanged?(next)
    }

    func finish() {
        settleShortcut()
        if startsAtLogin { registerLoginItem(true) }
        end()
        onStepChanged?(.done)
        onFinish?()
    }

    /// Esc, Skip setup and the close button. Nothing outside Foundry changes.
    func abandon(rivals: [LauncherRival] = LauncherRival.all,
        spotlightEnabled: () -> Bool = SpotlightShortcut.isEnabledOnThisMac) {
        guard hasEnded == false else { return }
        settleShortcut(rivals: rivals, spotlightEnabled: spotlightEnabled)
        end()
        onFinish?()
    }

    /// If ⌘ Space is still someone else's and the user never agreed to take
    /// it, Foundry falls back to ⌥ Space so it is never left without a shortcut.
    private func settleShortcut(rivals: [LauncherRival] = LauncherRival.all,
        spotlightEnabled: () -> Bool = SpotlightShortcut.isEnabledOnThisMac) {
        guard didClaimCommandSpace == false, panel.settings.hotkey == .commandSpace else { return }
        if commandSpaceUnreachable || spotlightEnabled() || rivals.contains(where: { $0.holdsCommandSpace() }) {
            panel.settings.setHotkey(.optionSpace)
        }
    }

    private var hasEnded = false

    private func end() {
        hasEnded = true
        stopWaitingForSpotlight()
        panel.searchHint = nil
        localState.update { state in
            state.onboardingCompletedVersion = version
            state.onboardingStep = nil
        }
    }

    func restart() {
        hasEnded = false
        didLaunch = false
        openedWithoutLaunch = false
        go(to: .welcome)
    }

    /// Fires once when the first real launch happens during the shortcut step.
    var onDidTryPanel: (() -> Void)?

    /// A result ran from the panel. Opening and closing it is not enough.
    func completeTryIt() {
        guard step == .shortcut, didLaunch == false else { return }
        didLaunch = true
        panel.searchHint = nil
        onDidTryPanel?()
    }

    func panelClosedWithoutLaunch() {
        guard step == .shortcut, didLaunch == false else { return }
        openedWithoutLaunch = true
    }

    /// ⌘ Space reached this window, so no global hotkey took it.
    func commandSpaceReachedWindow() {
        guard step == .shortcut, panel.settings.hotkey == .commandSpace else { return }
        commandSpaceUnreachable = true
    }

    func detectCommandSpaceHolders(rivals: [LauncherRival] = LauncherRival.all,
        spotlightEnabled: () -> Bool = SpotlightShortcut.isEnabledOnThisMac) {
        guard didClaimCommandSpace == false else { return }
        commandSpaceHolders = (spotlightEnabled() ? ["Spotlight"] : []) + rivals.filter { $0.holdsCommandSpace() }.map(\.name)
    }

    func useOptionSpace() {
        commandSpaceHolders = []
        commandSpaceUnreachable = false
        panel.settings.setHotkey(.optionSpace)
    }

    struct SuggestedLaunch: Equatable {
        let name: String
        let prefix: String
    }

    /// A running app that is not Foundry, Finder or the frontmost app; Safari otherwise.
    static func suggestedLaunch(running: [(name: String, bundleID: String)], frontmost: String?) -> SuggestedLaunch {
        let excluded: Set<String> = ["com.apple.finder", Bundle.main.bundleIdentifier ?? "app.foundry", frontmost ?? ""]
        let name = running.first { app in
            excluded.contains(app.bundleID) == false && app.name.count <= 14
                && app.name.allSatisfy { $0.isLetter || $0 == " " } && app.name.count >= 2
        }?.name ?? "Safari"
        return SuggestedLaunch(name: name, prefix: String(name.prefix(2)).lowercased())
    }

    static func suggestedLaunchOnThisMac() -> SuggestedLaunch {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.localizedName.flatMap { name in app.bundleIdentifier.map { (name: name, bundleID: $0) } } }
        return suggestedLaunch(running: running, frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    nonisolated static func detectImportSources() -> [ImportSource] {
        var sources: [ImportSource] = []
        let alfred = AlfredSnippetImporter(preferencesRoot: LauncherRival.alfredPreferencesRoot()).snippets().count
        if alfred > 0 { sources.append(ImportSource(kind: .alfred, available: alfred)) }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.raycast.macos") != nil {
            sources.append(ImportSource(kind: .raycast))
        }
        return sources
    }

    func importSnippets(from kind: ImportSource.Kind, file: URL? = nil) {
        guard let index = importSources.firstIndex(where: { $0.kind == kind }) else { return }
        let incoming: [StoredSnippet]
        switch kind {
        case .alfred:
            incoming = AlfredSnippetImporter(preferencesRoot: LauncherRival.alfredPreferencesRoot()).snippets()
        case .raycast:
            guard let file, let data = try? Data(contentsOf: file),
                  let decoded = try? JSONDecoder().decode([RaycastSnippetFile].self, from: data) else { return }
            incoming = decoded.map { StoredSnippet(title: $0.name, content: $0.text, keyword: $0.keyword ?? "") }
        }
        importSources[index].imported = panel.snippets.add(incoming)
    }

    var receipt: [String] {
        var lines: [String] = []
        if panel.settings.hotkey == .commandSpace {
            lines.append(String(localized: "⌘ Space is yours"))
        } else {
            lines.append(String(localized: "\(panel.settings.hotkey.displayName) opens Foundry"))
        }
        lines += takeovers.filter { $0.status == .done }.map { String(localized: "\($0.name) moved to ⌥ Space") }
        lines += importSources.compactMap { source in
            source.imported.flatMap { $0 > 0 ? String(localized: "\($0) snippets from \(source.name)") : nil }
        }
        if let chosenAI { lines.append(String(localized: "\(chosenAI) answers Tab")) }
        return lines
    }

    private func chooseAI() {
        if appleIntelligence() {
            makeDefault(kind: .appleFoundationModels)
            chosenAI = "Apple Intelligence"
        } else if let kind = detectedLocalKind,
                  let profile = panel.aiSettings.aiProfiles.first(where: { $0.kind == kind }) {
            if profile.enabled == false { panel.aiSettings.setAIProfileEnabled(true, id: profile.id) }
            panel.aiSettings.setDefaultAIProfile(profile.id)
            chosenAI = kind.displayName
        } else {
            chosenAI = nil
        }
    }

    private var spotlightTicks = 0

    struct Takeover: Identifiable, Equatable {
        enum Status { case working, done, failed }
        let id: String
        let name: String
        var status: Status
    }

    /// Spotlight's state lives in the flags above; this tracks the launchers
    /// moved off ⌘ Space.
    private(set) var takeovers: [Takeover] = []
    private(set) var didClaimSpotlight = false
    private(set) var didClaimCommandSpace = false

    /// Makes ⌘ Space Foundry's: turns off Spotlight's shortcut and moves any
    /// other launcher holding it to ⌥ Space.
    func claimCommandSpace(rivals: [LauncherRival] = LauncherRival.all,
        spotlightEnabled: @escaping @Sendable () -> Bool = SpotlightShortcut.isEnabledOnThisMac,
        disableSpotlight: () -> Bool = SpotlightShortcut.disableOnThisMac) {
        didClaimCommandSpace = true
        if spotlightEnabled() { didClaimSpotlight = true }
        useCommandSpace(spotlightEnabled: spotlightEnabled, disableSpotlight: disableSpotlight)
        for rival in rivals where takeovers.contains(where: { $0.id == rival.id }) == false && rival.holdsCommandSpace() {
            takeovers.append(Takeover(id: rival.id, name: rival.name, status: .working))
            Task { @MainActor [weak self] in
                let released = await rival.release()
                guard let self, let index = self.takeovers.firstIndex(where: { $0.id == rival.id }) else { return }
                self.takeovers[index].status = released ? .done : .failed
            }
        }
    }

    func useCommandSpace(spotlightEnabled: @escaping @Sendable () -> Bool = SpotlightShortcut.isEnabledOnThisMac,
        disableSpotlight: () -> Bool = SpotlightShortcut.disableOnThisMac) {
        guard spotlightEnabled() else {
            spotlightHoldsCommandSpace = false
            panel.settings.setHotkey(.commandSpace)
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
            panel.settings.setHotkey(.commandSpace)
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
            let probe = request
            if (await BestEffort.attempt("onboarding reachability probe") { try await URLSession.shared.data(for: probe) }) != nil {
                return kind
            }
        }
        return nil
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
