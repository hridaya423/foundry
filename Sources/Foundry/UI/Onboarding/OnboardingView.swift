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
    @State private var demoKeys: Set<String> = []
    @State private var launch = OnboardingState.SuggestedLaunch(name: "Safari", prefix: "sa")

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

            if state.step == .shortcut {
                EllipticalGradient(colors: [Brand.accentGlow, .clear])
                    .frame(width: 680, height: 260)
                    .offset(x: 80, y: 230)
                    .opacity(state.didLaunch ? 1 : 0)
                    .animation(Brand.Motion.enter, value: state.didLaunch)
                    .allowsHitTesting(false)
                ChalkKeyboard(modifiers: chord.modifiers, keyCode: chord.keyCode, hot: state.didLaunch) { key, lit in
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
                if state.step != .welcome && state.step != .done && awaitingLaunch == false {
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
            keyboard.onCommandSpace = { [state] in state.commandSpaceReachedWindow() }
        }
        .onChange(of: panel.presentationToken) { _, _ in
            if state.step == .shortcut, state.didLaunch == false {
                panel.searchHint = String(localized: "Type \(launch.prefix) and press Return")
            }
            keyboard.flash()
        }
        .onChange(of: panel.isPanelOpen) { _, isOpen in
            guard isOpen == false else { return }
            panel.searchHint = nil
            state.panelClosedWithoutLaunch()
        }
        .onChange(of: state.step) { _, step in
            keyboard.isRecording = false
            announce(Self.spokenTitle(for: step, receipt: state.receipt))
        }
        .onChange(of: state.didLaunch) { _, launched in
            if launched { announce(String(localized: "That’s the whole idea. \(launch.name) opened.")) }
        }
        .onExitCommand { state.abandon() }
    }

    static func spokenTitle(for step: OnboardingStep, receipt: [String]) -> String {
        switch step {
        case .welcome: String(localized: "Welcome to Foundry")
        case .shortcut: String(localized: "One keystroke opens everything")
        case .bringYourStuff: String(localized: "Bring your snippets")
        case .done: receipt.joined(separator: ". ")
        }
    }

    private func announce(_ message: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
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
        case .bringYourStuff: bringYourStuffStep
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
            Group {
                if state.didLaunch {
                    BrandHeadline(lines: ["That’s the whole idea"],
                                  lead: "\(launch.name) opened. \(hotkey.spokenName) works from any app.")
                } else if state.openedWithoutLaunch {
                    BrandHeadline(lines: ["Now open something"], lead: "Press \(hotkey.spokenName), type \(launch.prefix), and press Return.")
                } else {
                    BrandHeadline(lines: ["One keystroke opens everything"],
                                  lead: "Press \(hotkey.spokenName), type \(launch.prefix), and press Return to open \(launch.name).")
                }
            }
            .id(state.didLaunch ? 2 : (state.openedWithoutLaunch ? 1 : 0))
            .transition(.opacity)
            .animation(Brand.Motion.step, value: state.openedWithoutLaunch)
            .animation(Brand.Motion.step, value: state.didLaunch)
            Spacer(minLength: 0)
                .task { await demonstratePress() }
            HStack(alignment: .top, spacing: 20) {
                Reveal(index: 1) { shortcutControls }
                Spacer(minLength: 0)
                Reveal(index: 2) { shortcutStatus }
                    .padding(.top, 10)
            }
            .frame(height: Self.size.height - Self.controlsTop, alignment: .top)
        }
        .onAppear {
            launch = OnboardingState.suggestedLaunchOnThisMac()
            state.detectCommandSpaceHolders()
            state.refreshLocalModelDetection()
        }
    }

    private var shortcutControls: some View {
        ShortcutField(recording: keyboard.isRecording,
                      keys: keyboard.isRecording ? heldKeys : hotkeyKeys) { keyboard.isRecording.toggle() }
    }

    private var needsConsent: Bool {
        hotkey == .commandSpace && state.didClaimCommandSpace == false && state.commandSpaceHolders.isEmpty == false
    }

    @ViewBuilder
    private var shortcutStatus: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if needsConsent {
                let holders = state.commandSpaceHolders.formatted(.list(type: .and))
                StatusLine(kind: .problem, text: state.commandSpaceHolders.count == 1 ? "\(holders) uses ⌘ Space." : "\(holders) use ⌘ Space.")
                HStack(spacing: 14) {
                    Button("Use ⌥ Space") { state.useOptionSpace() }
                        .buttonStyle(BrandQuietButtonStyle())
                    Button("Take ⌘ Space") { state.claimCommandSpace() }
                        .buttonStyle(BrandSecondaryButtonStyle())
                }
            } else if state.commandSpaceUnreachable && hotkey == .commandSpace {
                StatusLine(kind: .problem, text: "Another app has ⌘ Space.")
                HStack(spacing: 14) {
                    Button("Record Your Own") { keyboard.isRecording = true }
                        .buttonStyle(BrandQuietButtonStyle())
                    Button("Use ⌥ Space") { state.useOptionSpace() }
                        .buttonStyle(BrandSecondaryButtonStyle())
                }
            } else if panel.settings.launcherHotkeyFailed {
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
        .animation(Brand.Motion.state, value: needsConsent)
    }

    /// Presses the chord on the keycaps once, and again only after the user sits idle.
    private func demonstratePress() async {
        guard reduceMotion == false else { return }
        var delay: Duration = .seconds(1.4)
        while state.didLaunch == false, state.openedWithoutLaunch == false, state.step == .shortcut {
            do {
                try await Task.sleep(for: delay)
                for key in BoardKey.macBook.joined() where key.isLit(modifiers: chord.modifiers, keyCode: chord.keyCode) {
                    demoKeys.insert(key.id)
                    try await Task.sleep(for: .milliseconds(140))
                }
                try await Task.sleep(for: .milliseconds(320))
                demoKeys.removeAll()
                delay = .seconds(6)
            } catch {
                demoKeys.removeAll()
                return
            }
        }
        demoKeys.removeAll()
    }

    // MARK: Bring your stuff

    private var bringYourStuffStep: some View {
        page {
            Reveal(index: 0) {
                BrandHeadline(lines: ["Bring your snippets"], lead: "Foundry reads what you already saved. Nothing in the other app changes.")
            }
            Reveal(index: 1) {
                BrandList {
                    ForEach(Array(state.importSources.enumerated()), id: \.element.id) { index, source in
                        if index > 0 { BrandDivider() }
                        importRow(source)
                    }
                }
            }
            .padding(.top, Self.listGap)
        }
    }

    private func importRow(_ source: ImportSource) -> some View {
        HStack(spacing: 16) {
            switch source.kind {
            case .alfred:
                BrandRowText(title: "Alfred", detail: String(localized: "\(source.available ?? 0) snippets"))
            case .raycast:
                BrandRowText(title: "Raycast", detail: String(localized: "Export snippets from Raycast, then choose the file."))
            }
            if let imported = source.imported {
                StatusLine(kind: .done, text: "\(imported) imported")
            } else {
                Button(source.kind == .alfred ? "Import" : "Choose File…") { importSnippets(from: source.kind) }
                    .buttonStyle(BrandSecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func importSnippets(from kind: ImportSource.Kind) {
        guard kind == .raycast else { return state.importSnippets(from: kind) }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.importSnippets(from: .raycast, file: url)
    }

    // MARK: Done

    private var doneStep: some View {
        let receipt = state.receipt
        return page {
            Reveal(index: 0) {
                BrandHeadline(lines: [LocalizedStringKey(receipt.first ?? "")])
            }
            Reveal(index: 1) {
                BrandList {
                    ForEach(receipt.dropFirst(), id: \.self) { line in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark").foregroundStyle(Brand.accent)
                            Text(line).font(Brand.rowTitle).tracking(Brand.bodyTracking).foregroundStyle(Brand.text)
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 52)
                        .accessibilityElement(children: .combine)
                        BrandDivider()
                    }
                    Toggle(isOn: Binding(get: { state.startsAtLogin }, set: { state.startsAtLogin = $0 })) {
                        BrandRowText(title: "Starts when you log in", detail: String(localized: "So the shortcut works after a restart."))
                    }
                    .toggleStyle(BrandToggleStyle())
                    .disabled(panel.settings.launchAtLoginAvailable == false)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    BrandDivider()
                    BrandRowText(title: "Foundry lives in the menu bar", detail: String(localized: "Its icon opens the panel and Settings."))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
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
            if awaitingLaunch {
                Button("Skip") { state.advance() }
                    .buttonStyle(BrandQuietButtonStyle(dim: true))
            } else {
                Button(primaryTitle) { state.advance() }
                    .buttonStyle(BrandPrimaryButtonStyle(ready: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, Self.margin)
        .padding(.bottom, 36)
    }

    /// The shortcut step's primary appears once a launch works.
    private var awaitingLaunch: Bool { state.step == .shortcut && state.didLaunch == false }

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
