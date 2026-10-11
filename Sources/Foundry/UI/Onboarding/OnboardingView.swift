import AppKit
import Carbon
import FoundryDomain
import SwiftUI

struct OnboardingView: View {
    var state: OnboardingState
    private var panel: CommandPanelState
    private var permissions: PermissionHealthState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var panelOpenedForTryIt = false
    @State private var clipboardHotkeyOn = false

    init(state: OnboardingState) {
        self.state = state
        self.panel = state.panel
        self.permissions = state.permissions
    }

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(state.step)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 24)).combined(with: .scale(scale: 0.98)),
                    removal: .opacity.combined(with: .offset(x: -24)).combined(with: .scale(scale: 1.02))
                ))

            footer
        }
        .background(FoundryBackdrop(intensity: 0.72, isOpaque: false))
        .onChange(of: panel.presentationToken) { _, _ in
            if state.step == .tryIt { panelOpenedForTryIt = true }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.9), value: state.step)
        .onAppear {
            clipboardHotkeyOn = clipboardHotkeyIsSet
        }
        .onExitCommand {
            state.finish()
        }
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

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()
            OnboardingReveal(index: 0) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .shadow(color: FoundryTheme.brand.opacity(FoundryTheme.Alpha.half), radius: 26, y: 8)
            }
            OnboardingReveal(index: 1) {
                Text("Everything on your Mac, one keystroke away.")
                    .font(FoundryTheme.Glyph.lg)
                    .foregroundStyle(FoundryTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            OnboardingReveal(index: 2) {
                Text("Launch apps, run commands, and ask AI from a single panel.")
                    .font(FoundryTheme.bodySecondary)
                    .foregroundStyle(FoundryTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 48)
    }

    private var shortcutStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(panel.settings.hotkey.displayName)
                .font(FoundryTheme.title)
                .foregroundStyle(FoundryTheme.textPrimary)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(FoundryTheme.fillTint)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(FoundryTheme.fillEmphasis, lineWidth: 1)
                )

            Text("Press it anywhere to open Foundry.")
                .font(FoundryTheme.bodySecondary)
                .foregroundStyle(FoundryTheme.textSecondary)

            ShortcutRecorder(hotkey: panel.settings.hotkey, placeholder: "Record a different shortcut", onChange: { hotkey in
                if hotkey == .commandSpace { state.useCommandSpace() } else { panel.settings.setHotkey(hotkey) }
            })
                .frame(width: 260, height: 30)

            Button("Use ⌘Space instead") {
                state.useCommandSpace()
            }
            .buttonStyle(FoundryQuietButtonStyle())
            .font(FoundryTheme.body)
            .foregroundStyle(FoundryTheme.accent)

            if state.spotlightHoldsCommandSpace {
                VStack(alignment: .leading, spacing: 8) {
                    Text("⌘Space is still held by Spotlight:")
                        .font(FoundryTheme.body)
                        .foregroundStyle(FoundryTheme.warning)
                    Text("1. Open Keyboard Shortcuts\n2. Turn off “Show Spotlight search”")
                        .font(FoundryTheme.bodySecondary)
                        .foregroundStyle(FoundryTheme.textSecondary)
                    Button("Open Keyboard Shortcuts") {
                        state.openSpotlightShortcutSettings()
                    }
                    .buttonStyle(FoundryQuietButtonStyle())
                    .font(FoundryTheme.body)
                    .foregroundStyle(FoundryTheme.textPrimary)
                }
                .padding(14)
                .frame(maxWidth: 360, alignment: .leading)
                .background(FoundryTheme.fillHover)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if state.isWaitingForSpotlight {
                Label("Turning off Spotlight's ⌘Space shortcut…", systemImage: "clock")
                    .font(FoundryTheme.bodySecondary)
                    .foregroundStyle(FoundryTheme.textTertiary)
            }

            if panel.settings.launcherHotkeyFailed {
                InlineNotice(
                    level: .error,
                    text: "\(panel.settings.hotkey.displayName) is in use by another app. Record a different shortcut above."
                )
                .frame(maxWidth: 400)
            }
            Spacer()
        }
        .padding(.horizontal, 48)
    }

    private var tryItStep: some View {
        VStack(spacing: 18) {
            Spacer()
            if state.didTryPanel {
                Image(systemName: "checkmark.circle.fill")
                    .font(FoundryTheme.Glyph.hero)
                    .foregroundStyle(FoundryTheme.success)
                    .symbolEffect(.bounce, options: .nonRepeating, value: state.didTryPanel)
                Text("That’s the whole idea.")
                    .font(FoundryTheme.Glyph.lg)
                    .foregroundStyle(FoundryTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if panelOpenedForTryIt {
                Image(systemName: "text.cursor")
                    .font(FoundryTheme.Glyph.xl)
                    .foregroundStyle(FoundryTheme.accent)
                Text("Type an app name, press Return")
                    .font(FoundryTheme.Glyph.lg)
                    .foregroundStyle(FoundryTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Foundry runs your top hit instantly.")
                    .font(FoundryTheme.bodySecondary)
                    .foregroundStyle(FoundryTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                OnboardingReveal(index: 0) {
                    PulsingKeycap(text: panel.settings.hotkey.displayName)
                }
                OnboardingReveal(index: 1) {
                    Text("Press it now")
                        .font(FoundryTheme.title)
                        .foregroundStyle(FoundryTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                OnboardingReveal(index: 2) {
                    Text("The panel opens right over this window.")
                        .font(FoundryTheme.bodySecondary)
                        .foregroundStyle(FoundryTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 48)
        .overlay(ConfettiBurst(trigger: tryItConfetti))
        .onChange(of: state.didTryPanel) { _, tried in
            if tried { tryItConfetti &+= 1 }
        }
    }

    @State private var tryItConfetti = 0

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            Text("Make it yours")
                .font(FoundryTheme.title)
                .foregroundStyle(FoundryTheme.textPrimary)
                .frame(maxWidth: .infinity)

            OnboardingToggle(
                title: "Launch at login",
                detail: panel.settings.launchAtLoginError ?? "Foundry is ready the moment you sign in.",
                isOn: Binding(get: { panel.settings.launchAtLoginEnabled }, set: { panel.settings.setLaunchAtLogin($0) }),
                onChange: nil
            )
            .disabled(panel.settings.launchAtLoginAvailable == false)
            OnboardingToggle(
                title: "Show in menu bar",
                detail: "Quick access to the panel and clipboard.",
                isOn: Binding(get: { state.menuBarIconOn }, set: { state.setMenuBarIcon($0) }),
                onChange: nil
            )
            OnboardingToggle(
                title: "Clipboard history",
                detail: "Stored only on this Mac. Items password managers mark private are never saved.",
                isOn: Binding(get: { state.clipboardCaptureOn }, set: { state.setClipboardCapture($0) }),
                onChange: nil
            )
            Spacer()
        }
        .padding(.horizontal, 56)
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            Text("Superpowers, only if you want them")
                .font(FoundryTheme.title)
                .foregroundStyle(FoundryTheme.textPrimary)
                .frame(maxWidth: .infinity)

            ForEach(PermissionKind.allCases) { kind in
                HStack(spacing: 12) {
                    Image(systemName: kind.symbol)
                        .font(FoundryTheme.Glyph.sm)
                        .foregroundStyle(FoundryTheme.textSecondary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                            .font(FoundryTheme.body)
                            .foregroundStyle(FoundryTheme.textPrimary)
                        Text(kind.purpose)
                            .font(FoundryTheme.caption)
                            .foregroundStyle(FoundryTheme.textTertiary)
                            .lineLimit(2)
                    }
                    Spacer()
                    let status = permissions.status(for: kind)
                    if status == .granted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .font(FoundryTheme.micro)
                            .foregroundStyle(FoundryTheme.success)
                    } else if status == .notGranted {
                        Button("Grant") { permissions.request(kind) }
                            .buttonStyle(FoundryQuietButtonStyle())
                            .font(FoundryTheme.body)
                            .foregroundStyle(FoundryTheme.accent)
                    } else {
                        Text(status.label)
                            .font(FoundryTheme.caption)
                            .foregroundStyle(FoundryTheme.textTertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .onboardingCard()
            }
            Spacer()
        }
        .padding(.horizontal, 56)
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
    }

    private var aiStep: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("AI, your way")
                .font(FoundryTheme.title)
                .foregroundStyle(FoundryTheme.textPrimary)
                .frame(maxWidth: .infinity)

            aiChoiceButton(
                title: "Use Apple Intelligence",
                detail: OnboardingState.appleIntelligenceAvailable
                    ? "Runs on-device. Nothing leaves this Mac."
                    : "Not available on this Mac yet.",
                enabled: OnboardingState.appleIntelligenceAvailable
            ) { state.chooseAI(.appleIntelligence) }

            aiChoiceButton(
                title: "Use a local model",
                detail: state.detectedLocalKind.map { "\($0.displayName) detected on this Mac." }
                    ?? "No Ollama or LM Studio found. You can set one up later.",
                enabled: state.detectedLocalKind != nil
            ) { state.chooseAI(.localModel) }

            aiChoiceButton(
                title: "Add an API key later",
                detail: "Skip for now. You can set up AI later in Settings.",
                enabled: true
            ) { state.chooseAI(.later) }

            Button("Turn AI off") { state.chooseAI(.off) }
                .buttonStyle(FoundryQuietButtonStyle())
                .font(FoundryTheme.bodySecondary)
                .foregroundStyle(FoundryTheme.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 56)
        .onAppear { state.refreshLocalModelDetection() }
    }

    private func aiChoiceButton(title: String, detail: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(FoundryTheme.body)
                        .foregroundStyle(enabled ? FoundryTheme.textPrimary : FoundryTheme.textQuaternary)
                    Text(detail)
                        .font(FoundryTheme.caption)
                        .foregroundStyle(FoundryTheme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(FoundryTheme.Glyph.xs)
                    .foregroundStyle(FoundryTheme.textQuaternary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .onboardingCard()
        }
        .buttonStyle(FoundryQuietButtonStyle())
        .opacity(enabled ? 1 : 0.55)
        .disabled(enabled == false)
    }

    private var clipboardHotkeyIsSet: Bool {
        panel.settings.commandPreferences["foundry.clipboard-history"]?.globalHotkey != nil
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("You’re set")
                .font(FoundryTheme.title)
                .foregroundStyle(FoundryTheme.textPrimary)

            VStack(spacing: 0) {
                cheatRow(panel.settings.hotkey.displayName, "Open Foundry")
                cheatRow("Tab", "Ask AI")
                cheatRow("⌘K", "Actions on a result")
                cheatRow("⌘,", "Settings")
            }
            .onboardingCard()
            .frame(maxWidth: 400)

            Toggle(isOn: $clipboardHotkeyOn) {
                Text("⇧⌘V opens Clipboard History")
                    .font(FoundryTheme.body)
                    .foregroundStyle(FoundryTheme.textPrimary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: clipboardHotkeyOn) { _, on in
                var hotkey: FoundryHotkey?
                if on,
                   panel.settings.commandHotkeyOwner(
                       keyCode: UInt32(kVK_ANSI_V),
                       modifiers: UInt32(cmdKey | shiftKey),
                       excluding: "foundry.clipboard-history"
                   ) == nil {
                    hotkey = FoundryHotkey(
                        keyCode: UInt32(kVK_ANSI_V),
                        modifiers: UInt32(cmdKey | shiftKey),
                        displayName: HotkeyFormatter.displayName(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey))
                    )
                }
                panel.settings.setCommandHotkey(hotkey, for: "foundry.clipboard-history")
            }
            .frame(maxWidth: 400)
            Spacer()
        }
        .padding(.horizontal, 48)
        .overlay(ConfettiBurst(trigger: doneConfetti))
        .onAppear { doneConfetti &+= 1 }
    }

    @State private var doneConfetti = 0

    private func cheatRow(_ keys: String, _ label: String) -> some View {
        HStack {
            Text(label)
                .font(FoundryTheme.body)
                .foregroundStyle(FoundryTheme.textSecondary)
            Spacer()
            KeycapHint(text: keys)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            ForEach(Array(OnboardingStep.allCases.enumerated()), id: \.offset) { index, step in
                Capsule()
                    .fill(step == state.step ? FoundryTheme.accent : FoundryTheme.stroke)
                    .frame(width: step == state.step ? 20 : 6, height: 6)
                    .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.72), value: state.step)
                    .accessibilityLabel("Step \(index + 1) of \(OnboardingStep.allCases.count)\(step == state.step ? ", current" : "")")
            }

            Spacer()

            if state.step != .welcome && state.step != .done {
                Button("Skip") { state.finish() }
                    .buttonStyle(FoundryQuietButtonStyle())
                    .font(FoundryTheme.bodySecondary)
                    .foregroundStyle(FoundryTheme.textTertiary)
                    .keyboardShortcut(.cancelAction)
            }

            if state.canGoBack {
                Button {
                    state.back()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(FoundryTheme.Glyph.sm)
                }
                .buttonStyle(FoundryQuietButtonStyle())
                .foregroundStyle(FoundryTheme.textSecondary)
                .accessibilityLabel("Back")
                .keyboardShortcut(.leftArrow, modifiers: [])
            }

            Button(primaryButtonTitle) {
                state.advance()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .frame(height: 54)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FoundryTheme.fillTint)
                .frame(height: 1)
        }
    }

    private var primaryButtonTitle: String {
        switch state.step {
        case .welcome: "Get Started"
        case .done: "Open Foundry"
        case .ai, .permissions: "Continue"
        default: "Continue"
        }
    }
}

private struct OnboardingToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var onChange: ((Bool) -> Void)?

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { newValue in
            if let onChange { onChange(newValue) } else { isOn = newValue }
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FoundryTheme.body)
                    .foregroundStyle(FoundryTheme.textPrimary)
                Text(detail)
                    .font(FoundryTheme.caption)
                    .foregroundStyle(FoundryTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onboardingCard()
    }
}

private extension View {
    func onboardingCard() -> some View {
        FoundryGlassSurface(role: .contentSurface, shape: RoundedRectangle(cornerRadius: 12, style: .continuous)) { self }
    }
}

private struct OnboardingReveal<Content: View>: View {
    let index: Int
    @ViewBuilder var content: Content
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                guard shown == false else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.42).delay(Double(index) * 0.07)) {
                    shown = true
                }
            }
    }
}

private struct PulsingKeycap: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                keycap
            } else {
                keycap
                    .phaseAnimator([false, true]) { content, pressed in
                        content
                            .scaleEffect(pressed ? 0.94 : 1)
                            .shadow(color: FoundryTheme.accent.opacity(pressed ? 0.05 : 0.5), radius: pressed ? 4 : 22, y: pressed ? 1 : 6)
                    } animation: { pressed in
                        pressed ? .easeIn(duration: 0.18) : .spring(response: 0.5, dampingFraction: 0.55).delay(0.9)
                    }
            }
        }
    }

    private var keycap: some View {
        Text(text)
            .font(FoundryTheme.title)
            .foregroundStyle(FoundryTheme.textPrimary)
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
            .onboardingCard()
    }
}
