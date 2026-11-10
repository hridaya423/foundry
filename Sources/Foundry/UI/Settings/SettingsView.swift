import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers
import FoundryDomain

struct SettingsView: View {
    @Bindable var state: CommandPanelState
    @AppStorage("settings.lastPane") private var category: SettingsCategory = .general
    @State private var searchQuery = ""
    @State private var pendingAnchor: String?
    @State private var highlightedAnchor: String?
    @State private var confirmingReset = false
    @State private var confirmingModelRemoval = false
    @State private var pendingBackup: FoundryBackup?
    @State private var pendingRetention: ClipboardRetention?
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            settingsRail
                .frame(minWidth: 210)
                .navigationSplitViewColumnWidth(min: 210, ideal: 210, max: 260)
                .toolbar(removing: .sidebarToggle)
        } detail: {
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
        case .ai:
            category = .ai
            pendingAnchor = "ai.provider"
        case .snippets:
            category = .snippets
        case .agents:
            category = .agents
        case let .command(id, title):
            category = .commands
            state.settings.prepareCommandCatalog()
            state.settings.commandSettingsQuery = title
            state.settings.expandedCommandID = id
            pendingAnchor = "commands.\(id)"
            highlightedAnchor = "commands.\(id)"
        }
    }

    private var searchMatches: [SettingItem] {
        SettingsSearch.matches(searchQuery)
    }

    private var isSearching: Bool {
        searchQuery.trimmingCharacters(in: .whitespaces).isEmpty == false
    }

    private var settingsRail: some View {
        List(selection: railSelection) {
            if isSearching == false {
                ForEach(SettingsCategory.allCases) { item in
                    Label(item.title, systemImage: item.symbol).tag(item.rawValue)
                }
            } else if searchMatches.isEmpty {
                Text("No settings match \u{201C}\(searchQuery)\u{201D}")
                    .font(FoundryTheme.bodySecondary)
                    .foregroundStyle(FoundryTheme.textTertiary)
                    .selectionDisabled()
            } else {
                ForEach(searchMatches) { item in
                    Label(item.title, systemImage: item.pane.symbol).tag(item.id)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: FoundryTheme.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(FoundryTheme.Glyph.xs)
                    .foregroundStyle(FoundryTheme.textTertiary)
                TextField("Search settings", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(FoundryTheme.bodySecondary)
                    .focused($searchFocused)
                    .onSubmit { if let first = searchMatches.first { reveal(first) } }
            }
            .padding(.horizontal, FoundryTheme.Spacing.sm)
            .frame(height: FoundryTheme.Control.compact)
            .background(FoundryTheme.fillHover, in: RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
            .padding(.horizontal, FoundryTheme.Spacing.md)
            .padding(.bottom, FoundryTheme.Spacing.xs)
        }
    }

    private var railSelection: Binding<String?> {
        Binding(
            get: {
                guard isSearching else { return category.rawValue }
                return searchMatches.first { $0.anchorID == highlightedAnchor && $0.pane == category }?.id
            },
            set: { id in
                if let item = searchMatches.first(where: { $0.id == id }) {
                    reveal(item)
                } else if let id, let item = SettingsCategory(rawValue: id) {
                    select(item)
                }
            }
        )
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
                SettingsNotice(text: LocalizedStringResource(stringLiteral: error), symbol: "exclamationmark.triangle")
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch category {
                        case .general:
                            generalContent
                        case .commands:
                            FallbackSettingsPane(settings: state.settings).modifier(anchor("commands.fallbacks"))
                            windowHotkeysContent.modifier(anchor("commands.windowHotkeys"))
                            commandsContent.id("commands.list")
                        case .quicklinks:
                            QuicklinksSettingsPane(settings: state.settings).id("quicklinks.list")
                        case .snippets:
                            snippetsContent
                        case .scripts:
                            ScriptsSettingsPane().id("scripts.folders")
                        case .fileSearch:
                            FileSearchSettingsPane(settings: state.settings).id("fileSearch.folders")
                        case .clipboard:
                            clipboardContent.id("clipboard.history")
                        case .browser:
                            browserContent
                        case .permissions:
                            PermissionsSettingsPane().id("permissions.list")
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
                    .padding(.horizontal, FoundryTheme.Spacing.lg)
                    .padding(.vertical, FoundryTheme.Spacing.md)
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
        .navigationTitle(category.title)
    }

    private func anchor(_ id: String) -> SettingsAnchor {
        SettingsAnchor(id: id, highlighted: highlightedAnchor == id)
    }

    private var advancedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup {
                HStack(spacing: 12) {
                    SettingsLabel(
                        title: "Config folder",
                        subtitle: LocalizedStringResource(stringLiteral: ConfigService.configURL.deletingLastPathComponent().path)
                    )
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
                Button("Import", role: .destructive) {
                    if let pendingBackup { state.settings.restoreBackup(pendingBackup) }
                }
            } message: {
                let changes = pendingBackup.map(state.settings.sensitiveChanges(in:)) ?? []
                Text(changes.isEmpty ? "Current files are kept next to the originals as .pre-import copies."
                    : "This backup changes:\n\(changes.joined(separator: "\n"))\n\nCurrent files are kept next to the originals as .pre-import copies.")
            }

            if state.fileShelf.hasDetailedModelData {
                SettingsGroup {
                    HStack(spacing: 12) {
                        SettingsLabel(title: "Background removal model", subtitle: "Used by Remove Background (Detailed) on the File Shelf")
                        Spacer()
                        Button("Remove Model Data…", role: .destructive) { confirmingModelRemoval = true }
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                }
                .modifier(anchor("advanced.backgroundModel"))
                .confirmationDialog("Delete the background-removal model?", isPresented: $confirmingModelRemoval) {
                    Button("Delete Model", role: .destructive, action: state.fileShelf.removeBEN2Data)
                } message: {
                    Text("You can download it again later.")
                }
            }

            SettingsGroup {
                HStack(spacing: 12) {
                    SettingsLabel(title: "Reset settings", subtitle: "Restore every preference to its default")
                    Spacer()
                    Button("Reset…", role: .destructive) { confirmingReset = true }
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            }
            .modifier(anchor("advanced.reset"))
            .confirmationDialog("Reset all Foundry settings?", isPresented: $confirmingReset) {
                Button("Reset", role: .destructive, action: state.settings.resetConfiguration)
            } message: {
                Text("Clipboard history and snippets are kept.")
            }
        }
    }

    private struct ClipboardRetention: Equatable {
        let maxItems: Int
        let maxBytes: Int
        let maxAgeDays: Int
        let removed: Int
    }

    private func applyRetention(maxItems: Int, maxBytes: Int, maxAgeDays: Int) {
        let removed = state.clipboardHistory.itemsRemoved(maxItems: maxItems, maxBytes: maxBytes, maxAgeDays: maxAgeDays)
        guard removed > 0 else {
            state.settings.setClipboardRetention(maxItems: maxItems, maxBytes: maxBytes, maxAgeDays: maxAgeDays)
            return
        }
        pendingRetention = ClipboardRetention(maxItems: maxItems, maxBytes: maxBytes, maxAgeDays: maxAgeDays, removed: removed)
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Foundry-\(Date().formatted(.iso8601.year().month().day())).\(FoundryBackup.fileExtension)"
        panel.allowedContentTypes = [UTType(filenameExtension: FoundryBackup.fileExtension) ?? .json]
        Task { @MainActor in
            guard await runFilePanelAsSheet(panel), let url = panel.url else { return }
            state.settings.exportBackup(to: url)
        }
    }

    private func chooseBackup() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        Task { @MainActor in
            guard await runFilePanelAsSheet(panel), let url = panel.url else { return }
            pendingBackup = state.settings.loadBackup(from: url)
        }
    }

    private var aboutContent: some View {
        SettingsGroup {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Foundry")
                        .font(FoundryTheme.title)
                        .foregroundStyle(FoundryTheme.textPrimary)
                    Text(Self.versionString)
                        .font(FoundryTheme.bodySecondary.monospacedDigit())
                        .foregroundStyle(FoundryTheme.textTertiary)
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
                                .frame(width: FoundryTheme.Control.settingsColumn, height: FoundryTheme.Control.compact)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    if let error = state.settings.hotkeyError {
                        Text(error)
                            .font(FoundryTheme.bodySecondary)
                            .foregroundStyle(FoundryTheme.destructive)
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
                        subtitle: state.settings.launchAtLoginAvailable
                            ? "Start Foundry automatically when you sign in"
                            : "Available in the installed Foundry app",
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
                }
            }
            .modifier(anchor("general.system"))
            if let error = state.settings.launchAtLoginError {
                SettingsNotice(text: LocalizedStringResource(stringLiteral: error), symbol: "exclamationmark.triangle")
            }

            SettingsGroup {
                HStack(spacing: 12) {
                    SettingsLabel(title: "Return to Home after", subtitle: "Reopening sooner than this resumes where you left off.")
                    Spacer()
                    Picker("Return to Home after", selection: Binding(
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
                    .frame(width: FoundryTheme.Control.settingsColumn, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            }
            .modifier(anchor("general.popToRoot"))

            compactModeGroup
                .modifier(anchor("general.compact"))

            panelContrastGroup
                .modifier(anchor("general.contrast"))

            SettingsGroup {
                HStack(spacing: 12) {
                    SettingsLabel(title: "Search sensitivity", subtitle: LocalizedStringResource(stringLiteral: state.settings.searchSensitivity.subtitle))
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
                    .frame(width: FoundryTheme.Control.settingsColumn, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            }
            .modifier(anchor("general.sensitivity"))
        }
    }

    private var snippetsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup {
                HStack(spacing: 12) {
                    SettingsLabel(title: "Snippet library",
                        subtitle: "^[\(state.snippets.items.count) snippet](inflect: true). Import and export use Raycast's JSON format.")
                    Spacer()
                    Button("Import…") { state.snippets.importFromFile() }
                        .controlSize(.small)
                    Button("Export…") { state.snippets.exportToFile() }
                        .controlSize(.small)
                        .disabled(state.snippets.items.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            }
            .modifier(anchor("snippets.library"))
            snippetExpansionContent
                .modifier(anchor("snippets.expansion"))
        }
        .onAppear(perform: state.snippets.load)
    }

    private var browserContent: some View {
        SettingsGroup {
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
                .frame(width: FoundryTheme.Control.settingsColumn, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
        .modifier(anchor("browser.main"))
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
                        Button("Request Access") { state.settings.requestSnippetExpansionAccessibility() }
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
                    HStack(spacing: FoundryTheme.Spacing.md) {
                        ForEach(snippetDelimiterOptions, id: \.delimiter) { option in
                            Toggle(option.label, isOn: Binding(
                                get: { state.settings.snippetExpansion.delimiters.contains(option.delimiter) },
                                set: { state.settings.setSnippetExpansionDelimiter(option.delimiter, enabled: $0) }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }
                    .font(FoundryTheme.bodySecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                SettingsDivider()
                HStack(spacing: 12) {
                    SettingsLabel(title: "Return key in search", subtitle: "What Return does on a snippet result")
                    Spacer()
                    Picker("Return key in search", selection: Binding(
                        get: { state.settings.snippetExpansion.insertAsPrimary },
                        set: { state.settings.setSnippetInsertAsPrimary($0) }
                    )) {
                        Text("Insert").tag(true)
                        Text("Copy").tag(false)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: FoundryTheme.Control.settingsColumn, alignment: .trailing)
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
                SettingsNotice(text: LocalizedStringResource(stringLiteral: error), symbol: "exclamationmark.triangle")
            }
        }
    }

    private var snippetDelimiterOptions: [(label: String, delimiter: String)] {
        [("Space", " "), ("Return", "\n"), ("Tab", "\t"), ("Quote", "'"), ("Backtick", "`")]
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
                        .font(FoundryTheme.body)
                        .foregroundStyle(FoundryTheme.textSecondary)
                }

                Slider(
                    value: Binding(
                        get: { state.settings.themeIntensity },
                        set: { value in state.settings.setThemeIntensity(value) }
                    ),
                    in: 0.2...1
                )
                .tint(FoundryTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
    }

    private var windowHotkeysContent: some View {
        SettingsGroup {
            HStack(spacing: 10) {
                SettingsLabel(title: "Window layout shortcuts",
                    subtitle: "Suggested: \(WindowHotkeySuggestions.summary). Only layouts without a shortcut get one.")
                Spacer()
                Button("Use Suggested") { state.settings.applySuggestedWindowHotkeys() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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
                        .font(FoundryTheme.Glyph.xs)
                        .foregroundStyle(FoundryTheme.textTertiary)
                    TextField("Search commands", text: $state.settings.commandSettingsQuery)
                        .textFieldStyle(.plain)
                        .font(FoundryTheme.body)
                        .foregroundStyle(FoundryTheme.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            if state.settings.isCommandCatalogLoading && state.settings.commandCatalogCount == 0 {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing command catalog…")
                        .font(FoundryTheme.bodySecondary)
                        .foregroundStyle(FoundryTheme.textTertiary)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 5)
            } else if state.settings.isCommandCatalogReady && state.settings.commandCatalogCount == 0 {
                Text("No commands are available.")
                    .font(FoundryTheme.bodySecondary)
                    .foregroundStyle(FoundryTheme.textTertiary)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 5)
            } else if state.settings.visibleCommandRows.isEmpty {
                Text("No commands match this search.")
                    .font(FoundryTheme.bodySecondary)
                    .foregroundStyle(FoundryTheme.textTertiary)
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
                                toggleExpanded: { state.settings.toggleCommandExpansion(row.id) },
                                hotkeyConflict: { keyCode, modifiers in
                                    state.settings.commandHotkeyOwner(
                                        keyCode: keyCode, modifiers: modifiers, excluding: row.id
                                    )
                                }
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
                            .font(FoundryTheme.body)
                            .foregroundStyle(state.agents.socketListening ? FoundryTheme.success : FoundryTheme.warning)
                    }
                    Text(AgentEventSocketServer.socketURL.path)
                        .font(FoundryTheme.mono)
                        .foregroundStyle(FoundryTheme.textQuaternary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(
                        "Foundry shows sessions from your coding agents. Approvals and replies happen in each agent's own app unless it supports " +
                            "replying from Foundry.")
                        .font(FoundryTheme.caption)
                        .foregroundStyle(FoundryTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }

            if let integrationError = state.agents.integrationError {
                SettingsNotice(text: LocalizedStringResource(stringLiteral: integrationError), symbol: "exclamationmark.triangle")
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

        }
    }

    private var widgetsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(title: "Home strip", value: "\(state.widgetBoard.config.enabled.count)/\(WidgetBoardConfig.maxEnabled)")
            SettingsGroup {
                if state.widgetBoard.config.enabled.isEmpty {
                        Text("No Home widgets yet. Add one below.")
                        .font(FoundryTheme.bodySecondary)
                        .foregroundStyle(FoundryTheme.textTertiary)
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
                    .font(FoundryTheme.bodySecondary)
                    .foregroundStyle(FoundryTheme.textTertiary)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 5)
            } else if state.widgetBoard.config.available.isEmpty {
                Text("All available widgets are already on Home.")
                    .font(FoundryTheme.bodySecondary)
                    .foregroundStyle(FoundryTheme.textTertiary)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 5)
            } else {
                ForEach(WidgetCategory.allCases, id: \.self) { category in
                    let kinds = state.widgetBoard.config.available.filter { $0.category == category }
                    if kinds.isEmpty == false {
                        Text(category.title)
                            .font(FoundryTheme.micro)
                            .foregroundStyle(FoundryTheme.textTertiary)
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

    static func itemLimits(current: Int) -> [Int] {
        let standard = [100, 250, 500, 1_000, 5_000].filter { $0 <= ClipboardConfig.maximumMaxItems }
        return standard.contains(current) ? standard : (standard + [current]).sorted()
    }

    private static func retentionLabel(days: Int) -> String {
        switch days {
        case 1: String(localized: "1 day")
        case 7: String(localized: "1 week")
        case 30: String(localized: "1 month")
        case 90: String(localized: "3 months")
        case 365: String(localized: "1 year")
        case ClipboardConfig.maximumMaxAgeDays: String(localized: "Forever")
        default: String(localized: "\(days) days")
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
                    Picker("Retain items", selection: Binding(
                        get: { state.clipboardHistory.policy.maxItems },
                        set: {
                            applyRetention(
                                maxItems: $0,
                                maxBytes: state.clipboardHistory.policy.maxBytes,
                                maxAgeDays: Int(state.clipboardHistory.policy.maxAge / 86_400)
                            )
                        }
                    )) {
                        ForEach(Self.itemLimits(current: state.clipboardHistory.policy.maxItems), id: \.self) { limit in
                            Text(limit.formatted()).tag(limit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: FoundryTheme.Control.settingsColumn, alignment: .trailing)
                }.padding(.horizontal, 12).padding(.vertical, 10)
                SettingsDivider()
                HStack {
                    SettingsLabel(title: "Keep for", subtitle: "Unpinned items older than this are dropped")
                    Spacer()
                    Picker("Keep for", selection: Binding(
                        get: { Int(state.clipboardHistory.policy.maxAge / 86_400) },
                        set: {
                            applyRetention(
                                maxItems: state.clipboardHistory.policy.maxItems,
                                maxBytes: state.clipboardHistory.policy.maxBytes,
                                maxAgeDays: $0
                            )
                        }
                    )) {
                        let current = Int(state.clipboardHistory.policy.maxAge / 86_400)
                        ForEach(Array(Set([1, 7, 30, 90, 365, ClipboardConfig.maximumMaxAgeDays, current])).sorted(), id: \.self) { days in
                            Text(Self.retentionLabel(days: days)).tag(days)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: FoundryTheme.Control.settingsColumn, alignment: .trailing)
                }.padding(.horizontal, 12).padding(.vertical, 10)
                SettingsDivider()
                HStack {
                    SettingsLabel(title: "Storage cap", subtitle: "Approximate ceiling for all retained data")
                    Spacer()
                    Stepper(
                        value: Binding(
                            get: { state.clipboardHistory.policy.maxBytes / (1_024 * 1_024) },
                            set: {
                                applyRetention(
                                    maxItems: state.clipboardHistory.policy.maxItems,
                                    maxBytes: $0 * 1_024 * 1_024,
                                    maxAgeDays: Int(state.clipboardHistory.policy.maxAge / 86_400)
                                )
                            }
                        ),
                        in: (ClipboardConfig.minimumMaxBytes / (1_024 * 1_024))...(ClipboardConfig.maximumMaxBytes / (1_024 * 1_024)),
                        step: 256
                    ) { Text("\(state.clipboardHistory.policy.maxBytes / (1_024 * 1_024)) MB") }
                    .frame(width: FoundryTheme.Control.settingsColumn, alignment: .trailing)
                }.padding(.horizontal, 12).padding(.vertical, 10)
                SettingsDivider()
                ExcludedAppsRow(
                    title: "Excluded apps",
                    bundleIDs: state.clipboardHistory.excludedBundleIdentifiers,
                    commit: { state.settings.setClipboardExcludedBundleIdentifiers($0.joined(separator: ", ")) }
                )
            }
            if let error = state.clipboardHistory.error {
                SettingsNotice(text: "Couldn't load or save clipboard history: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
            }
        }
        .confirmationDialog("Remove \(pendingRetention?.removed ?? 0) older clipboard items?",
            isPresented: Binding(get: { pendingRetention != nil }, set: { if $0 == false { pendingRetention = nil } })) {
            Button("Remove Items", role: .destructive) {
                if let retention = pendingRetention {
                    state.settings.setClipboardRetention(maxItems: retention.maxItems, maxBytes: retention.maxBytes, maxAgeDays: retention.maxAgeDays)
                }
                pendingRetention = nil
            }
        } message: {
            Text("They don't fit the new limit. This can't be undone.")
        }
    }
}
