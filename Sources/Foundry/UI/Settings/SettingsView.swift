import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers
import FoundryDomain

struct SettingsView: View {
    @Bindable var state: CommandPanelState
    @State private var category: SettingsCategory = .general
    @State private var searchQuery = ""
    @State private var pendingAnchor: String?
    @State private var highlightedAnchor: String?
    @State private var confirmingReset = false
    @State private var pendingBackup: FoundryBackup?
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            settingsRail
            Divider()
            detailPane
        }
        .onAppear {
            searchFocused = true
            consumePendingCommandReveal()
        }
        .onChange(of: state.pendingSettingsDeepLink) { _, _ in consumePendingCommandReveal() }
    }

    private func consumePendingCommandReveal() {
        guard let deepLink = state.pendingSettingsDeepLink else { return }
        state.pendingSettingsDeepLink = nil
        switch deepLink {
        case .quicklinks:
            category = .quicklinks
            pendingAnchor = "quicklinks.list"
            highlightedAnchor = "quicklinks.list"
        case .scripts:
            category = .scripts
            pendingAnchor = "scripts.folders"
            highlightedAnchor = "scripts.folders"
        case let .command(id):
            category = .commands
            state.settings.prepareCommandCatalog()
            state.settings.commandSettingsQuery = ""
            state.settings.expandedCommandID = id
            pendingAnchor = "commands.\(id)"
            highlightedAnchor = "commands.\(id)"
        }
    }

    private var searchMatches: [SettingItem] {
        SettingsSearch.matches(searchQuery)
    }

    private var settingsRail: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FoundryTheme.mutedText)
                TextField("Search settings", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(FoundryTheme.body(size: 13, weight: .regular))
                    .focused($searchFocused)
                    .onSubmit { if let first = searchMatches.first { reveal(first) } }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
            .padding(.bottom, 10)

            ScrollView {
                if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    ForEach(SettingsCategory.allCases) { item in
                        railButton(title: item.title, symbol: item.symbol, isSelected: category == item) {
                            select(item)
                        }
                    }
                } else if searchMatches.isEmpty {
                    Text("No settings match \u{201C}\(searchQuery)\u{201D}")
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .padding(.horizontal, 9)
                        .padding(.top, 4)
                } else {
                    ForEach(searchMatches) { item in
                        railButton(title: item.title, symbol: item.pane.symbol, isSelected: highlightedAnchor == item.anchorID && category == item.pane) {
                            reveal(item)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .frame(width: 176, alignment: .leading)
        .padding(12)
    }

    private func railButton(title: String, symbol: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(title)
                    .font(FoundryTheme.body(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? FoundryTheme.primaryText : FoundryTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous)
                    .fill(isSelected ? FoundryTheme.selection : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ item: SettingsCategory) {
        category = item
        highlightedAnchor = nil
        if item == .commands {
            state.settings.prepareCommandCatalog()
        } else if item == .agents {
            state.agents.refreshIntegrationStatuses()
        }
    }

    private func reveal(_ item: SettingItem) {
        select(item.pane)
        pendingAnchor = item.anchorID
        highlightedAnchor = item.anchorID
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(category.title)
                .font(FoundryTheme.body(size: 20, weight: .semibold))
                .foregroundStyle(FoundryTheme.primaryText)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)

            if let error = state.settings.configLoadError {
                SettingsNotice(
                    text: "Foundry could not load its settings. Editing is disabled until they are reset. \(error)",
                    symbol: "exclamationmark.triangle",
                    actionTitle: "Reset",
                    action: state.settings.resetConfiguration
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            }

            if let error = state.settings.settingsPersistenceError {
                SettingsNotice(text: error, symbol: "exclamationmark.triangle")
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch category {
                        case .general:
                            generalContent
                        case .appearance:
                            appearanceContent
                        case .commands:
                            commandsContent.id("commands.list")
                        case .quicklinks:
                            QuicklinksSettingsPane().id("quicklinks.list")
                        case .scripts:
                            ScriptsSettingsPane().id("scripts.folders")
                        case .clipboard:
                            clipboardContent.id("clipboard.history")
                        case .ai:
                            aiContent.id("ai.provider")
                        case .agents:
                            agentsContent
                        case .widgets:
                            widgetsContent.id("widgets.strip")
                        case .advanced:
                            advancedContent
                        case .about:
                            aboutContent
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .frame(maxWidth: 720, alignment: .leading)
                }
                .onChange(of: pendingAnchor) { _, anchor in
                    guard let anchor else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(anchor, anchor: .top)
                        pendingAnchor = nil
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func anchor(_ id: String) -> SettingsAnchor {
        SettingsAnchor(id: id, highlighted: highlightedAnchor == id)
    }

    private var advancedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup {
                HStack(spacing: 12) {
                    SettingsLabel(title: "Config folder", subtitle: ConfigService.configURL.deletingLastPathComponent().path)
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([ConfigService.configURL])
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            }
            .modifier(anchor("advanced.config"))

            SettingsGroup {
                HStack(spacing: 12) {
                    SettingsLabel(title: "Backup",
                        subtitle: "Settings, snippets, quicklinks and script folders. Clipboard history and API keys are not included.")
                    Spacer()
                    Button("Export…", action: exportBackup)
                        .controlSize(.small)
                    Button("Import…", action: chooseBackup)
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            }
            .modifier(anchor("advanced.backup"))
            .confirmationDialog("Replace your Foundry settings?", isPresented: Binding(get: { pendingBackup != nil },
                set: { if $0 == false { pendingBackup = nil } })) {
                Button("Import and Quit", role: .destructive) {
                    if let pendingBackup { state.settings.restoreBackup(pendingBackup) }
                }
            } message: {
                Text("Current files are kept next to the originals as .pre-import copies. Foundry quits to apply the backup.")
            }

            SettingsGroup {
                HStack(spacing: 12) {
                    SettingsLabel(title: "Reset settings", subtitle: "Restore every preference to its default and quit Foundry")
                    Spacer()
                    Button("Reset…", role: .destructive) { confirmingReset = true }
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            }
            .modifier(anchor("advanced.reset"))
            .confirmationDialog("Reset all Foundry settings?", isPresented: $confirmingReset) {
                Button("Reset and Quit", role: .destructive, action: state.settings.resetConfiguration)
            } message: {
                Text("Clipboard history and snippets are kept.")
            }
        }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Foundry-\(Date().formatted(.iso8601.year().month().day())).\(FoundryBackup.fileExtension)"
        panel.allowedContentTypes = [UTType(filenameExtension: FoundryBackup.fileExtension) ?? .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.settings.exportBackup(to: url)
    }

    private func chooseBackup() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingBackup = state.settings.loadBackup(from: url)
    }

    private var aboutContent: some View {
        SettingsGroup {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Foundry")
                        .font(FoundryTheme.body(size: 17, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                    Text(Self.versionString)
                        .font(FoundryTheme.body(size: 12, weight: .regular).monospacedDigit())
                        .foregroundStyle(FoundryTheme.mutedText)
                        .textSelection(.enabled)
                }
                Spacer()
            }
            .padding(14)
        }
        .modifier(anchor("about.version"))
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "Development"
        let build = info["CFBundleVersion"] as? String
        return build.map { "Version \(version) (\($0))" } ?? "Version \(version)"
    }

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 12) {
                            SettingsLabel(title: "Global shortcut", subtitle: "Open Foundry from anywhere")
                            Spacer()
                            ShortcutRecorder(hotkey: state.settings.hotkey, onChange: state.settings.setHotkey)
                                .frame(width: 120, height: 30)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    if let error = state.settings.hotkeyError {
                        Text(error)
                            .font(FoundryTheme.body(size: 12, weight: .medium))
                            .foregroundStyle(FoundryTheme.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    }
                }
            }
            .modifier(anchor("general.hotkey"))

            if state.settings.launcherHotkeyFailed {
                SettingsNotice(
                    text: "\(state.settings.hotkey.displayName) could not be registered. Choose another shortcut.",
                    symbol: "exclamationmark.triangle"
                )
            }

            SettingsGroup {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        title: "Show in menu bar",
                        subtitle: "Access Foundry, Clipboard History, and Settings from the menu bar",
                        isOn: state.settings.showMenuBarIcon,
                        set: state.settings.setMenuBarIconVisible
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        title: "Launch at login",
                        subtitle: state.settings.launchAtLoginAvailable ? "Start Foundry automatically when you sign in" : "Available in the " +
                            "installed Foundry app",
                        isOn: state.settings.launchAtLoginEnabled,
                        set: state.settings.setLaunchAtLogin
                    )
                    .disabled(state.settings.launchAtLoginAvailable == false)
                    SettingsDivider()
                    SettingsToggleRow(
                        title: "Haptic feedback",
                        subtitle: "Subtle taps for drops, snippet expansion, and celebrations",
                        isOn: state.settings.hapticsEnabled,
                        set: state.settings.setHapticsEnabled
                    )
                    SettingsDivider()
                    HStack(spacing: 12) {
                        SettingsLabel(title: "Main browser", subtitle: "Used for browser history and open-tab results")
                        Spacer()
                        Picker("Main browser", selection: Binding(
                            get: { state.settings.mainBrowser ?? .safari },
                            set: { state.settings.setMainBrowser($0) }
                        )) {
                            ForEach(state.installedBrowsers, id: \.self) { browser in
                                Text(browser.displayName).tag(browser)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                }
            }
            .modifier(anchor("general.system"))
            if let error = state.settings.launchAtLoginError {
                SettingsNotice(text: error, symbol: "exclamationmark.triangle")
            }

            SettingsGroup {
                HStack(spacing: 12) {
                    SettingsLabel(title: "Pop to root", subtitle: "Reopening within this time restores the last mode")
                    Spacer()
                    Picker("Pop to root", selection: Binding(
                        get: { state.settings.popToRootAfterSeconds },
                        set: { state.settings.setPopToRootAfter($0) }
                    )) {
                        Text("Immediately").tag(0.0)
                        Text("30 seconds").tag(30.0)
                        Text("90 seconds").tag(90.0)
                        Text("5 minutes").tag(300.0)
                        Text("Never").tag(Double.greatestFiniteMagnitude)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 130)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            }
            .modifier(anchor("general.popToRoot"))

            compactModeGroup
                .modifier(anchor("general.compact"))

            SettingsGroup {
                HStack(spacing: 12) {
                    SettingsLabel(title: "Search sensitivity", subtitle: state.settings.searchSensitivity.subtitle)
                    Spacer()
                    Picker("Search sensitivity", selection: Binding(
                        get: { state.settings.searchSensitivity },
                        set: { state.settings.setSearchSensitivity($0) }
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
            .modifier(anchor("general.sensitivity"))

            snippetExpansionContent
                .modifier(anchor("general.snippets"))
        }
    }

    private var snippetExpansionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(title: "Snippet expansion", value: state.accessibilityTrusted ? "Accessibility allowed" : "Accessibility required")
            SettingsGroup {
                SettingsToggleRow(
                    title: "Expand keywords as you type",
                    subtitle: "Only runs when Accessibility access is already granted",
                    isOn: state.settings.snippetExpansion.isEnabled,
                    set: state.settings.setSnippetExpansionEnabled
                )
                SettingsDivider()
                HStack(spacing: 8) {
                    SettingsLabel(title: "Accessibility", subtitle: state.accessibilityTrusted ? "Ready" : "Not granted")
                    Spacer()
                    if !state.accessibilityTrusted {
                        Button("Request access") { state.settings.requestSnippetExpansionAccessibility() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Button("Privacy Settings") { state.settings.openSnippetExpansionPrivacySettings() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                SettingsDivider()
                VStack(alignment: .leading, spacing: 10) {
                    SettingsLabel(title: "Expand after", subtitle: "Keywords expand when one of these is typed")
                    HStack(spacing: 8) {
                        ForEach(snippetDelimiterOptions, id: \.delimiter) { option in
                            Button {
                                state.settings.setSnippetExpansionDelimiter(option.delimiter,
                                    enabled: !state.settings.snippetExpansion.delimiters.contains(option.delimiter))
                            } label: {
                                Text(option.label)
                                    .font(FoundryTheme.body(size: 11.5, weight: .semibold))
                                    .foregroundStyle(state.settings.snippetExpansion.delimiters.contains(
                                        option.delimiter) ? FoundryTheme.primaryText : FoundryTheme.mutedText)
                                    .padding(.horizontal, 11)
                                    .frame(height: 26)
                                    .background(
                                        Capsule()
                                            .fill(state.settings.snippetExpansion.delimiters.contains(
                                                option.delimiter) ? FoundryTheme.accentTint.opacity(0.18) : Color.primary.opacity(0.05))
                                            .overlay(
                                                Capsule()
                                                    .strokeBorder(state.settings.snippetExpansion.delimiters.contains(
                                                        option.delimiter) ? FoundryTheme.accentTint.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(PressableButtonStyle())
                            .pointerCursor()
                            .accessibilityLabel("Expand after \(option.label)")
                            .accessibilityValue(state.settings.snippetExpansion.delimiters.contains(option.delimiter) ? "On" : "Off")
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                SettingsDivider()
                VStack(alignment: .leading, spacing: 10) {
                    SettingsLabel(title: "Return key in search", subtitle: "What Return does on a snippet result")
                    HStack(spacing: 8) {
                        ForEach(snippetPrimaryActionOptions, id: \.insert) { option in
                            Button {
                                state.settings.setSnippetInsertAsPrimary(option.insert)
                            } label: {
                                Text(option.label)
                                    .font(FoundryTheme.body(size: 11.5, weight: .semibold))
                                    .foregroundStyle(state.settings.snippetExpansion.insertAsPrimary
                                        == option.insert ? FoundryTheme.primaryText : FoundryTheme.mutedText)
                                    .padding(.horizontal, 11)
                                    .frame(height: 26)
                                    .background(
                                        Capsule()
                                            .fill(state.settings.snippetExpansion.insertAsPrimary
                                                == option.insert ? FoundryTheme.accentTint.opacity(0.18) : Color.primary.opacity(0.05))
                                            .overlay(
                                                Capsule()
                                                    .strokeBorder(state.settings.snippetExpansion.insertAsPrimary
                                                        == option.insert ? FoundryTheme.accentTint.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(PressableButtonStyle())
                            .pointerCursor()
                            .accessibilityLabel("Return key \(option.label)")
                            .accessibilityValue(state.settings.snippetExpansion.insertAsPrimary == option.insert ? "Selected" : "")
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                SettingsDivider()
                ExcludedAppsRow(
                    title: "Excluded apps",
                    bundleIDs: state.settings.snippetExpansion.excludedBundleIdentifiers,
                    commit: { state.settings.setSnippetExpansionExcludedBundleIdentifiers($0.joined(separator: ", ")) }
                )
            }
            if let error = state.settings.snippetExpansionError {
                SettingsNotice(text: error, symbol: "exclamationmark.triangle")
            }
        }
    }

    private var snippetDelimiterOptions: [(label: String, delimiter: String)] {
        [("Space", " "), ("Return", "\n"), ("Tab", "\t"), ("Quote", "'"), ("Backtick", "`")]
    }

    private var snippetPrimaryActionOptions: [(label: String, insert: Bool)] {
        [("Insert", true), ("Copy", false)]
    }

    private var appearanceContent: some View {
        panelContrastGroup
            .modifier(anchor("appearance.contrast"))
    }

    private var compactModeGroup: some View {
        SettingsGroup {
            SettingsToggleRow(
                title: "Compact panel",
                subtitle: "Show only the search bar until you type",
                isOn: state.settings.windowMode == .compact,
                set: { state.settings.setWindowMode($0 ? .compact : .standard) }
            )
        }
    }

    private var panelContrastGroup: some View {
        SettingsGroup {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SettingsLabel(
                        title: "Panel contrast",
                        subtitle: "Increase separation from content behind Foundry"
                    )
                    Spacer()
                    Text("\(Int(state.settings.themeIntensity * 100))%")
                        .font(FoundryTheme.body(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                }

                Slider(
                    value: Binding(
                        get: { state.settings.themeIntensity },
                        set: { value in state.settings.setThemeIntensity(value) }
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
                value: state.settings.commandCatalogCount == 0 ? nil : "\(state.settings.visibleCommandRows.count)/\(state.settings.commandCatalogCount)"
            )

            if state.settings.commandCatalogFailures.isEmpty == false {
                SettingsNotice(
                    text: "Some commands couldn't load: \(state.settings.commandCatalogFailures.joined(separator: "; "))",
                    symbol: "exclamationmark.triangle",
                    actionTitle: "Retry",
                    action: state.settings.retryCommandCatalog
                )
            }

            SettingsGroup {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.mutedText)
                    TextField("Search commands", text: $state.settings.commandSettingsQuery)
                        .textFieldStyle(.plain)
                        .font(FoundryTheme.body(size: 13, weight: .medium))
                        .foregroundStyle(FoundryTheme.primaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            if state.settings.isCommandCatalogLoading && state.settings.commandCatalogCount == 0 {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing command catalog…")
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 5)
            } else if state.settings.isCommandCatalogReady && state.settings.commandCatalogCount == 0 {
                Text("No commands are available.")
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 5)
            } else if state.settings.visibleCommandRows.isEmpty {
                Text("No commands match this search.")
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 5)
            } else {
                SettingsGroup {
                    LazyVStack(spacing: 0) {
                        ForEach(state.settings.visibleCommandRows) { row in
                            CommandSettingsRow(
                                row: row,
                                isExpanded: state.settings.expandedCommandID == row.id,
                                 setEnabled: { state.settings.setCommandEnabled($0, for: row.id) },
                                 setFavorite: { state.settings.setCommandFavorite($0, for: row.id) },
                                 commitAliases: { state.settings.setCommandAliases($0, for: row.id) },
                                 setHotkey: { state.settings.setCommandHotkey($0, for: row.id) },
                                 setFallbackEligible: { state.settings.setCommandFallbackEligible($0, for: row.id) },
                                 reset: { state.settings.resetCommandPreference(for: row.id) },
                                toggleExpanded: { state.settings.toggleCommandExpansion(row.id) }
                            )
                            .modifier(anchor("commands.\(row.id)"))
                            .overlay(alignment: .bottom) {
                                if row.id != state.settings.visibleCommandRows.last?.id {
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
                .id("agents.socket")
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
                    Text(
                        "Foundry shows sessions from your coding agents. Approvals and replies happen in each agent's own app unless it supports " +
                            "replying from Foundry.")
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
                .id("agents.bridges")
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
                    Text("No active or recent agent sessions.")
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
                ForEach(WidgetCategory.allCases, id: \.self) { category in
                    let kinds = state.widgetBoard.config.available.filter { $0.category == category }
                    if kinds.isEmpty == false {
                        Text(category.title)
                            .font(FoundryTheme.body(size: 11, weight: .semibold))
                            .foregroundStyle(FoundryTheme.mutedText)
                            .padding(.horizontal, 2)
                        SettingsGroup {
                            ForEach(kinds) { kind in
                                AvailableWidgetRow(kind: kind, add: { state.widgetBoard.add(kind) })
                            }
                        }
                    }
                }
            }
        }
    }

    private var clipboardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(title: "Clipboard history")
            SettingsGroup {
                SettingsToggleRow(title: "Pause capture", subtitle: "Keep existing items but stop recording new copies",
                    isOn: state.clipboardHistory.isPaused, set: state.settings.setClipboardPaused)
                SettingsDivider()
                HStack {
                    SettingsLabel(title: "Retain items", subtitle: "Maximum number of entries")
                    Spacer()
                    Stepper(
                        value: Binding(
                            get: { state.clipboardHistory.policy.maxItems },
                            set: {
                                state.settings.setClipboardRetention(
                                    maxItems: $0,
                                    maxBytes: state.clipboardHistory.policy.maxBytes,
                                    maxAgeDays: Int(state.clipboardHistory.policy.maxAge / 86_400)
                                )
                            }
                        ),
                        in: 1...ClipboardConfig.maximumMaxItems,
                        step: 50
                    ) { Text("\(state.clipboardHistory.policy.maxItems)") }
                }.padding(.horizontal, 12).padding(.vertical, 10)
                SettingsDivider()
                HStack {
                    SettingsLabel(title: "Keep for", subtitle: "Unpinned items older than this are dropped")
                    Spacer()
                    Stepper(
                        value: Binding(
                            get: { Int(state.clipboardHistory.policy.maxAge / 86_400) },
                            set: {
                                state.settings.setClipboardRetention(
                                    maxItems: state.clipboardHistory.policy.maxItems,
                                    maxBytes: state.clipboardHistory.policy.maxBytes,
                                    maxAgeDays: $0
                                )
                            }
                        ),
                        in: ClipboardConfig.minimumMaxAgeDays...ClipboardConfig.maximumMaxAgeDays,
                        step: 30
                    ) { Text("\(Int(state.clipboardHistory.policy.maxAge / 86_400)) days") }
                }.padding(.horizontal, 12).padding(.vertical, 10)
                SettingsDivider()
                HStack {
                    SettingsLabel(title: "Storage cap", subtitle: "Approximate ceiling for all retained data")
                    Spacer()
                    Stepper(
                        value: Binding(
                            get: { state.clipboardHistory.policy.maxBytes / (1_024 * 1_024) },
                            set: {
                                state.settings.setClipboardRetention(
                                    maxItems: state.clipboardHistory.policy.maxItems,
                                    maxBytes: $0 * 1_024 * 1_024,
                                    maxAgeDays: Int(state.clipboardHistory.policy.maxAge / 86_400)
                                )
                            }
                        ),
                        in: (ClipboardConfig.minimumMaxBytes / (1_024 * 1_024))...(ClipboardConfig.maximumMaxBytes / (1_024 * 1_024)),
                        step: 256
                    ) { Text("\(state.clipboardHistory.policy.maxBytes / (1_024 * 1_024)) MB") }
                }.padding(.horizontal, 12).padding(.vertical, 10)
                SettingsDivider()
                ExcludedAppsRow(
                    title: "Excluded apps",
                    bundleIDs: state.clipboardHistory.excludedBundleIdentifiers,
                    commit: { state.settings.setClipboardExcludedBundleIdentifiers($0.joined(separator: ", ")) }
                )
            }
            if let error = state.clipboardHistory.error {
                SettingsNotice(text: "Clipboard history could not be saved: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
            }
        }
    }
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case appearance
    case commands
    case quicklinks
    case scripts
    case clipboard
    case ai
    case agents
    case widgets
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .commands: "Commands"
        case .quicklinks: "Quicklinks"
        case .scripts: "Scripts"
        case .clipboard: "Clipboard"
        case .ai: "AI"
        case .agents: "Agents"
        case .widgets: "Home"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "circle.lefthalf.filled"
        case .commands: "command"
        case .quicklinks: "link"
        case .scripts: "terminal"
        case .clipboard: "doc.on.clipboard"
        case .ai: "sparkles"
        case .agents: "sparkles.rectangle.stack"
        case .widgets: "house"
        case .advanced: "wrench.and.screwdriver"
        case .about: "info.circle"
        }
    }
}

struct SettingsAnchor: ViewModifier {
    let id: String
    let highlighted: Bool

    func body(content: Content) -> some View {
        content
            .id(id)
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(FoundryTheme.selectionBorder, lineWidth: highlighted ? 2 : 0)
                    .allowsHitTesting(false)
            )
    }
}
