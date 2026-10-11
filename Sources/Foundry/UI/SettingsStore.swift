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
    var hotkey: FoundryHotkey = .optionSpace
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
        commandPreferences = config.commandPreferences
        configLoadError = configService.loadErrorMessage
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
                hotkeyError = "That shortcut is unavailable. Choose another key combination."
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
            launchAtLoginError = "Could not update launch at login: \(error.localizedDescription)"
            diagnostics.log("Launch at login update failed: \(error.localizedDescription)")
        }
    }

    func setMainBrowser(_ browser: BrowserSource) {
        if applySetting(\.mainBrowser, browser, save: { browser in
            try configService.updateLocalState { $0.mainBrowser = browser?.rawValue }
        }), browser == .firefox {
            FirefoxConnectorInstaller(diagnostics: diagnostics).requestFirefoxConnector()
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
        settingsPersistenceError = "Preferences could not be saved. Your previous settings were kept."
        diagnostics.log("Settings persistence failed: \(error.localizedDescription)")
    }

    func resetConfiguration() {
        do {
            try configService.resetToDefaults()
            configLoadError = nil
            NSApp.terminate(nil)
        } catch {
            settingsPersistenceError = "Could not reset Foundry settings. Your existing configuration was kept."
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
            settingsPersistenceError = "Could not save the backup: \(error.localizedDescription)"
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
            panel?.showActionFeedback(.success("Backup imported"))
        } catch {
            settingsPersistenceError = "Could not import the backup. Your previous files are kept as .pre-import copies."
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
            ?? CommandPreference(isEnabled: CommandRegistry.defaultDisabledCommandIDs.contains(commandID) == false)
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

    func setClipboardPaused(_ paused: Bool) {
        var configuration = configService.current.clipboard
        configuration.isPaused = paused
        updateClipboard(configuration)
    }

    func setClipboardEnabled(_ enabled: Bool) {
        var configuration = configService.current.clipboard
        configuration.isEnabled = enabled
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
        panel?.showActionFeedback(.failure("Couldn't paste: \(error.localizedDescription)"))
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

    func setCommandHotkey(_ hotkey: FoundryHotkey?, for commandID: String) {
        var preference = commandPreference(for: commandID)
        preference.globalHotkey = hotkey.map {
            CommandHotkey(keyCode: $0.keyCode, modifiers: $0.modifiers, displayName: $0.displayName)
        }
        updateCommandPreference(preference, for: commandID)
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
