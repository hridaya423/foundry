import AppKit
import Foundation
import ServiceManagement
import SwiftUI
import FoundryDomain
import FoundryServices

/// The settings surface: every config-mirrored field, the command catalog,
/// backup/restore, and feature-config mutations. Views bind this directly —
/// there are no shadowed copies on `CommandPanelState`.
@MainActor
@Observable
final class SettingsStore {
    var isAgentShelfVisible = true
    var hotkey: FoundryHotkey = .commandSpace
    var hotkeyError: String? = nil
    var launcherHotkeyFailed = false
    var showMenuBarIcon = true
    var hapticsEnabled = true
    var popToRootAfterSeconds = 90.0
    var windowMode = WindowMode.standard
    var launchAtLoginError: String?
    var mainBrowser: BrowserSource?
    var themeIntensity = 0.72
    var searchSensitivity = SearchSensitivity.medium
    var settingsPersistenceError: String?
    var snippetExpansion = SnippetExpansionConfig.default
    var snippetExpansionError: String?
    var fallbacks = FallbackConfig.default
    var fileSearch = FileSearchConfig.default
    var quicklinkSiteIcons = true
    var checkForUpdates = true
    var commandSettingsQuery = "" {
        didSet { rebuildCommandRows() }
    }
    var commandDescriptors: [CommandDescriptor] = []
    var commandPreferences: [String: CommandPreference] = [:]
    var commandRows: [CommandSettingsRowModel] = []
    var visibleCommandRows: [CommandSettingsRowModel] = []
    var commandCatalogFailures: [String] = []
    var isCommandCatalogLoading = false
    var isCommandCatalogReady = false
    var configLoadError: String? = nil
    var expandedCommandID: String?
    private var commandCatalogTask: Task<Void, Never>?

    let configService: ConfigService
    let diagnostics: DiagnosticsService
    let registry: CommandRegistry
    /// Panel orchestration the store must trigger after a mutation —
    /// result refresh, favorites, clipboard re-configuration.
    weak var panel: CommandPanelState?

    private var shell: (any ShellPort)? { panel?.shell }

    init(configService: ConfigService, diagnostics: DiagnosticsService, registry: CommandRegistry) {
        self.configService = configService
        self.diagnostics = diagnostics
        self.registry = registry
        configService.onSaveFailure { [weak self] reason in
            Task { @MainActor in self?.showSettingsPersistenceError(ConfigSaveFailure(reason: reason)) }
        }
    }

    /// Mirrors a config snapshot onto the store — used at init and after a
    /// backup restore replaces the config wholesale.
    func apply(config: FoundryConfig) {
        isAgentShelfVisible = config.showAgentShelf
        showMenuBarIcon = config.showMenuBarIcon
        hapticsEnabled = config.hapticsEnabled
        popToRootAfterSeconds = config.popToRootAfterSeconds
        windowMode = config.windowMode
        hotkey = config.hotkey
        mainBrowser = config.localState.mainBrowser.flatMap(BrowserSource.init(rawValue:))
        themeIntensity = config.themeIntensity
        searchSensitivity = config.searchSensitivity
        snippetExpansion = config.snippetExpansion
        fallbacks = config.fallbacks
        fileSearch = config.fileSearch
        quicklinkSiteIcons = config.quicklinkSiteIcons
        checkForUpdates = config.checkForUpdates
        commandPreferences = config.commandPreferences
        configLoadError = configService.loadErrorMessage
        releasedLaunchers = Self.launcherNames(config.localState.releasedLaunchers)
    }

    var launchAtLoginAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier == "com.hridya.foundry"
    }

    var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var commandCatalogCount: Int {
        commandRows.count
    }

    func prepareCommandCatalog(forceRefresh: Bool = false) {
        guard isCommandCatalogLoading == false, forceRefresh || isCommandCatalogReady == false else { return }
        isCommandCatalogLoading = true
        if forceRefresh {
            isCommandCatalogReady = false
        }
        let registry = registry
        let diagnostics = diagnostics
        let span = diagnostics.startSpan("commands.catalog.prepare")
        commandCatalogTask = Task { [weak self] in
            let snapshot = await registry.commandCatalog(forceRefresh: forceRefresh)
            diagnostics.endSpan(span)
            guard let self, Task.isCancelled == false else { return }
            self.commandDescriptors = snapshot.descriptors
            self.commandCatalogFailures = snapshot.providerFailures
            self.isCommandCatalogLoading = false
            self.isCommandCatalogReady = true
            self.rebuildCommandRows()
            self.commandCatalogTask = nil
        }
    }

    func retryCommandCatalog() {
        commandCatalogTask?.cancel()
        commandCatalogTask = nil
        isCommandCatalogLoading = false
        prepareCommandCatalog(forceRefresh: true)
    }

    func cancelCatalogTask() {
        commandCatalogTask?.cancel()
        commandCatalogTask = nil
    }

    func setHotkey(_ hotkey: FoundryHotkey) {
        guard self.hotkey != hotkey else { return }
        let previous = self.hotkey
        var didRegister = false
        do {
            try shell?.hotkeyChanged(hotkey)
            didRegister = true
            try configService.updateHotkey(hotkey)
            self.hotkey = hotkey
            hotkeyError = nil
            settingsPersistenceError = nil
        } catch {
            if didRegister {
                do {
                    try shell?.hotkeyChanged(previous)
                } catch {
                    diagnostics.log("Failed to restore previous hotkey: \(error.localizedDescription)")
                }
                showSettingsPersistenceError(error)
            } else {
                hotkeyError = String(localized: "That shortcut is unavailable. Choose another key combination.")
                diagnostics.log("Failed to register hotkey: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    func applySetting<Value>(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Value>, _ value: Value, save: (Value) throws -> Void) -> Bool {
        let previous = self[keyPath: keyPath]
        self[keyPath: keyPath] = value
        do {
            try save(value)
            settingsPersistenceError = nil
            return true
        } catch {
            self[keyPath: keyPath] = previous
            showSettingsPersistenceError(error)
            return false
        }
    }

    func setHapticsEnabled(_ enabled: Bool) {
        if applySetting(\.hapticsEnabled, enabled, save: configService.updateHapticsEnabled) {
            shell?.snippetExpansionChanged()
        }
    }

    func setMenuBarIconVisible(_ visible: Bool) {
        if applySetting(\.showMenuBarIcon, visible, save: configService.updateMenuBarIconVisibility) {
            shell?.menuBarIconVisibilityChanged(visible)
        }
    }

    func setLauncherHotkeyFailed(_ failed: Bool) {
        launcherHotkeyFailed = failed
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard launchAtLoginAvailable else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            try configService.updateLocalState { $0.launchAtLoginConsent = enabled }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = String(localized: "Could not update launch at login: \(error.localizedDescription)")
            diagnostics.log("Launch at login update failed: \(error.localizedDescription)")
        }
    }

    func setMainBrowser(_ browser: BrowserSource) {
        if applySetting(\.mainBrowser, browser, save: { browser in
            try configService.updateLocalState { $0.mainBrowser = browser?.rawValue }
        }), browser == .firefox {
            FirefoxConnectorInstaller(diagnostics: diagnostics, requestPrompt: { [weak panel] spec in
                await panel?.requestPrompt(spec) ?? .cancelled
            }).requestFirefoxConnector()
        }
    }

    func setThemeIntensity(_ intensity: Double) {
        applySetting(\.themeIntensity, intensity, save: configService.updateThemeIntensity)
    }

    func setPopToRootAfter(_ seconds: Double) {
        applySetting(\.popToRootAfterSeconds, seconds, save: configService.updatePopToRootAfter)
    }

    func setWindowMode(_ mode: WindowMode) {
        applySetting(\.windowMode, mode, save: configService.updateWindowMode)
    }

    func showSettingsPersistenceError(_ error: Error) {
        settingsPersistenceError = String(localized: "Preferences could not be saved. Your previous settings were kept.")
        diagnostics.log("Settings persistence failed: \(error.localizedDescription)")
    }

    func resetConfiguration() {
        do {
            try configService.resetToDefaults()
            configLoadError = nil
            panel?.applyRestoredConfiguration()
            panel?.showActionFeedback(.success(String(localized: "Settings reset")))
        } catch {
            settingsPersistenceError = String(localized: "Could not reset Foundry settings. Your existing configuration was kept.")
            diagnostics.log("Settings reset failed: \(error.localizedDescription)")
        }
    }

    func exportBackup(to url: URL) {
        do {
            // Land any debounced write first — the export reads the file.
            configService.flush()
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
            try FoundryBackup.make(scriptDirectories: ScriptDirectoryStore.shared.directories, appVersion: version).encoded().write(to: url, options: .atomic)
        } catch {
            settingsPersistenceError = String(localized: "Could not save the backup: \(error.localizedDescription)")
            diagnostics.log("Backup export failed: \(error.localizedDescription)")
        }
    }

    func loadBackup(from url: URL) -> FoundryBackup? {
        do {
            return try FoundryBackup.decode(Data(contentsOf: url))
        } catch {
            settingsPersistenceError = (error as? LocalizedError)?.errorDescription ?? "Could not read the backup."
            return nil
        }
    }

    func sensitiveChanges(in backup: FoundryBackup) -> [String] {
        backup.sensitiveChanges(from: configService.current, scriptDirectories: ScriptDirectoryStore.shared.directories)
    }

    func restoreBackup(_ backup: FoundryBackup) {
        do {
            // The restore replaces config.json wholesale — a debounced write
            // of the pre-restore snapshot must not land on top of it.
            configService.discardPending()
            try backup.restore()
            try configService.reload()
            // restore() wrote script dirs into the pre-reload snapshot;
            // re-apply them onto the restored config.
            ScriptDirectoryStore.shared.directories = backup.scriptDirectories
            panel?.applyRestoredConfiguration()
            panel?.showActionFeedback(.success(String(localized: "Backup imported")))
        } catch {
            settingsPersistenceError = String(localized: "Could not import the backup. Your settings were left as they were.")
            diagnostics.log("Backup import failed: \(error.localizedDescription)")
        }
    }

    func toggleCommandExpansion(_ commandID: String) {
        expandedCommandID = expandedCommandID == commandID ? nil : commandID
    }

    func rebuildCommandRows() {
        let catalog = CommandSettingsCatalog.build(
            descriptors: commandDescriptors,
            preferences: commandPreferences,
            query: commandSettingsQuery
        )
        commandRows = catalog.rows
        visibleCommandRows = catalog.visibleRows
    }

    func commandPreference(for commandID: String) -> CommandPreference {
        commandPreferences[commandID]
            ?? CommandPreference(isEnabled: true)
    }

    func setCommandEnabled(_ isEnabled: Bool, for commandID: String) {
        var preference = commandPreference(for: commandID)
        preference.isEnabled = isEnabled
        updateCommandPreference(preference, for: commandID)
    }

    func setSearchSensitivity(_ sensitivity: SearchSensitivity) {
        if applySetting(\.searchSensitivity, sensitivity, save: configService.updateSearchSensitivity) {
            panel?.session.refreshResults()
        }
    }

    func updateFallbacks(_ change: (inout FallbackConfig) -> Void) {
        var next = fallbacks
        change(&next)
        if applySetting(\.fallbacks, next, save: configService.updateFallbacks) {
            panel?.session.refreshResults()
        }
    }

    func updateFileSearch(_ change: (inout FileSearchConfig) -> Void) {
        var next = fileSearch
        change(&next)
        _ = applySetting(\.fileSearch, next, save: configService.updateFileSearch)
    }

    func setCheckForUpdates(_ enabled: Bool) {
        _ = applySetting(\.checkForUpdates, enabled, save: configService.updateCheckForUpdates)
    }

    func updateQuicklinkSiteIcons(_ enabled: Bool) {
        if applySetting(\.quicklinkSiteIcons, enabled, save: configService.updateQuicklinkSiteIcons) {
            panel?.session.refreshResults()
        }
    }

    func setClipboardPaused(_ paused: Bool) {
        var configuration = configService.current.clipboard
        configuration.isPaused = paused
        updateClipboard(configuration)
    }

    func setSnippetExpansionEnabled(_ enabled: Bool) {
        var next = snippetExpansion
        next.isEnabled = enabled
        updateSnippetExpansion(next)
    }

    func setSnippetExpansionExcludedBundleIdentifiers(_ value: String) {
        var next = snippetExpansion
        next.excludedBundleIdentifiers = value.split(separator: ",").map(String.init)
        updateSnippetExpansion(next)
    }

    func setSnippetExpansionDelimiter(_ delimiter: String, enabled: Bool) {
        var next = snippetExpansion
        let affected = delimiter == "\n" ? ["\n", "\r"] : [delimiter]
        if enabled {
            for value in affected where next.delimiters.contains(value) == false { next.delimiters.append(value) }
        } else {
            next.delimiters.removeAll { affected.contains($0) }
        }
        updateSnippetExpansion(next)
    }

    func setSnippetInsertAsPrimary(_ insert: Bool) {
        var next = snippetExpansion
        next.insertAsPrimary = insert
        updateSnippetExpansion(next)
    }

    func requestSnippetExpansionAccessibility() { shell?.requestSnippetAccessibility() }

    func openSnippetExpansionPrivacySettings() { shell?.openSnippetPrivacySettings() }

    func setSnippetExpansionError(_ message: String?) { snippetExpansionError = message }

    func setDirectPasteError(_ error: Error) {
        panel?.showActionFeedback(.failure(String(localized: "Couldn't paste: \(error.localizedDescription)")))
        diagnostics.log("Direct paste failed: \(error.localizedDescription)")
    }

    func updateSnippetExpansion(_ next: SnippetExpansionConfig) {
        if applySetting(\.snippetExpansion, next.normalized, save: configService.updateSnippetExpansionConfig) {
            shell?.snippetExpansionChanged()
        }
    }

    func setClipboardRetention(maxItems: Int, maxBytes: Int, maxAgeDays: Int? = nil) {
        var configuration = configService.current.clipboard
        configuration.maxItems = maxItems
        configuration.maxBytes = maxBytes
        if let maxAgeDays { configuration.maxAgeDays = maxAgeDays }
        updateClipboard(configuration)
    }

    func setClipboardExcludedBundleIdentifiers(_ value: String) {
        var configuration = configService.current.clipboard
        configuration.excludedBundleIdentifiers = value.split(separator: ",").map(String.init)
        updateClipboard(configuration)
    }

    func updateClipboard(_ configuration: ClipboardConfig) {
        let previous = configService.current.clipboard
        do {
            try configService.updateClipboardConfig(configuration)
            panel?.clipboardHistory.updateConfiguration(configService.current.clipboard)
            settingsPersistenceError = nil
        } catch {
            panel?.clipboardHistory.updateConfiguration(previous)
            showSettingsPersistenceError(error)
        }
    }

    func setCommandFavorite(_ isFavorite: Bool, for commandID: String) {
        var preference = commandPreference(for: commandID)
        preference.favoriteRank = isFavorite ? nextFavoriteRank() : nil
        updateCommandPreference(preference, for: commandID)
    }

    @discardableResult
    func toggleFavorite(commandID: String) -> Bool {
        let nowFavorite = commandPreferences[commandID]?.favoriteRank == nil
        setCommandFavorite(nowFavorite, for: commandID)
        return nowFavorite
    }

    func setCommandAliases(_ rawAliases: String, for commandID: String) {
        var preference = commandPreference(for: commandID)
        preference.aliases = Self.normalizedCommandAliases(rawAliases)
        updateCommandPreference(preference, for: commandID)
    }

    /// Who already owns a chord: `"launcher"` for the main hotkey, or the
    /// commandID holding it. Used to hide suggestions that would collide.
    func commandHotkeyOwner(keyCode: UInt32, modifiers: UInt32, excluding commandID: String? = nil) -> String? {
        if hotkey.keyCode == keyCode, hotkey.modifiers == modifiers {
            return "launcher"
        }
        for (id, preference) in commandPreferences where id != commandID {
            if let existing = preference.globalHotkey,
               existing.keyCode == keyCode, existing.modifiers == modifiers {
                return id
            }
        }
        return nil
    }

    /// Why a command's shortcut is not active, keyed by command ID — shown under its recorder.
    private(set) var commandHotkeyIssues: [String: String] = [:]

    func setUnavailableCommandHotkeys(_ commandIDs: [String]) {
        commandHotkeyIssues = Dictionary(uniqueKeysWithValues: commandIDs.map {
            ($0, String(localized: "macOS or another app already uses this shortcut, so it is off."))
        })
    }

    /// Launchers Foundry moved off ⌘ Space during setup, by name.
    private(set) var releasedLaunchers: [String] = []

    private static func launcherNames(_ ids: [String]) -> [String] {
        LauncherRival.all.filter { ids.contains($0.id) }.map(\.name)
    }

    /// Hands ⌘ Space back to each launcher Foundry moved off it, and moves Foundry to ⌥ Space.
    func giveCommandSpaceBack(rivals: [LauncherRival] = LauncherRival.all, localState: LocalStateStore = .shared) async {
        let released = localState.get(\.releasedLaunchers)
        var kept: [String] = []
        for rival in rivals where released.contains(rival.id) {
            if await rival.restore() == false { kept.append(rival.id) }
        }
        localState.set(\.releasedLaunchers, kept)
        releasedLaunchers = Self.launcherNames(kept)
        if kept.count < released.count, hotkey == .commandSpace { setHotkey(.optionSpace) }
        if kept.isEmpty == false {
            settingsPersistenceError = String(localized: "Foundry could not give ⌘ Space back to every launcher. Set it in that app's settings.")
        }
    }

    func setCommandHotkey(_ hotkey: FoundryHotkey?, for commandID: String) {
        if let hotkey, let owner = commandHotkeyOwner(keyCode: hotkey.keyCode, modifiers: hotkey.modifiers, excluding: commandID) {
            let name = owner == "launcher" ? String(localized: "the launcher") : commandRows.first { $0.id == owner }?.title ?? owner
            commandHotkeyIssues[commandID] = String(localized: "\(hotkey.displayName) is already used by \(name).")
            return
        }
        commandHotkeyIssues[commandID] = nil
        var preference = commandPreference(for: commandID)
        preference.globalHotkey = hotkey.map {
            CommandHotkey(keyCode: $0.keyCode, modifiers: $0.modifiers, displayName: $0.displayName)
        }
        updateCommandPreference(preference, for: commandID)
    }

    @discardableResult
    func applySuggestedWindowHotkeys() -> Int {
        var applied = 0
        for (placement, hotkey) in WindowHotkeySuggestions.all {
            let id = WindowHotkeySuggestions.commandID(for: placement)
            guard commandPreference(for: id).globalHotkey == nil,
                  commandHotkeyOwner(keyCode: hotkey.keyCode, modifiers: hotkey.modifiers) == nil else { continue }
            setCommandHotkey(hotkey, for: id)
            applied += 1
        }
        return applied
    }

    func setCommandFallbackEligible(_ isEligible: Bool, for commandID: String) {
        var preference = commandPreference(for: commandID)
        preference.fallbackEligible = isEligible
        updateCommandPreference(preference, for: commandID)
    }

    func resetCommandPreference(for commandID: String) {
        updateCommandPreference(CommandPreference(), for: commandID)
    }

    static func normalizedCommandAliases(_ value: String) -> [String] {
        var seen = Set<String>()
        var aliases: [String] = []
        for component in value.split(separator: ",") {
            let alias = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard alias.isEmpty == false else { continue }
            guard seen.insert(alias.lowercased()).inserted else { continue }
            aliases.append(String(alias))
            if aliases.count == 8 { break }
        }
        return aliases
    }

    func nextFavoriteRank() -> Int {
        (commandPreferences.values.compactMap(\.favoriteRank).max() ?? -1) + 1
    }

    func updateCommandPreference(_ preference: CommandPreference, for commandID: String) {
        let previous = commandPreferences[commandID]
        commandPreferences[commandID] = preference
        rebuildCommandRows()
        do {
            try configService.updateCommandPreference(preference, for: commandID)
            settingsPersistenceError = nil
            shell?.commandPreferencesChanged()
        } catch {
            if let previous {
                commandPreferences[commandID] = previous
            } else {
                commandPreferences.removeValue(forKey: commandID)
            }
            rebuildCommandRows()
            showSettingsPersistenceError(error)
        }
        panel?.session.refreshFavorites()
    }
}

private struct ConfigSaveFailure: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}
