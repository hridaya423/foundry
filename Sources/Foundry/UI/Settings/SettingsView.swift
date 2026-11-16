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
    @Namespace private var railSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            settingsRail
            Divider()
            detailPane
        }
        .background(FoundryTheme.windowGround)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            searchFocused = true
            select(category)
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
        VStack(alignment: .leading, spacing: FoundryTheme.Spacing.sm) {
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

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if isSearching == false {
                        ForEach(SettingsCategory.allCases) { item in
                            SettingsRailButton(title: item.title, symbol: item.symbol, isSelected: category == item,
                                selection: railSelection) { select(item) }
                        }
                    } else if searchMatches.isEmpty {
                        Text("No settings match \u{201C}\(searchQuery)\u{201D}")
                            .font(FoundryTheme.bodySecondary)
                            .foregroundStyle(FoundryTheme.textTertiary)
                            .padding(.horizontal, FoundryTheme.Spacing.sm)
                            .padding(.top, 4)
                    } else {
                        ForEach(searchMatches) { item in
                            SettingsRailButton(title: item.title, symbol: item.pane.symbol,
                                isSelected: highlightedAnchor == item.anchorID && category == item.pane,
                                selection: railSelection) { reveal(item) }
                        }
                    }
                }
                .animation(reduceMotion ? nil : FoundryTheme.Motion.state, value: category)
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, FoundryTheme.Spacing.sm)
        .padding(.top, FoundryTheme.Control.rowDouble)
        .padding(.bottom, FoundryTheme.Spacing.sm)
        .frame(width: 208, alignment: .leading)
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
                .font(FoundryTheme.title)
                .foregroundStyle(FoundryTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .frame(height: FoundryTheme.Control.compact)
                .padding(.horizontal, FoundryTheme.Spacing.lg)
                .padding(.top, FoundryTheme.Control.rowDouble)

            if let error = state.settings.configLoadError {
                SettingsNotice(
                    text: "Foundry could not load its settings. Editing is disabled until they are reset. \(error)",
                    symbol: "exclamationmark.triangle",
                    actionTitle: "Reset",
                    action: state.settings.resetConfiguration
                )
                .padding(.horizontal, FoundryTheme.Spacing.lg)
                .padding(.top, FoundryTheme.Spacing.sm)
            }

            if let error = state.settings.settingsPersistenceError {
                SettingsNotice(text: LocalizedStringResource(stringLiteral: error), symbol: "exclamationmark.triangle")
                    .padding(.horizontal, FoundryTheme.Spacing.lg)
                    .padding(.top, FoundryTheme.Spacing.sm)
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
                    .padding(.top, FoundryTheme.Spacing.sm)
                    .padding(.bottom, FoundryTheme.Spacing.lg)
                    .frame(maxWidth: 720, alignment: .leading)
                    .buttonStyle(SettingsButtonStyle())
                }
                .mask(scrollEdgeFade)
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

    private var scrollEdgeFade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: FoundryTheme.Spacing.sm)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: FoundryTheme.Spacing.lg)
        }
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
                        subtitle: LocalizedStringResource(stringLiteral:
                            (ConfigService.configURL.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    )
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([ConfigService.configURL])
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .modifier(anchor("advanced.config"))

            SettingsGroup {
                HStack(spacing: 12) {
                    SettingsLabel(title: "Backup",
                        subtitle: "Settings, snippets, quicklinks and script folders. Clipboard history and API keys are not included.")
                    Spacer()
                    Button("Export…", action: exportBackup)
                    Button("Import…", action: chooseBackup)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
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
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
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
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
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
        VStack(alignment: .leading, spacing: 12) {
            aboutVersion
            SettingsGroup {
                SettingsToggleRow(title: "Check for updates",
                    subtitle: "Foundry asks GitHub once a day for a newer version",
                    isOn: state.settings.checkForUpdates, set: state.settings.setCheckForUpdates)
            }
            .modifier(anchor("about.updates"))
        }
    }

    private var aboutVersion: some View {
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
                Link("Website", destination: Self.websiteURL)
                Link("Releases", destination: Self.releasesURL)
            }
            .padding(14)
        }
        .modifier(anchor("about.version"))
    }

    private static let websiteURL = URL(string: "https://foundry.hridya.tech")!
    private static let releasesURL = URL(string: "https://github.com/hridaya423/foundry/releases/latest")!

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
                    .padding(.vertical, 12)
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

            if state.settings.releasedLaunchers.isEmpty == false {
                SettingsNotice(
                    text: "During setup Foundry moved \(state.settings.releasedLaunchers.formatted(.list(type: .and))) to ⌥ Space to free ⌘ Space.",
                    symbol: "arrow.uturn.backward",
                    actionTitle: "Give ⌘ Space Back",
                    action: { Task { await state.settings.giveCommandSpaceBack() } }
                )
            }

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
                        subtitle: "Adds a Foundry menu with Clipboard History and Settings",
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
                    SettingsLabel(title: "Return to Home after", subtitle: "Reopen sooner to resume where you were")
                    Spacer()
                    SettingsMenuPicker(title: "Return to Home after", options: [
                        (0, String(localized: "Immediately")), (30, String(localized: "30 seconds")),
                        (90, String(localized: "90 seconds")), (300, String(localized: "5 minutes")),
                        (.greatestFiniteMagnitude, String(localized: "Never"))
                    ], selection: state.settings.popToRootAfterSeconds) { state.settings.setPopToRootAfter($0) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
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
                    SettingsMenuPicker(title: "Search sensitivity", options: SearchSensitivity.allCases.map { ($0, $0.title) },
                        selection: state.settings.searchSensitivity) { state.settings.setSearchSensitivity($0) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
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
                    Button("Export…") { state.snippets.exportToFile() }
                        .disabled(state.snippets.items.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
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
                SettingsLabel(title: "Main browser", subtitle: "For browser history and open tabs")
                Spacer()
                SettingsMenuPicker(title: "Main browser", options: state.installedBrowsers.map { ($0, $0.displayName) },
                    selection: state.settings.mainBrowser ?? .safari) { state.settings.setMainBrowser($0) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
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
                    }
                    Button("Privacy Settings") { state.settings.openSnippetExpansionPrivacySettings() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                SettingsDivider()
                VStack(alignment: .leading, spacing: 10) {
                    SettingsLabel(title: "Expand after", subtitle: "Keywords expand when one of these is typed")
                    HStack(spacing: FoundryTheme.Spacing.md) {
                        ForEach(snippetDelimiterOptions, id: \.delimiter) { option in
                            Toggle(option.label, isOn: Binding(
                                get: { state.settings.snippetExpansion.delimiters.contains(option.delimiter) },
                                set: { state.settings.setSnippetExpansionDelimiter(option.delimiter, enabled: $0) }
                            ))
                            .toggleStyle(FoundryCheckboxStyle())
                        }
                    }
                    .font(FoundryTheme.bodySecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
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
                .padding(.vertical, 12)
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
            .padding(.vertical, 12)
        }
    }

    private var windowHotkeysContent: some View {
        SettingsGroup {
            HStack(spacing: 10) {
                SettingsLabel(title: "Window layout shortcuts",
                    subtitle: "Suggested: \(WindowHotkeySuggestions.summary). Only layouts without a shortcut get one.")
                Spacer()
                Button("Use Suggested") { state.settings.applySuggestedWindowHotkeys() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
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
                .padding(.vertical, 12)
            }

            if state.settings.isCommandCatalogLoading && state.settings.commandCatalogCount == 0 {
                HStack(spacing: 8) {
                    ProgressView()
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
                                },
                                hotkeyIssue: state.settings.commandHotkeyIssues[row.id]
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
                    Text((AgentEventSocketServer.socketURL.path as NSString).abbreviatingWithTildeInPath)
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
                        install: { state.agents.installIntegration(for: provider) },
                        remove: { state.agents.removeIntegration(for: provider) }
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
                    SettingsMenuPicker(title: "Retain items",
                        options: Self.itemLimits(current: state.clipboardHistory.policy.maxItems).map { ($0, $0.formatted()) },
                        selection: state.clipboardHistory.policy.maxItems) {
                        applyRetention(
                            maxItems: $0,
                            maxBytes: state.clipboardHistory.policy.maxBytes,
                            maxAgeDays: Int(state.clipboardHistory.policy.maxAge / 86_400)
                        )
                    }
                }.padding(.horizontal, 12).padding(.vertical, 12)
                SettingsDivider()
                HStack {
                    SettingsLabel(title: "Keep for", subtitle: "Unpinned items older than this are dropped")
                    Spacer()
                    let current = Int(state.clipboardHistory.policy.maxAge / 86_400)
                    SettingsMenuPicker(title: "Keep for",
                        options: Set([1, 7, 30, 90, 365, ClipboardConfig.maximumMaxAgeDays, current]).sorted()
                            .map { ($0, Self.retentionLabel(days: $0)) },
                        selection: current) {
                        applyRetention(
                            maxItems: state.clipboardHistory.policy.maxItems,
                            maxBytes: state.clipboardHistory.policy.maxBytes,
                            maxAgeDays: $0
                        )
                    }
                }.padding(.horizontal, 12).padding(.vertical, 12)
                SettingsDivider()
                HStack {
                    SettingsLabel(title: "Storage cap", subtitle: "Approximate ceiling for all retained data")
                    Spacer()
                    let megabyte = 1_024 * 1_024
                    SettingsMenuPicker(title: "Storage cap",
                        options: Set([256, 512, 1_024, 2_048, 4_096].map { $0 * megabyte } + [state.clipboardHistory.policy.maxBytes]).sorted()
                            .map { ($0, Int64($0).formatted(.byteCount(style: .memory))) },
                        selection: state.clipboardHistory.policy.maxBytes) {
                        applyRetention(
                            maxItems: state.clipboardHistory.policy.maxItems,
                            maxBytes: $0,
                            maxAgeDays: Int(state.clipboardHistory.policy.maxAge / 86_400)
                        )
                    }
                }.padding(.horizontal, 12).padding(.vertical, 12)
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
