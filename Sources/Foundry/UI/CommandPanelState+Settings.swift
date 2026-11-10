import AppKit
import Foundation
import SwiftUI
import FoundryDomain
import FoundryServices

// Backup-restore re-mirroring — panel-side orchestration around
// `SettingsStore`.
extension CommandPanelState {

    /// Re-mirrors every config-driven surface after a restore — no restart.
    func applyRestoredConfiguration() {
        let config = configService.current
        settings.apply(config: config)
        clipboardHistory.updateConfiguration(config.clipboard)
        snippets.load()
        widgetBoard.reload()
        QuicklinkStore.shared.reload()
        registry.reloadUsage()
        aiSettings.reloadFromConfig()
        settings.rebuildCommandRows()
        session.refreshFavorites()
        session.refreshResults()
        shell?.commandPreferencesChanged()
        shell?.snippetExpansionChanged()
        shell?.menuBarIconVisibilityChanged(config.showMenuBarIcon)
        do {
            try shell?.hotkeyChanged(config.hotkey)
        } catch {
            diagnostics.log("Failed to register restored hotkey: \(error.localizedDescription)")
            settings.setLauncherHotkeyFailed(true)
        }
    }
}
