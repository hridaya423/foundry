import AppKit
import Carbon
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
                    insertion: .opacity.combined(with: .offset(x: 24)),
                    removal: .opacity.combined(with: .offset(x: -24))
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
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Everything on your Mac, one keystroke away.")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(FoundryTheme.primaryText)
                .multilineTextAlignment(.center)
            Text("Launch apps, run commands, and ask AI from a single panel.")
                .font(FoundryTheme.body(size: 13, weight: .regular))
                .foregroundStyle(FoundryTheme.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 48)
    }

    private var shortcutStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(panel.hotkey.displayName)
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .foregroundStyle(FoundryTheme.primaryText)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Color.primary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                )

            Text("Press it anywhere to open Foundry.")
                .font(FoundryTheme.body(size: 13, weight: .regular))
                .foregroundStyle(FoundryTheme.secondaryText)

            ShortcutRecorder(hotkey: panel.hotkey, placeholder: "Record a different shortcut", onChange: { hotkey in
                if hotkey == .commandSpace { state.useCommandSpace() } else { panel.setHotkey(hotkey) }
            })
                .frame(width: 260, height: 30)

            Button("Use ⌘Space instead") {
                state.useCommandSpace()
            }
            .buttonStyle(FoundryQuietButtonStyle())
            .font(FoundryTheme.body(size: 12, weight: .semibold))
            .foregroundStyle(FoundryTheme.accentTint)
            .pointerCursor()

            if state.spotlightHoldsCommandSpace {
                VStack(alignment: .leading, spacing: 8) {
                    Text("⌘Space is still held by Spotlight:")
                        .font(FoundryTheme.body(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.warning)
                    Text("1. Open Keyboard Shortcuts\n2. Turn off “Show Spotlight search”")
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.secondaryText)
                    Button("Open Keyboard Shortcuts") {
                        state.openSpotlightShortcutSettings()
                    }
                    .buttonStyle(FoundryQuietButtonStyle())
                    .font(FoundryTheme.body(size: 12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .pointerCursor()
                }
                .padding(14)
                .frame(maxWidth: 360, alignment: .leading)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if state.isWaitingForSpotlight {
                Label("Turning off Spotlight's ⌘Space shortcut…", systemImage: "clock")
                    .font(FoundryTheme.body(size: 12, weight: .medium))
                    .foregroundStyle(FoundryTheme.mutedText)
            }

            if panel.launcherHotkeyFailed {
                InlineNotice(
                    level: .error,
                    text: "\(panel.hotkey.displayName) is in use by another app. Record a different shortcut above."
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
                    .font(.system(size: 44))
                    .foregroundStyle(FoundryTheme.success)
                Text("That’s the whole idea.")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
            } else if panelOpenedForTryIt {
                Image(systemName: "text.cursor")
                    .font(.system(size: 36))
                    .foregroundStyle(FoundryTheme.accentTint)
                Text("Type an app name, press Return")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                Text("Foundry runs your top hit instantly.")
                    .font(FoundryTheme.body(size: 13, weight: .regular))
                    .foregroundStyle(FoundryTheme.secondaryText)
            } else {
                Text("Press \(panel.hotkey.displayName) now")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                Text("The panel opens right over this window.")
                    .font(FoundryTheme.body(size: 13, weight: .regular))
                    .foregroundStyle(FoundryTheme.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 48)
    }

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            Text("Make it yours")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(FoundryTheme.primaryText)
                .frame(maxWidth: .infinity)

            OnboardingToggle(
                title: "Launch at login",
                detail: panel.launchAtLoginError ?? "Foundry is ready the moment you sign in.",
                isOn: Binding(get: { panel.launchAtLoginEnabled }, set: { panel.setLaunchAtLogin($0) }),
                onChange: nil
            )
            .disabled(panel.launchAtLoginAvailable == false)
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
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(FoundryTheme.primaryText)
                .frame(maxWidth: .infinity)

            ForEach(PermissionKind.allCases) { kind in
                HStack(spacing: 12) {
                    Image(systemName: kind.symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                            .font(FoundryTheme.body(size: 13, weight: .semibold))
                            .foregroundStyle(FoundryTheme.primaryText)
                        Text(kind.purpose)
                            .font(FoundryTheme.body(size: 11, weight: .regular))
                            .foregroundStyle(FoundryTheme.mutedText)
                            .lineLimit(2)
                    }
                    Spacer()
                    let status = permissions.status(for: kind)
                    if status == .granted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .font(FoundryTheme.body(size: 11, weight: .semibold))
                            .foregroundStyle(FoundryTheme.success)
                    } else if status == .notGranted {
                        Button("Grant") { permissions.request(kind) }
                            .buttonStyle(FoundryQuietButtonStyle())
                            .font(FoundryTheme.body(size: 12, weight: .semibold))
                            .foregroundStyle(FoundryTheme.accentTint)
                            .pointerCursor()
                    } else {
                        Text(status.label)
                            .font(FoundryTheme.body(size: 11, weight: .medium))
                            .foregroundStyle(FoundryTheme.mutedText)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(FoundryTheme.primaryText)
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
                .font(FoundryTheme.body(size: 12, weight: .medium))
                .foregroundStyle(FoundryTheme.mutedText)
                .pointerCursor()
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
                        .font(FoundryTheme.body(size: 13, weight: .semibold))
                        .foregroundStyle(enabled ? FoundryTheme.primaryText : FoundryTheme.faintText)
                    Text(detail)
                        .font(FoundryTheme.body(size: 11, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.faintText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(enabled ? 0.06 : 0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(FoundryQuietButtonStyle())
        .disabled(enabled == false)
        .pointerCursor()
    }

    private var clipboardHotkeyIsSet: Bool {
        panel.commandPreferences["foundry.clipboard-history"]?.globalHotkey != nil
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("You’re set")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(FoundryTheme.primaryText)

            VStack(spacing: 0) {
                cheatRow(panel.hotkey.displayName, "Open Foundry")
                cheatRow("Tab", "Ask AI")
                cheatRow("⌘K", "Actions on a result")
                cheatRow("⌘,", "Settings")
            }
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: 400)

            Toggle(isOn: $clipboardHotkeyOn) {
                Text("⇧⌘V opens Clipboard History")
                    .font(FoundryTheme.body(size: 13, weight: .medium))
                    .foregroundStyle(FoundryTheme.primaryText)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: clipboardHotkeyOn) { _, on in
                let hotkey: FoundryHotkey? = on
                    ? FoundryHotkey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey), displayName: "⇧⌘V")
                    : nil
                panel.setCommandHotkey(hotkey, for: "foundry.clipboard-history")
            }
            .frame(maxWidth: 400)
            Spacer()
        }
        .padding(.horizontal, 48)
    }

    private func cheatRow(_ keys: String, _ label: String) -> some View {
        HStack {
            Text(label)
                .font(FoundryTheme.body(size: 13, weight: .medium))
                .foregroundStyle(FoundryTheme.secondaryText)
            Spacer()
            KeycapHint(text: keys)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            ForEach(Array(OnboardingStep.allCases.enumerated()), id: \.offset) { index, step in
                Circle()
                    .fill(step == state.step ? FoundryTheme.primaryText : Color.primary.opacity(0.18))
                    .frame(width: 6, height: 6)
                    .scaleEffect(step == state.step ? 1.2 : 1)
            }

            Spacer()

            if state.step != .welcome && state.step != .done {
                Button("Skip") { state.finish() }
                    .buttonStyle(FoundryQuietButtonStyle())
                    .font(FoundryTheme.body(size: 12, weight: .medium))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .pointerCursor()
                    .keyboardShortcut(.cancelAction)
            }

            if state.canGoBack {
                Button {
                    state.back()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(FoundryQuietButtonStyle())
                .foregroundStyle(FoundryTheme.secondaryText)
                .pointerCursor()
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
                .fill(Color.primary.opacity(0.07))
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
                    .font(FoundryTheme.body(size: 13, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                Text(detail)
                    .font(FoundryTheme.body(size: 11, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
