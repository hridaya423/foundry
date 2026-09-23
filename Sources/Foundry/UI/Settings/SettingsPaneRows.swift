import AppKit
import Carbon
import SwiftUI

struct AgentIntegrationRow: View {
    let provider: AgentBridgeProvider
    let status: AgentIntegrationStatus
    let install: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: provider.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FoundryTheme.secondaryText)
                .frame(width: 22)
            SettingsLabel(title: provider.title, subtitle: status.detail ?? status.path.path)
            Spacer()
            if status.installed {
                Text("Installed")
                    .font(FoundryTheme.body(size: 11, weight: .semibold))
                    .foregroundStyle(FoundryTheme.success)
            } else {
                Button("Install", action: install)
                    .buttonStyle(.plain)
                    .font(FoundryTheme.body(size: 11, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .pointerCursor()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }
}

struct AISettingsSection: View {
    @Bindable var state: AISettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = state.settingsPersistenceError {
                SettingsNotice(text: error, symbol: "exclamationmark.triangle")
            }

            HStack(spacing: 8) {
                SettingsSectionLabel(title: "Provider profiles", value: "\(state.aiProfiles.count)")
                Menu {
                    ForEach(AIProviderPreset.all) { preset in
                        Button(preset.name) {
                            state.addAIProfile(presetID: preset.id)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .foregroundStyle(FoundryTheme.secondaryText)
                .help("Add provider")
            }

            SettingsGroup {
                VStack(spacing: 0) {
                    ForEach(state.aiProfiles) { profile in
                        Button {
                            state.selectAIProfile(profile.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: profile.kind == .appleFoundationModels ? "apple.logo" : "network")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(profile.enabled ? FoundryTheme.secondaryText : FoundryTheme.faintText)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name)
                                        .font(FoundryTheme.body(size: 13, weight: .medium))
                                        .foregroundStyle(FoundryTheme.primaryText)
                                    Text("\(profile.kind.displayName) · \(profile.model)")
                                        .font(FoundryTheme.body(size: 11, weight: .regular))
                                        .foregroundStyle(FoundryTheme.mutedText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if state.defaultAIProfileID == profile.id {
                                    Text("Default")
                                        .font(FoundryTheme.body(size: 11, weight: .semibold))
                                        .foregroundStyle(FoundryTheme.success)
                                } else if state.fallbackAIProfileIDs.contains(profile.id) {
                                    Text("Fallback")
                                        .font(FoundryTheme.body(size: 11, weight: .medium))
                                        .foregroundStyle(FoundryTheme.mutedText)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.primary.opacity(state.selectedAIProfileID == profile.id ? 0.07 : 0))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            if profile.id != state.aiProfiles.last?.id { SettingsDivider() }
                        }
                    }
                }
            }

            if let profile = state.selectedAIProfile {
                SettingsGroup {
                    SettingsToggleRow(
                        title: "Enabled",
                        subtitle: "Allow Foundry to route requests to this profile",
                        isOn: profile.enabled,
                        set: { state.setAIProfileEnabled($0, id: profile.id) }
                    )
                    SettingsDivider()
                    HStack(spacing: 10) {
                        SettingsLabel(title: "Default", subtitle: "Use this profile for new AI chats")
                        Spacer()
                        Button(state.defaultAIProfileID == profile.id ? "Selected" : "Use by default") {
                            state.setDefaultAIProfile(profile.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    SettingsDivider()
                    SettingsToggleRow(
                        title: "Fallback",
                        subtitle: "Try this profile after temporary provider failures",
                        isOn: state.fallbackAIProfileIDs.contains(profile.id),
                        set: { state.setAIFallback($0, id: profile.id) }
                    )
                    if profile.kind != .appleFoundationModels {
                        SettingsDivider()
                        SettingsTextFieldRow(
                            title: "Name",
                            placeholder: profile.kind.displayName,
                            value: profile.name,
                            error: nil,
                            commit: { state.setAIProfileName($0, id: profile.id) }
                        )
                        SettingsDivider()
                        if profile.kind != .openAISubscription {
                            SettingsDivider()
                            SettingsTextFieldRow(
                                title: "Endpoint",
                                placeholder: "https://api.example.com/v1",
                                value: profile.endpoint ?? "",
                                error: nil,
                                commit: { state.setAIProfileEndpoint($0, id: profile.id) }
                            )
                        }
                    }
                    SettingsDivider()
                    SettingsTextFieldRow(
                        title: "Model",
                        placeholder: "Model name",
                        value: profile.model,
                        error: nil,
                        commit: { state.setAIProfileModel($0, id: profile.id) }
                    )
                    if profile.capabilities.modelDiscovery {
                        SettingsDivider()
                        HStack(spacing: 10) {
                            SettingsLabel(
                                title: "Models",
                                subtitle: profile.kind == .openAISubscription ? "Choose a model available through ChatGPT" : "Discover models from this endpoint"
                            )
                            Spacer()
                            if profile.kind != .openAISubscription {
                                Button {
                                    state.refreshAIModels()
                                } label: {
                                    if state.aiModelsLoading {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Text("Refresh")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            if state.aiAvailableModels.isEmpty == false {
                                Menu {
                                    ForEach(state.aiAvailableModels) { model in
                                        Button(model.displayName) {
                                            state.setAIProfileModel(model.id, id: profile.id)
                                        }
                                    }
                                } label: {
                                    Text("Choose")
                                }
                                .menuStyle(.borderlessButton)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    if profile.authentication == .apiKey || profile.authentication == .optionalAPIKey {
                        SettingsDivider()
                        SettingsSecureFieldRow(
                            title: "API key",
                            placeholder: state.aiProfileHasCredential(profile) ? "Keychain credential stored" : "Paste API key",
                            value: $state.aiCredentialInput,
                            commit: { state.setAIProfileAPIKey($0, id: profile.id) }
                        )
                    } else if profile.authentication == .oauth {
                        SettingsDivider()
                        VStack(alignment: .leading, spacing: 10) {
                            SettingsLabel(title: "ChatGPT subscription", subtitle: "Uses the private Codex backend with OAuth PKCE")
                            Text("This integration may change or stop working without notice. Foundry stores OAuth credentials only in macOS Keychain and does not use browser cookies.")
                                .font(FoundryTheme.body(size: 11, weight: .regular))
                                .foregroundStyle(FoundryTheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                            SettingsToggleRow(
                                title: "Private backend warning",
                                subtitle: "I understand this is an experimental integration",
                                isOn: state.acceptedCodexPrivateBackendWarning,
                                set: state.setCodexPrivateBackendWarningAccepted
                            )
                            if state.acceptedCodexPrivateBackendWarning {
                                if state.aiProfileHasCredential(profile) || state.codexLoginState == .connected {
                                    HStack(spacing: 10) {
                                        Label("Connected", systemImage: "checkmark.circle.fill")
                                            .font(FoundryTheme.body(size: 12, weight: .semibold))
                                            .foregroundStyle(FoundryTheme.success)
                                        Spacer()
                                        Button("Sign out") { state.logoutCodex() }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                    }
                                } else {
                                    HStack(spacing: 8) {
                                        Button("Sign in with ChatGPT") { state.loginCodexBrowser() }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                        Button("Use device code") { state.requestCodexDeviceLogin() }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                    }
                                }
                                if let device = state.codexDeviceAuthorization {
                                    Text("Open \(device.verificationURL) and enter \(device.userCode).")
                                        .font(FoundryTheme.mono(size: 10, weight: .regular))
                                        .foregroundStyle(FoundryTheme.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                    HStack(spacing: 8) {
                                        Button("Finish device login") { state.completeCodexDeviceLogin() }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                        Button("Cancel") { state.cancelCodexLogin() }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                    }
                    SettingsDivider()
                    HStack(spacing: 10) {
                        SettingsLabel(title: "Connection", subtitle: profile.kind.requiresNetwork ? "Test endpoint and credentials" : "Runs on this Mac")
                        Spacer()
                        Button {
                            state.testSelectedAIProfile()
                        } label: {
                            if state.aiProfileTestingID == profile.id {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Test")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }

                if let status = state.aiProfileStatus {
                    Text(status)
                        .font(FoundryTheme.body(size: 11, weight: .regular))
                        .foregroundStyle(state.aiProfileStatusIsError ? FoundryTheme.error : FoundryTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)
                }

                if profile.kind != .appleFoundationModels {
                    Button("Remove profile", role: .destructive) {
                        state.removeSelectedAIProfile()
                    }
                    .buttonStyle(.borderless)
                    .font(FoundryTheme.body(size: 12, weight: .medium))
                }
            }
        }
    }
}
