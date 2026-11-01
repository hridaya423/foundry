import AppKit
import Carbon
import FoundryDomain
import SwiftUI

private typealias Brand = FoundryTheme.Brand

struct OnboardingView: View {
    var state: OnboardingState
    var keyboard: KeyboardMirror

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var windowState
    /// The opening plays when the user can first see it: macOS may open the
    /// window behind the frontmost app and bring it forward later.
    @State private var windowSeen = false
    /// Offscreen renders never become key.
    var opensImmediately = false
    @State private var panelOpenedForTryIt = false
    @State private var aiSelection: OnboardingState.AIChoice?
    @State private var demoKeys: Set<String> = []

    static let size = CGSize(width: 880, height: 580)
    private static let margin: CGFloat = 64
    /// Level with the lists on the other steps.
    private static let keyboardTop: CGFloat = 177
    private static let controlsTop: CGFloat = 406
    /// Every list starts the same distance under its headline.
    private static let listGap: CGFloat = 36
    private static let welcomeMarkHeight: CGFloat = 350
    /// The headline and footer wait for most of the cast, not all of it.
    private static let welcomeCastBeat = 0.8

    private var panel: CommandPanelState { state.panel }
    private var permissions: PermissionHealthState { state.permissions }
    private var hotkey: FoundryHotkey { panel.settings.hotkey }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RadialGradient(colors: [Brand.inkGlow, Brand.ink], center: UnitPoint(x: 0.65, y: 0.45), startRadius: 0, endRadius: 640)

            if state.step == .shortcut || state.step == .tryIt {
                EllipticalGradient(colors: [Brand.accentGlow, .clear])
                    .frame(width: 680, height: 260)
                    .offset(x: 80, y: 230)
                    .opacity(state.step == .tryIt && state.didTryPanel ? 1 : 0)
                    .animation(Brand.Motion.enter, value: state.didTryPanel)
                    .allowsHitTesting(false)
                ChalkKeyboard(modifiers: chord.modifiers, keyCode: chord.keyCode, hot: state.step == .tryIt && state.didTryPanel) { key, lit in
                    keyboard.isPressed(key) || demoKeys.contains(key.id) || (lit && keyboard.flashing)
                }
                    .padding(.top, Self.keyboardTop)
                    .padding(.horizontal, Self.margin)
                    .transition(.opacity)
            }

            if windowSeen || opensImmediately {
                stepContent
                    .id(state.step)
                    .transition(stepTransition)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // The cast plays alone; the footer arrives with the headline.
                Reveal(index: 1, after: reduceMotion ? 0 : (state.step == .welcome ? Self.welcomeCastBeat : 0)) { footer }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                if state.step != .welcome && state.step != .done {
                    Button("Skip setup") { state.abandon() }
                        .buttonStyle(BrandQuietButtonStyle(dim: true))
                        .padding(.top, 30)
                        .padding(.trailing, Self.margin)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .transition(.opacity)
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // The titlebar is transparent; the brand ground runs under it.
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .animation(Brand.Motion.step, value: state.step)
        .onChange(of: windowState, initial: true) { _, state in
            if state == .key { windowSeen = true }
        }
        .onAppear {
            keyboard.onRecord = { [state] recorded in
                if recorded == .commandSpace { state.claimCommandSpace() } else { state.panel.settings.setHotkey(recorded) }
            }
        }
        .onChange(of: panel.presentationToken) { _, _ in
            if state.step == .tryIt, state.didTryPanel == false {
                panelOpenedForTryIt = true
                panel.searchHint = String(localized: "Press \(hotkey.spokenName) again to close")
            }
            keyboard.flash()
        }
        .onChange(of: panel.isPanelOpen) { _, isOpen in
            guard isOpen == false else { return }
            panel.searchHint = nil
            guard state.step == .tryIt, panelOpenedForTryIt else { return }
            keyboard.flash()
            state.completeTryIt()
        }
        .onChange(of: state.step) { _, _ in keyboard.isRecording = false }
        .onExitCommand { state.abandon() }
    }

    /// A crossfade; the slight blur makes the two steps read as one change.
    private var stepTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .modifier(active: StepBlur(radius: 4), identity: StepBlur(radius: 0)))
    }

    private var chord: (modifiers: UInt32, keyCode: UInt32?) {
        keyboard.isRecording ? (keyboard.heldModifiers, nil) : (hotkey.modifiers, hotkey.keyCode)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch state.step {
        case .welcome: welcomeStep
        case .shortcut: shortcutStep
        case .tryIt: tryItStep
        case .preferences: preferencesStep
        case .permissions: permissionsStep
        case .ai: aiStep
        case .done: doneStep
        }
    }

    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(.horizontal, Self.margin)
            .padding(.top, Self.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Welcome

    private var welcomeStep: some View {
        ZStack(alignment: .bottomLeading) {
            CastMark()
                .frame(height: Self.welcomeMarkHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            Reveal(index: 0, after: reduceMotion ? 0 : Self.welcomeCastBeat) {
                BrandHeadline(lines: ["Welcome", "to Foundry"],
                              lead: "Everything on your Mac, one keystroke away.",
                              large: true)
            }
        }
        .padding(.horizontal, Self.margin)
        .padding(.top, 72)
        // The lead's baseline sits on the mark's base; its descenders hang below.
        .padding(.bottom, Self.size.height - 72 - Self.welcomeMarkHeight - 5)
    }

    // MARK: Shortcut

    private var shortcutStep: some View {
        page {
            Reveal(index: 0) {
                BrandHeadline(lines: ["One keystroke opens everything"],
                              lead: "From any app, right over whatever you’re doing.")
            }
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 20) {
                Reveal(index: 1) { shortcutControls }
                Spacer(minLength: 0)
                Reveal(index: 2) { takeoverStatus }
                    .padding(.top, 10)
            }
            .frame(height: Self.size.height - Self.controlsTop, alignment: .top)
        }
        .onAppear {
            if hotkey == .commandSpace && state.didClaimCommandSpace == false { state.claimCommandSpace() }
        }
    }

    private var shortcutControls: some View {
        HStack(spacing: 20) {
            ShortcutField(recording: keyboard.isRecording,
                          keys: keyboard.isRecording ? heldKeys : hotkeyKeys) { keyboard.isRecording.toggle() }

            if hotkey != .commandSpace && keyboard.isRecording == false {
                Button("Use ⌘ Space instead") { state.claimCommandSpace() }
                    .buttonStyle(BrandQuietButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var takeoverStatus: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if panel.settings.launcherHotkeyFailed {
                StatusLine(kind: .problem, text: "\(hotkey.spokenName) is taken by another app. Record a different shortcut.")
            }
            if state.didClaimSpotlight {
                if state.spotlightHoldsCommandSpace {
                    HStack(spacing: 14) {
                        StatusLine(kind: .problem, text: "Spotlight still has ⌘ Space.")
                        Button("Open Keyboard Shortcuts") { state.openSpotlightShortcutSettings() }
                            .buttonStyle(BrandQuietButtonStyle())
                    }
                } else if state.isWaitingForSpotlight {
                    StatusLine(kind: .working, text: "Turning off Spotlight’s ⌘ Space")
                } else {
                    StatusLine(kind: .done, text: "Spotlight’s ⌘ Space turned off")
                }
            }
            ForEach(state.takeovers) { takeover in
                switch takeover.status {
                case .working: StatusLine(kind: .working, text: "Moving \(takeover.name) to ⌥ Space")
                case .done: StatusLine(kind: .done, text: "\(takeover.name) moved to ⌥ Space")
                case .failed: StatusLine(kind: .problem, text: "Couldn’t change \(takeover.name). Change its hotkey in \(takeover.name) settings.")
                }
            }
        }
        .animation(Brand.Motion.state, value: state.takeovers)
    }

    // MARK: Try it

    private var tryItStep: some View {
        page {
            Group {
                if state.didTryPanel {
                    BrandHeadline(lines: ["That’s the whole idea"], lead: "Open it from anywhere. Close it the same way.")
                } else if panelOpenedForTryIt {
                    BrandHeadline(lines: ["Now press it again"], lead: "The same keys close it. So does Esc.")
                } else {
                    BrandHeadline(lines: ["Now press it"], lead: "The panel opens right over this window.")
                }
            }
            .id(state.didTryPanel ? 2 : (panelOpenedForTryIt ? 1 : 0))
            .transition(.opacity)
            .animation(Brand.Motion.step, value: panelOpenedForTryIt)
            .animation(Brand.Motion.step, value: state.didTryPanel)

            Spacer(minLength: 0)
                .task { await demonstratePress() }
            Group {
                if panelOpenedForTryIt == false && state.didTryPanel == false {
                    Reveal(index: 1, after: 0.6) {
                        Button { state.go(to: .shortcut) } label: {
                            Text("Nothing happened?") + Text(" ") + Text("Choose another shortcut").foregroundStyle(Brand.text)
                        }
                        .buttonStyle(BrandQuietButtonStyle())
                    }
                    .padding(.top, 11)
                }
            }
            .frame(height: Self.size.height - Self.controlsTop, alignment: .top)
        }
    }

    /// Presses the chord on the keycaps, key by key, until the user does it for real.
    private func demonstratePress() async {
        guard reduceMotion == false else { return }
        while panelOpenedForTryIt == false, state.step == .tryIt {
            do {
                try await Task.sleep(for: .seconds(1.4))
                for key in BoardKey.macBook.joined() where key.isLit(modifiers: chord.modifiers, keyCode: chord.keyCode) {
                    demoKeys.insert(key.id)
                    try await Task.sleep(for: .milliseconds(140))
                }
                try await Task.sleep(for: .milliseconds(320))
                demoKeys.removeAll()
                try await Task.sleep(for: .seconds(1.6))
            } catch {
                demoKeys.removeAll()
                return
            }
        }
        demoKeys.removeAll()
    }

    // MARK: Preferences

    private var preferencesStep: some View {
        page {
            Reveal(index: 0) {
                BrandHeadline(lines: ["Make it yours"], lead: "Change any of these later in Settings.")
            }
            Reveal(index: 1) {
                BrandList {
                    toggleRow("Launch at login",
                              detail: panel.settings.launchAtLoginAvailable
                                  ? panel.settings.launchAtLoginError ?? String(localized: "Ready the moment you sign in.")
                                  : String(localized: "Available in the installed Foundry app."),
                              isOn: Binding(get: { panel.settings.launchAtLoginEnabled }, set: { panel.settings.setLaunchAtLogin($0) }))
                        .disabled(panel.settings.launchAtLoginAvailable == false)
                    BrandDivider()
                    toggleRow("Menu bar icon", detail: String(localized: "Quick access to the panel and your clipboard."),
                              isOn: Binding(get: { state.menuBarIconOn }, set: { state.setMenuBarIcon($0) }))
                    BrandDivider()
                    toggleRow("Clipboard history", detail: String(localized: "Kept only on this Mac. Items apps mark private are never saved."),
                              isOn: Binding(get: { state.clipboardCaptureOn }, set: { state.setClipboardCapture($0) }))
                    BrandDivider()
                    toggleRow("Clipboard shortcut", detail: String(localized: "Chrome and Slack also use it, to paste without formatting."),
                              keys: ["⇧", "⌘", "V"],
                              isOn: Binding(get: { clipboardHotkeyIsSet }, set: { setClipboardHotkey($0) }))
                }
            }
            .padding(.top, Self.listGap)
        }
    }

    private func toggleRow(_ title: LocalizedStringKey, detail: String, keys: [String] = [], isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 16) {
                BrandRowText(title: title, detail: detail)
                if keys.isEmpty == false { kbdChord(keys) }
            }
        }
            .toggleStyle(BrandToggleStyle())
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
    }

    // MARK: Permissions

    private var permissionsStep: some View {
        page {
            Reveal(index: 0) {
                BrandHeadline(lines: ["Grant only what you use"], lead: "Foundry works without these. Each one unlocks a few commands.")
            }
            Reveal(index: 1) {
                BrandList {
                    ForEach(Array(PermissionKind.allCases.enumerated()), id: \.element) { index, kind in
                        if index > 0 { BrandDivider() }
                        HStack(spacing: 16) {
                            BrandRowText(title: LocalizedStringKey(kind.title), detail: kind.purpose)
                            permissionStatus(kind)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    }
                }
            }
            .padding(.top, Self.listGap)
        }
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
    }

    @ViewBuilder
    private func permissionStatus(_ kind: PermissionKind) -> some View {
        switch permissions.status(for: kind) {
        case .granted:
            StatusLine(kind: .done, text: "Allowed")
        case .notGranted:
            Button("Allow…") { permissions.request(kind) }
                .buttonStyle(BrandSecondaryButtonStyle())
        case let status:
            Text(status.label)
                .font(Brand.rowDetail)
                .foregroundStyle(Brand.muted)
        }
    }

    // MARK: AI

    private var aiStep: some View {
        page {
            Reveal(index: 0) {
                BrandHeadline(lines: ["Choose your AI"], lead: "Press Tab in Foundry to ask. Change it any time in Settings.")
            }
            Reveal(index: 1) {
                BrandList {
                    aiRow(.appleIntelligence, "Apple Intelligence",
                          detail: OnboardingState.appleIntelligenceAvailable
                              ? String(localized: "Runs on this Mac. Nothing leaves it.")
                              : String(localized: "Not available on this Mac yet."),
                          enabled: OnboardingState.appleIntelligenceAvailable)
                    BrandDivider()
                    aiRow(.localModel, "Local model",
                          detail: state.detectedLocalKind.map { String(localized: "\($0.displayName) is running on this Mac.") }
                              ?? String(localized: "Start Ollama or LM Studio to use one."),
                          enabled: state.detectedLocalKind != nil)
                    BrandDivider()
                    aiRow(.later, "Cloud provider", detail: String(localized: "Add an API key in Settings when you’re ready."))
                    BrandDivider()
                    aiRow(.off, "No AI", detail: String(localized: "Foundry stays a launcher."))
                }
                .animation(Brand.Motion.state, value: selectedAI)
            }
            .padding(.top, Self.listGap)
        }
        .onAppear { state.refreshLocalModelDetection() }
    }

    private var recommendedAI: OnboardingState.AIChoice {
        if OnboardingState.appleIntelligenceAvailable { return .appleIntelligence }
        return state.detectedLocalKind == nil ? .later : .localModel
    }

    private var selectedAI: OnboardingState.AIChoice { aiSelection ?? recommendedAI }

    private func aiRow(_ choice: OnboardingState.AIChoice, _ title: LocalizedStringKey, detail: String,
                       enabled: Bool = true) -> some View {
        let selected = selectedAI == choice
        return Button { aiSelection = choice } label: {
            HStack(spacing: 16) {
                BrandRowText(title: title, detail: detail)
                BrandSelectionMark(selected: selected)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(selected ? Brand.rowSelected : .clear)
        }
        .buttonStyle(BrandRowButtonStyle())
        .disabled(enabled == false)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Done

    private var doneStep: some View {
        page {
            Reveal(index: 0) {
                BrandHeadline(lines: ["You’re set"], lead: "The keys worth remembering.")
            }
            Reveal(index: 1) {
                BrandList {
                    cheatRow(hotkeyKeys, "Open from anywhere")
                    BrandDivider()
                    if panel.settings.commandPreference(for: "foundry.ai").isEnabled {
                        cheatRow(["Tab"], "Ask AI")
                        BrandDivider()
                    }
                    cheatRow(["⌘", "K"], "Actions on a result")
                    BrandDivider()
                    cheatRow(["⌘", ","], "Settings")
                }
            }
            .padding(.top, Self.listGap)
        }
    }

    private var hotkeyKeys: [String] {
        HotkeyFormatter.modifierString(hotkey.modifiers).map(String.init) + [HotkeyFormatter.keyName(hotkey.keyCode) ?? "?"]
    }

    private var heldKeys: [String] {
        HotkeyFormatter.modifierString(keyboard.heldModifiers).map(String.init)
    }

    private func cheatRow(_ keys: [String], _ label: LocalizedStringKey) -> some View {
        HStack {
            Text(label)
                .font(Brand.rowTitle)
                .tracking(Brand.bodyTracking)
                .foregroundStyle(Brand.text)
            Spacer()
            kbdChord(keys)
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    private func kbdChord(_ keys: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(keys.indices, id: \.self) { BrandKbd(key: keys[$0]) }
        }
    }

    private var clipboardHotkeyIsSet: Bool {
        panel.settings.commandPreferences["foundry.clipboard-history"]?.globalHotkey != nil
    }

    private func setClipboardHotkey(_ on: Bool) {
        let keyCode = UInt32(kVK_ANSI_V), modifiers = UInt32(cmdKey | shiftKey)
        var chord: FoundryHotkey?
        if on, panel.settings.commandHotkeyOwner(keyCode: keyCode, modifiers: modifiers, excluding: "foundry.clipboard-history") == nil {
            chord = FoundryHotkey(keyCode: keyCode, modifiers: modifiers,
                                  displayName: HotkeyFormatter.displayName(keyCode: keyCode, modifiers: modifiers))
        }
        panel.settings.setCommandHotkey(chord, for: "foundry.clipboard-history")
    }

    // MARK: Footer

    /// The same geometry on every step: progress left, Back and the one
    /// primary action right.
    private var footer: some View {
        HStack(spacing: 24) {
            ProgressTiles(current: state.step.rawValue, count: OnboardingStep.allCases.count)
            Spacer()
            if state.canGoBack {
                Button("Back") { state.back() }
                    .buttonStyle(BrandQuietButtonStyle())
                    .keyboardShortcut(.leftArrow, modifiers: [])
            }
            Button(primaryTitle) {
                if state.step == .ai { state.chooseAI(selectedAI) } else { state.advance() }
            }
            .buttonStyle(BrandPrimaryButtonStyle(ready: awaitingTry == false))
            .keyboardShortcut(awaitingTry ? nil : .defaultAction)
        }
        .padding(.horizontal, Self.margin)
        .padding(.bottom, 36)
    }

    /// Try it asks for the shortcut; Continue waits quietly until it works.
    private var awaitingTry: Bool { state.step == .tryIt && state.didTryPanel == false }

    private var primaryTitle: LocalizedStringKey {
        switch state.step {
        case .welcome: "Get started"
        case .done: "Open Foundry"
        default: "Continue"
        }
    }
}

private extension FoundryHotkey {
    /// "⌘ Space", the way people say it, for running text.
    var spokenName: String {
        HotkeyFormatter.modifierString(modifiers) + " " + (HotkeyFormatter.keyName(keyCode) ?? "?")
    }
}

private struct RecordingDot: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Brand.accent)
            .frame(width: 8, height: 8)
            .phaseAnimator(active && reduceMotion == false ? [1, 0.25] : [1]) { dot, opacity in
                dot.opacity(opacity)
            } animation: { _ in FoundryTheme.Motion.pulse }
    }
}

private struct StatusLine: View {
    enum Kind { case done, working, problem }
    let kind: Kind
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 8) {
            switch kind {
            case .done:
                Image(systemName: "checkmark").foregroundStyle(Brand.accent)
            case .working:
                ProgressView().controlSize(.mini)
            case .problem:
                Image(systemName: "exclamationmark.triangle").foregroundStyle(FoundryTheme.warning)
            }
            Text(text).foregroundStyle(kind == .problem ? Brand.text : Brand.muted)
        }
        .font(Brand.rowDetail)
        .frame(height: 20)
    }
}

/// The launcher chord as one field, recorded in place the way Raycast does it.
private struct ShortcutField: View {
    let recording: Bool
    let keys: [String]
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text("Shortcut")
                    .foregroundStyle(Brand.muted)
                HStack(spacing: 4) {
                    ForEach(keys.indices, id: \.self) { BrandKbd(key: keys[$0]) }
                    if recording {
                        HStack(spacing: 8) {
                            RecordingDot(active: true)
                            Text(keys.isEmpty ? "Press the new shortcut" : "Now a key")
                        }
                        .padding(.leading, keys.isEmpty ? 0 : 6)
                        .foregroundStyle(Brand.text)
                    }
                }
                Text(recording ? "Cancel" : "Change")
                    .foregroundStyle(hovering ? Brand.text : Brand.muted)
                    .padding(.horizontal, 8)
            }
            .font(Brand.quiet)
            .tracking(Brand.bodyTracking)
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(height: 40)
            .background(BrandRowSurface(radius: 8, lifted: hovering))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Brand.accent, lineWidth: 1)
                    .opacity(recording ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Brand.Motion.state, value: recording)
        .accessibilityLabel(recording ? Text("Recording a new shortcut") : Text("Shortcut \(keys.joined(separator: " "))"))
        .accessibilityHint("Records a new shortcut")
    }
}

private struct StepBlur: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}
