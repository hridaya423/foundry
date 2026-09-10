import AppKit
import Carbon
import SwiftUI
import FoundryDomain

struct WidgetSettingsView: View {
    @ObservedObject var state: CommandPanelState
    @State private var category: SettingsCategory = .general

    var body: some View {
        HStack(spacing: 0) {
            settingsRail
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 1)
            detailPane
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private var settingsRail: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsCategory.allCases) { item in
                Button {
                    category = item
                    if item == .commands {
                        state.prepareCommandCatalog()
                    } else if item == .agents {
                        state.agents.refreshIntegrationStatuses()
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18)
                        Text(item.title)
                            .font(FoundryTheme.body(size: 13, weight: .medium))
                    }
                    .foregroundStyle(category == item ? FoundryTheme.primaryText : FoundryTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.primary.opacity(category == item ? 0.07 : 0))
                    )
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(category == item ? .isSelected : [])
            }

            Spacer()
        }
        .frame(width: 148, alignment: .leading)
        .padding(.top, 8)
        .padding(.trailing, 8)
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = state.configLoadError {
                SettingsNotice(
                    text: "Foundry could not load its settings. Editing is disabled until they are reset. \(error)",
                    symbol: "exclamationmark.triangle",
                    actionTitle: "Reset",
                    action: state.resetConfiguration
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }

            if let error = state.settingsPersistenceError {
                SettingsNotice(text: error, symbol: "exclamationmark.triangle")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch category {
                    case .general:
                        generalContent
                    case .commands:
                        commandsContent
                    case .agents:
                        agentsContent
                    case .appearance:
                        appearanceContent
                    case .ai:
                        aiContent
                    case .widgets:
                        widgetsContent
                    case .clipboard:
                        clipboardContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 12) {
                            SettingsLabel(title: "Global shortcut", subtitle: "Open Foundry from anywhere")
                            Spacer()
                            ShortcutRecorder(hotkey: state.hotkey, onChange: state.setHotkey)
                                .frame(width: 120, height: 30)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    if let error = state.hotkeyError {
                        Text(error)
                            .font(FoundryTheme.body(size: 12, weight: .medium))
                            .foregroundStyle(FoundryTheme.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    }
                }
            }

            SettingsGroup {
                HStack(spacing: 12) {
                    SettingsLabel(title: "Search sensitivity", subtitle: state.searchSensitivity.subtitle)
                    Spacer()
                    Picker("Search sensitivity", selection: Binding(
                        get: { state.searchSensitivity },
                        set: { state.setSearchSensitivity($0) }
                    )) {
                        ForEach(SearchSensitivity.allCases) { sensitivity in
                            Text(sensitivity.title).tag(sensitivity)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 110)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            }

            snippetExpansionContent
        }
    }

    private var snippetExpansionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(title: "Snippet expansion", value: state.accessibilityTrusted ? "Accessibility allowed" : "Accessibility required")
            SettingsGroup {
                SettingsToggleRow(
                    title: "Expand keywords as you type",
                    subtitle: "Only runs when Accessibility access is already granted",
                    isOn: state.snippetExpansion.isEnabled,
                    set: state.setSnippetExpansionEnabled
                )
                SettingsDivider()
                HStack(spacing: 8) {
                    SettingsLabel(title: "Accessibility", subtitle: state.accessibilityTrusted ? "Ready" : "Not granted")
                    Spacer()
                    if !state.accessibilityTrusted {
                        Button("Request access") { state.requestSnippetExpansionAccessibility() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Button("Privacy Settings") { state.openSnippetExpansionPrivacySettings() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                SettingsDivider()
                ConfigFieldRow(
                    title: "Excluded apps",
                    placeholder: "com.example.app, com.other.app",
                    initialValue: state.snippetExpansion.excludedBundleIdentifiers.joined(separator: ", "),
                    commit: state.setSnippetExpansionExcludedBundleIdentifiers
                )
            }
            if let error = state.snippetExpansionError {
                SettingsNotice(text: error, symbol: "exclamationmark.triangle")
            }
        }
    }

    private var appearanceContent: some View {
        SettingsGroup {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SettingsLabel(
                        title: "Panel contrast",
                        subtitle: "Increase separation from content behind Foundry"
                    )
                    Spacer()
                    Text("\(Int(state.themeIntensity * 100))%")
                        .font(FoundryTheme.body(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                }

                Slider(
                    value: Binding(
                        get: { state.themeIntensity },
                        set: { value in state.setThemeIntensity(value) }
                    ),
                    in: 0.2...1
                )
                .tint(FoundryTheme.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
    }

    private var commandsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(
                title: "Commands",
                value: state.commandCatalogCount == 0 ? nil : "\(state.visibleCommandRows.count)/\(state.commandCatalogCount)"
            )

            if state.commandCatalogFailures.isEmpty == false {
                SettingsNotice(
                    text: "Some command providers could not be loaded: \(state.commandCatalogFailures.joined(separator: "; "))",
                    symbol: "exclamationmark.triangle",
                    actionTitle: "Retry",
                    action: state.retryCommandCatalog
                )
            }

            SettingsGroup {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.mutedText)
                    TextField("Search commands", text: $state.commandSettingsQuery)
                        .textFieldStyle(.plain)
                        .font(FoundryTheme.body(size: 13, weight: .medium))
                        .foregroundStyle(FoundryTheme.primaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            if state.isCommandCatalogLoading && state.commandCatalogCount == 0 {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing command catalog…")
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 5)
            } else if state.isCommandCatalogReady && state.commandCatalogCount == 0 {
                Text("No commands are available.")
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 5)
            } else if state.visibleCommandRows.isEmpty {
                Text("No commands match this search.")
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 5)
            } else {
                SettingsGroup {
                    LazyVStack(spacing: 0) {
                        ForEach(state.visibleCommandRows) { row in
                            CommandSettingsRow(
                                row: row,
                                isExpanded: state.expandedCommandID == row.id,
                                 setEnabled: { state.setCommandEnabled($0, for: row.id) },
                                 setFavorite: { state.setCommandFavorite($0, for: row.id) },
                                 commitAliases: { state.setCommandAliases($0, for: row.id) },
                                 setHotkey: { state.setCommandHotkey($0, for: row.id) },
                                 setFallbackEligible: { state.setCommandFallbackEligible($0, for: row.id) },
                                 reset: { state.resetCommandPreference(for: row.id) },
                                toggleExpanded: { state.toggleCommandExpansion(row.id) }
                            )
                            .overlay(alignment: .bottom) {
                                if row.id != state.visibleCommandRows.last?.id {
                                    SettingsDivider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var aiContent: some View {
        AISettingsSection(state: state.aiSettings)
    }

    private var agentsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(title: "Observation", value: state.agents.socketListening ? "Listening" : "Unavailable")
            SettingsGroup {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: state.agents.socketListening ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(state.agents.socketListening ? FoundryTheme.success : FoundryTheme.warning)
                        SettingsLabel(
                            title: "Agent event socket",
                            subtitle: "Provider hooks and plugins can send observation events here"
                        )
                        Spacer()
                        Text(state.agents.socketListening ? "Live" : "Offline")
                            .font(FoundryTheme.body(size: 12, weight: .semibold))
                            .foregroundStyle(state.agents.socketListening ? FoundryTheme.success : FoundryTheme.warning)
                    }
                    Text(AgentEventSocketServer.socketURL.path)
                        .font(FoundryTheme.mono(size: 10, weight: .regular))
                        .foregroundStyle(FoundryTheme.faintText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Foundry observes provider-owned sessions. Approvals and replies remain native-only until a provider response channel is installed.")
                        .font(FoundryTheme.body(size: 11, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }

            if let integrationError = state.agents.integrationError {
                SettingsNotice(text: integrationError, symbol: "exclamationmark.triangle")
            }

            SettingsSectionLabel(title: "Provider bridges")
            SettingsGroup {
                ForEach(AgentBridgeProvider.allCases, id: \.self) { provider in
                    AgentIntegrationRow(
                        provider: provider,
                        status: state.agents.integrationStatus(for: provider),
                        install: { state.agents.installIntegration(for: provider) }
                    )
                    if provider != AgentBridgeProvider.allCases.last {
                        SettingsDivider()
                    }
                }
            }

            SettingsSectionLabel(title: "Tracked sessions", value: "\(state.agents.sessions.count)")
            SettingsGroup {
                if state.agents.sessions.isEmpty {
                    Text("No current or recent provider sessions.")
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(state.agents.sessions.prefix(6)) { session in
                            HStack(spacing: 9) {
                                Image(systemName: session.provider.symbol)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(FoundryTheme.secondaryText)
                                    .frame(width: 22)
                                SettingsLabel(title: session.title, subtitle: "\(session.provider.rawValue) · \(session.status.rawValue)")
                                Spacer()
                                Text(session.origin.rawValue)
                                    .font(FoundryTheme.body(size: 10, weight: .medium))
                                    .foregroundStyle(FoundryTheme.faintText)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                        }
                    }
                }
            }
        }
    }

    private var widgetsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(title: "Home strip", value: "\(state.widgetBoard.config.enabled.count)/\(WidgetBoardConfig.maxEnabled)")
            SettingsGroup {
                if state.widgetBoard.config.enabled.isEmpty {
                        Text("No Home widgets yet. Add one below.")
                        .font(FoundryTheme.body(size: 13, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .padding(.vertical, 5)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(state.widgetBoard.config.enabled.enumerated()), id: \.element) { index, kind in
                            ActiveWidgetRow(
                                kind: kind,
                                isFirst: index == 0,
                                isLast: index == state.widgetBoard.config.enabled.count - 1,
                                moveUp: { state.widgetBoard.moveUp(kind) },
                                moveDown: { state.widgetBoard.moveDown(kind) },
                                remove: { state.widgetBoard.remove(kind) }
                            )
                            if index < state.widgetBoard.config.enabled.count - 1 {
                                SettingsDivider()
                            }
                        }
                    }
                }
            }

            if state.widgetBoard.config.enabled.contains(.weather) || state.widgetBoard.config.enabled.contains(.stock) {
                SettingsSectionLabel(title: "Widget options")
                SettingsGroup {
                    if state.widgetBoard.config.enabled.contains(.weather) {
                        ConfigFieldRow(
                            title: "Weather city",
                            placeholder: "City name",
                            initialValue: state.widgetBoard.config.weatherCity,
                            commit: state.widgetBoard.setWeatherCity
                        )
                        if state.widgetBoard.config.enabled.contains(.stock) {
                            SettingsDivider()
                        }
                    }
                    if state.widgetBoard.config.enabled.contains(.stock) {
                        ConfigFieldRow(
                            title: "Stock ticker",
                            placeholder: "e.g. AAPL",
                            initialValue: state.widgetBoard.config.stockSymbol,
                            commit: state.widgetBoard.setStockSymbol
                        )
                    }
                }
            }

            SettingsSectionLabel(title: "Available widgets")
            if state.widgetBoard.isFull {
                Text("Remove a widget to add another.")
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 5)
            } else if state.widgetBoard.config.available.isEmpty {
                Text("All available widgets are already on Home.")
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 5)
            } else {
                SettingsGroup {
                    ForEach(state.widgetBoard.config.available) { kind in
                        AvailableWidgetRow(kind: kind, add: { state.widgetBoard.add(kind) })
                    }
                }
            }
        }
    }

    private var clipboardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(title: "Clipboard history")
            SettingsGroup {
                SettingsToggleRow(title: "Pause capture", subtitle: "Keep existing items but stop recording new copies", isOn: state.clipboardHistory.isPaused, set: state.setClipboardPaused)
                SettingsDivider()
                HStack {
                    SettingsLabel(title: "Retain items", subtitle: "Maximum number of entries")
                    Spacer()
                    Stepper(value: Binding(get: { state.clipboardHistory.policy.maxItems }, set: { state.setClipboardRetention(maxItems: $0, maxBytes: state.clipboardHistory.policy.maxBytes) }), in: 1...ClipboardConfig.maximumMaxItems) { Text("\(state.clipboardHistory.policy.maxItems)") }
                }.padding(.horizontal, 12).padding(.vertical, 10)
                SettingsDivider()
                ConfigFieldRow(title: "Excluded apps", placeholder: "com.example.app, com.other.app", initialValue: state.clipboardHistory.excludedBundleIdentifiers.joined(separator: ", "), commit: state.setClipboardExcludedBundleIdentifiers)
            }
            if let error = state.clipboardHistory.error {
                SettingsNotice(text: "Clipboard history could not be saved: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
            }
        }
    }
}

private struct AgentIntegrationRow: View {
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

private struct AISettingsSection: View {
    @ObservedObject var state: AISettingsState

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
                        .foregroundStyle(status.contains("failed") || status.contains("Could") || status.contains("unavailable") ? FoundryTheme.error : FoundryTheme.mutedText)
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

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case commands
    case agents
    case appearance
    case ai
    case widgets
    case clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .commands: "Commands"
        case .agents: "Agents"
        case .appearance: "Appearance"
        case .ai: "AI"
        case .widgets: "Home"
        case .clipboard: "Clipboard"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .commands: "command"
        case .agents: "sparkles.rectangle.stack"
        case .appearance: "circle.lefthalf.filled"
        case .ai: "sparkles"
        case .widgets: "house"
        case .clipboard: "doc.on.clipboard"
        }
    }

}

private struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(.horizontal, 2)
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.primary.opacity(0.045), lineWidth: 1)
            )
    }
}

private struct SettingsSectionLabel: View {
    let title: String
    let value: String?

    init(title: String, value: String? = nil) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack {
            Text(title)
                .font(FoundryTheme.body(size: 13, weight: .semibold))
                .foregroundStyle(FoundryTheme.primaryText.opacity(0.78))
            Spacer()
            if let value {
                Text(value)
                    .font(FoundryTheme.body(size: 12, weight: .medium))
                    .foregroundStyle(FoundryTheme.mutedText)
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
            .padding(.horizontal, 12)
    }
}

private struct SettingsLabel: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(FoundryTheme.body(size: 14, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)
            Text(subtitle)
                .font(FoundryTheme.body(size: 12, weight: .regular))
                .foregroundStyle(FoundryTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let isOn: Bool
    let set: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            SettingsLabel(title: title, subtitle: subtitle)
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { value in set(value) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
                .accessibilityValue(isOn ? "On" : "Off")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

private struct SettingsNotice: View {
    let text: String
    let symbol: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 9) {
            Label(text, systemImage: symbol)
                .font(FoundryTheme.body(size: 12, weight: .medium))
                .foregroundStyle(FoundryTheme.error)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(FoundryTheme.body(size: 11, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .pointerCursor()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(FoundryTheme.error.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct SettingsTextFieldRow: View {
    let title: String
    let placeholder: String
    let value: String
    let error: String?
    let commit: (String) -> Void

    @State private var text: String

    init(title: String, placeholder: String, value: String, error: String?, commit: @escaping (String) -> Void) {
        self.title = title
        self.placeholder = placeholder
        self.value = value
        self.error = error
        self.commit = commit
        _text = State(initialValue: value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(title)
                    .font(FoundryTheme.body(size: 13, weight: .medium))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .frame(width: 72, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .font(FoundryTheme.body(size: 14, weight: .medium))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .onSubmit { commit(text) }
                }
                Spacer()
            }
            if let error {
                Text(error)
                    .font(FoundryTheme.body(size: 11, weight: .medium))
                    .foregroundStyle(FoundryTheme.error)
                    .padding(.leading, 44)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .onAppear { text = value }
        .onChange(of: value) { _, newValue in text = newValue }
    }
}

private struct SettingsSecureFieldRow: View {
    let title: String
    let placeholder: String
    @Binding var value: String
    let commit: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(FoundryTheme.body(size: 13, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)
                .frame(width: 72, alignment: .leading)
            SecureField(placeholder, text: $value)
                .textFieldStyle(.plain)
                .font(FoundryTheme.body(size: 14, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)
                .onSubmit { commit(value) }
            Button("Save") {
                commit(value)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let hotkey: FoundryHotkey
    var placeholder: String? = nil
    let onChange: (FoundryHotkey) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.onHotkey = context.coordinator.record
        view.hotkey = hotkey
        view.placeholder = placeholder
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.hotkey = hotkey
        view.placeholder = placeholder
        view.onHotkey = context.coordinator.record
    }

    final class Coordinator {
        let onChange: (FoundryHotkey) -> Void

        init(onChange: @escaping (FoundryHotkey) -> Void) { self.onChange = onChange }

        func record(_ hotkey: FoundryHotkey) { onChange(hotkey) }
    }
}

private final class ShortcutRecorderView: NSView {
    var hotkey = FoundryHotkey.commandSpace { didSet { needsDisplay = true } }
    var placeholder: String? { didSet { needsDisplay = true } }
    var onHotkey: ((FoundryHotkey) -> Void)?
    private var isRecording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let background = isRecording ? NSColor.labelColor.withAlphaComponent(0.14) : NSColor.labelColor.withAlphaComponent(0.08)
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()

        let text = isRecording ? "Press shortcut…" : (placeholder ?? hotkey.displayName)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(isRecording ? 0.7 : 0.95)
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = carbonModifiers(from: flags)
        guard modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else {
            NSSound.beep()
            return
        }
        guard let keyName = keyName(for: event) else {
            NSSound.beep()
            return
        }

        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        parts.append(keyName)

        isRecording = false
        onHotkey?(FoundryHotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers, displayName: parts.joined()))
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    private func keyName(for event: NSEvent) -> String? {
        let names: [UInt16: String] = [
            UInt16(kVK_Return): "↩",
            UInt16(kVK_Tab): "⇥",
            UInt16(kVK_Space): "Space",
            UInt16(kVK_Delete): "⌫",
            UInt16(kVK_Escape): "Esc",
            UInt16(kVK_LeftArrow): "←",
            UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑",
            UInt16(kVK_DownArrow): "↓"
        ]
        if let name = names[event.keyCode] { return name }
        guard let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines), characters.isEmpty == false else {
            return nil
        }
        return characters.uppercased()
    }
}

private struct ActiveWidgetRow: View {
    let kind: WidgetKind
    let isFirst: Bool
    let isLast: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FoundryTheme.secondaryText)
                .frame(width: 20)
            SettingsLabel(title: kind.title, subtitle: kind.summary)
            Spacer()
            SettingsIconButton(symbol: "chevron.up", label: "Move \(kind.title) up", action: moveUp)
                .disabled(isFirst)
                .opacity(isHovering ? (isFirst ? 0.3 : 1) : 0.12)
            SettingsIconButton(symbol: "chevron.down", label: "Move \(kind.title) down", action: moveDown)
                .disabled(isLast)
                .opacity(isHovering ? (isLast ? 0.3 : 1) : 0.12)
            SettingsIconButton(symbol: "minus", label: "Remove \(kind.title)", action: remove, tint: FoundryTheme.error)
                .opacity(isHovering ? 1 : 0.12)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

private struct AvailableWidgetRow: View {
    let kind: WidgetKind
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            HStack(spacing: 10) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .frame(width: 20)
                SettingsLabel(title: kind.title, subtitle: kind.summary)
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}

private struct SettingsIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var tint: Color = FoundryTheme.secondaryText

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
        .pointerCursor()
    }
}

private struct ConfigFieldRow: View {
    let title: String
    let placeholder: String
    let initialValue: String
    let commit: (String) -> Void
    @State private var text = ""

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(FoundryTheme.body(size: 13, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)
                .frame(width: 112, alignment: .leading)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(FoundryTheme.body(size: 14, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)
                .onSubmit { commit(text) }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .onAppear { text = initialValue }
    }
}

private struct CommandSettingsRow: View {
    let row: CommandSettingsRowModel
    let isExpanded: Bool
    let setEnabled: (Bool) -> Void
    let setFavorite: (Bool) -> Void
    let commitAliases: (String) -> Void
    let setHotkey: (FoundryHotkey?) -> Void
    let setFallbackEligible: (Bool) -> Void
    let reset: () -> Void
    let toggleExpanded: () -> Void

    @State private var aliasesText: String

    init(
        row: CommandSettingsRowModel,
        isExpanded: Bool,
        setEnabled: @escaping (Bool) -> Void,
        setFavorite: @escaping (Bool) -> Void,
        commitAliases: @escaping (String) -> Void,
        setHotkey: @escaping (FoundryHotkey?) -> Void,
        setFallbackEligible: @escaping (Bool) -> Void,
        reset: @escaping () -> Void,
        toggleExpanded: @escaping () -> Void
    ) {
        self.row = row
        self.isExpanded = isExpanded
        self.setEnabled = setEnabled
        self.setFavorite = setFavorite
        self.commitAliases = commitAliases
        self.setHotkey = setHotkey
        self.setFallbackEligible = setFallbackEligible
        self.reset = reset
        self.toggleExpanded = toggleExpanded
        _aliasesText = State(initialValue: row.preference.aliases.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                CommandSettingsIcon(icon: row.icon)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(FoundryTheme.body(size: 14, weight: .semibold))
                        .foregroundStyle(row.preference.isEnabled ? FoundryTheme.primaryText : FoundryTheme.mutedText)
                        .lineLimit(1)
                    Text(row.subtitle)
                        .font(FoundryTheme.body(size: 11, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    setFavorite(row.preference.favoriteRank == nil)
                } label: {
                    Image(systemName: row.preference.favoriteRank == nil ? "star" : "star.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(row.preference.favoriteRank == nil ? FoundryTheme.mutedText : FoundryTheme.accent)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.preference.favoriteRank == nil ? "Favorite \(row.title)" : "Remove \(row.title) from favorites")

                Toggle("", isOn: Binding(get: { row.preference.isEnabled }, set: { value in setEnabled(value) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.82)
                    .accessibilityLabel("Enable \(row.title)")

                Button {
                    if isExpanded {
                        commitAliases(aliasesText)
                    }
                    toggleExpanded()
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Hide settings for \(row.title)" : "Show settings for \(row.title)")
            }

            if isExpanded {
                HStack(spacing: 8) {
                    Text("Aliases")
                        .font(FoundryTheme.body(size: 11, weight: .medium))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .frame(width: 48, alignment: .leading)
                    TextField("comma separated", text: $aliasesText)
                        .textFieldStyle(.plain)
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .onSubmit { commitAliases(aliasesText) }
                    Spacer()
                    if row.preference.aliases.isEmpty == false || row.preference.favoriteRank != nil || row.preference.isEnabled == false || row.preference.globalHotkey != nil || row.preference.fallbackEligible == false {
                        Button("Reset") { reset() }
                            .buttonStyle(.plain)
                            .font(FoundryTheme.body(size: 11, weight: .medium))
                            .foregroundStyle(FoundryTheme.mutedText)
                    }
                }

                HStack(spacing: 8) {
                    Text("Hotkey")
                        .font(FoundryTheme.body(size: 11, weight: .medium))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .frame(width: 48, alignment: .leading)
                    ShortcutRecorder(
                        hotkey: row.preference.globalHotkey.map {
                            FoundryHotkey(keyCode: $0.keyCode, modifiers: $0.modifiers, displayName: $0.displayName)
                        } ?? FoundryHotkey(keyCode: 0, modifiers: 0, displayName: "Set shortcut"),
                        placeholder: row.preference.globalHotkey == nil ? "Set shortcut" : nil,
                        onChange: { setHotkey($0) }
                    )
                    .frame(width: 132, height: 28)
                    if row.preference.globalHotkey != nil {
                        Button("Clear") { setHotkey(nil) }
                            .buttonStyle(.plain)
                            .font(FoundryTheme.body(size: 11, weight: .medium))
                            .foregroundStyle(FoundryTheme.mutedText)
                    }
                    Spacer()
                }

                Toggle("Use as fallback result", isOn: Binding(
                    get: { row.preference.fallbackEligible },
                    set: { setFallbackEligible($0) }
                ))
                .toggleStyle(.switch)
                .font(FoundryTheme.body(size: 11, weight: .medium))
                .foregroundStyle(FoundryTheme.mutedText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .onChange(of: row.preference.aliases) { _, newValue in
            aliasesText = newValue.joined(separator: ", ")
        }
        .onChange(of: isExpanded) { wasExpanded, nowExpanded in
            if wasExpanded && !nowExpanded {
                commitAliases(aliasesText)
            }
        }
    }
}

private struct CommandSettingsIcon: View {
    let icon: CommandIcon
    @State private var appImage: NSImage?

    var body: some View {
        Group {
            if let appImage {
                Image(nsImage: appImage)
                    .resizable()
                    .scaledToFit()
            } else if let systemName = icon.systemName {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
            } else {
                Text(icon.fallback)
                    .font(FoundryTheme.body(size: 10, weight: .bold))
                    .foregroundStyle(FoundryTheme.secondaryText)
            }
        }
        .frame(width: 28, height: 28)
        .task(id: icon.filePath) {
            guard let filePath = icon.filePath else { return }
            appImage = await CommandIconRepository.shared.image(for: filePath)
        }
    }
}
