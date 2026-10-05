import Foundation

struct SettingItem: Identifiable, Equatable {
    let title: String
    let keywords: [String]
    let pane: SettingsCategory
    let anchorID: String

    var id: String { "\(anchorID).\(title)" }
}

enum SettingsSearch {
    static let items: [SettingItem] = [
        SettingItem(title: "Global shortcut", keywords: ["hotkey", "keyboard", "option space", "command space", "spotlight"], pane: .general, anchorID: "general.hotkey"),
        SettingItem(title: "Show in menu bar", keywords: ["menubar", "status item", "icon"], pane: .general, anchorID: "general.system"),
        SettingItem(title: "Launch at login", keywords: ["startup", "login item", "open at login"], pane: .general, anchorID: "general.system"),
        SettingItem(title: "Main browser", keywords: ["safari", "chrome", "arc", "brave", "firefox", "tabs", "history"], pane: .general, anchorID: "general.system"),
        SettingItem(title: "Pop to root", keywords: ["reset", "restore", "reopen", "remember mode"], pane: .general, anchorID: "general.popToRoot"),
        SettingItem(title: "Compact panel", keywords: ["compact", "window mode", "size", "search bar only"], pane: .general, anchorID: "general.compact"),
        SettingItem(title: "Search sensitivity", keywords: ["fuzzy", "matching", "results"], pane: .general, anchorID: "general.sensitivity"),
        SettingItem(title: "Snippet expansion", keywords: ["snippets", "keywords", "text expansion", "accessibility", "excluded apps"], pane: .general, anchorID: "general.snippets"),
        SettingItem(title: "Panel contrast", keywords: ["theme", "transparency", "glass", "intensity", "appearance"], pane: .appearance, anchorID: "appearance.contrast"),
        SettingItem(title: "Commands", keywords: ["aliases", "hotkeys", "favorites", "enable", "disable", "fallback"], pane: .commands, anchorID: "commands.list"),
        SettingItem(title: "Quicklinks", keywords: ["links", "bookmarks", "search engines", "url", "raycast import", "keyword"], pane: .quicklinks, anchorID: "quicklinks.list"),
        SettingItem(title: "Script folders", keywords: ["scripts", "script commands", "raycast", "bash", "trust", "shell"], pane: .scripts, anchorID: "scripts.folders"),
        SettingItem(title: "Agent event socket", keywords: ["agents", "claude", "codex", "hooks", "observation"], pane: .agents, anchorID: "agents.socket"),
        SettingItem(title: "Provider bridges", keywords: ["agents", "install", "integration", "plugin"], pane: .agents, anchorID: "agents.bridges"),
        SettingItem(title: "AI provider", keywords: ["model", "api key", "openai", "anthropic", "ollama", "chatgpt", "quick ai"], pane: .ai, anchorID: "ai.provider"),
        SettingItem(title: "Home widgets", keywords: ["widgets", "strip", "weather", "stock", "cpu", "memory", "disk"], pane: .widgets, anchorID: "widgets.strip"),
        SettingItem(title: "Pause clipboard capture", keywords: ["clipboard", "history", "pause"], pane: .clipboard, anchorID: "clipboard.history"),
        SettingItem(title: "Clipboard retention", keywords: ["clipboard", "retain", "limit", "items", "history size"], pane: .clipboard, anchorID: "clipboard.history"),
        SettingItem(title: "Clipboard excluded apps", keywords: ["clipboard", "privacy", "password", "ignore"], pane: .clipboard, anchorID: "clipboard.history"),
        SettingItem(title: "Config folder", keywords: ["json", "file", "reveal", "configuration"], pane: .advanced, anchorID: "advanced.config"),
        SettingItem(title: "Backup and import", keywords: ["export", "import", "backup", "restore", "transfer", "migrate"], pane: .advanced, anchorID: "advanced.backup"),
        SettingItem(title: "Reset settings", keywords: ["defaults", "restore", "configuration"], pane: .advanced, anchorID: "advanced.reset"),
        SettingItem(title: "Version", keywords: ["about", "build", "update"], pane: .about, anchorID: "about.version")
    ]

    static func matches(_ query: String) -> [SettingItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.isEmpty == false else { return [] }
        return items.filter { item in
            ([item.title, item.pane.title] + item.keywords).contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }
}
