import Foundation

final class SystemCommandProvider: CommandProvider, @unchecked Sendable {
    let id = "foundry.system"

    private let commands: [SystemCommand]

    init(diagnostics: DiagnosticsService) {
        self.commands = Self.systemCommands()
    }

    func results(matching query: String) async -> [CommandResult] {
        commands.compactMap { command in
            guard Task.isCancelled == false else { return nil }
            guard let score = SearchScoring.score(query: query, title: command.title, aliases: command.aliases) else {
                return nil
            }

            return CommandResult(
                id: command.id,
                title: command.title,
                subtitle: command.subtitle,
                icon: CommandIcon(fallback: command.fallback, systemName: command.systemIcon),
                score: score + command.scoreBoost,
                primaryAction: CommandAction(id: "\(command.id).perform", title: command.actionTitle, kind: command.actionKind),
                secondaryActions: []
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
            return lhs.score > rhs.score
        }
    }

    private static func systemCommands() -> [SystemCommand] {
        [
            SystemCommand(
                id: "system.lock-screen",
                title: "Lock Screen",
                subtitle: "Secure this Mac immediately",
                aliases: ["lock", "secure", "login window"],
                systemIcon: "lock.fill",
                fallback: "LK",
                scoreBoost: 3,
                actionTitle: "Lock",
                actionKind: .runProcess(path: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession", arguments: ["-suspend"])
            ),
            SystemCommand(
                id: "system.sleep",
                title: "Sleep Mac",
                subtitle: "Put this Mac to sleep",
                aliases: ["sleep", "suspend"],
                systemIcon: "moon.fill",
                fallback: "SL",
                scoreBoost: 2,
                actionTitle: "Sleep",
                actionKind: .runProcess(path: "/usr/bin/pmset", arguments: ["sleepnow"])
            ),
            SystemCommand(
                id: "system.sleep-displays",
                title: "Sleep Displays",
                subtitle: "Turn off connected displays without sleeping the Mac",
                aliases: ["display sleep", "screen sleep", "turn off screen", "turn off display", "monitor sleep"],
                systemIcon: "display.2",
                fallback: "DS",
                scoreBoost: 2,
                actionTitle: "Sleep Displays",
                actionKind: .runProcess(path: "/usr/bin/pmset", arguments: ["displaysleepnow"])
            ),
            SystemCommand(
                id: "system.restart",
                title: "Restart Mac",
                subtitle: "Restart macOS",
                aliases: ["restart", "reboot", "relaunch mac", "restart computer"],
                systemIcon: "arrow.clockwise.circle.fill",
                fallback: "RE",
                scoreBoost: 3,
                actionTitle: "Restart",
                actionKind: .runProcess(path: "/usr/bin/osascript", arguments: ["-e", "tell application \"System Events\" to restart"])
            ),
            SystemCommand(
                id: "system.shutdown",
                title: "Shut Down Mac",
                subtitle: "Shut down macOS",
                aliases: ["shutdown", "shut down", "power off", "turn off mac", "power down"],
                systemIcon: "power.circle.fill",
                fallback: "SD",
                scoreBoost: 3,
                actionTitle: "Shut Down",
                actionKind: .runProcess(path: "/usr/bin/osascript", arguments: ["-e", "tell application \"System Events\" to shut down"])
            ),
            SystemCommand(
                id: "system.logout",
                title: "Log Out",
                subtitle: "Sign out of the current macOS user",
                aliases: ["logout", "log out", "sign out", "signoff", "end session"],
                systemIcon: "rectangle.portrait.and.arrow.right",
                fallback: "LO",
                scoreBoost: 2,
                actionTitle: "Log Out",
                actionKind: .runProcess(path: "/usr/bin/osascript", arguments: ["-e", "tell application \"System Events\" to log out"])
            ),
            SystemCommand(
                id: "system.restart-finder",
                title: "Restart Finder",
                subtitle: "Refresh Finder without restarting the Mac",
                aliases: ["restart finder", "refresh finder", "reload finder"],
                systemIcon: "folder.fill.badge.gearshape",
                fallback: "RF",
                scoreBoost: 2,
                actionTitle: "Restart",
                actionKind: .runProcess(path: "/usr/bin/killall", arguments: ["Finder"])
            ),
            SystemCommand(
                id: "system.restart-dock",
                title: "Restart Dock",
                subtitle: "Refresh the macOS Dock",
                aliases: ["restart dock", "refresh dock", "reload dock"],
                systemIcon: "dock.rectangle",
                fallback: "RD",
                scoreBoost: 1,
                actionTitle: "Restart",
                actionKind: .runProcess(path: "/usr/bin/killall", arguments: ["Dock"])
            ),
            SystemCommand(
                id: "system.restart-menu-bar",
                title: "Restart Menu Bar",
                subtitle: "Refresh the macOS menu bar services",
                aliases: ["restart menubar", "restart menu bar", "refresh menu bar", "restart systemuiserver"],
                systemIcon: "menubar.rectangle",
                fallback: "MB",
                scoreBoost: 1,
                actionTitle: "Restart",
                actionKind: .runProcess(path: "/usr/bin/killall", arguments: ["SystemUIServer"])
            ),
            SystemCommand(
                id: "system.flush-dns",
                title: "Flush DNS Cache",
                subtitle: "Refresh macOS DNS resolver caches",
                aliases: ["flush dns", "clear dns", "reset dns", "dns cache"],
                systemIcon: "network.badge.shield.half.filled",
                fallback: "DNS",
                scoreBoost: 2,
                actionTitle: "Flush",
                actionKind: .runProcess(path: "/bin/zsh", arguments: ["-lc", "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder"])
            ),
            SystemCommand(
                id: "system.toggle-dark-mode",
                title: "Toggle Dark Mode",
                subtitle: "Switch between Light and Dark appearance",
                aliases: ["dark mode", "light mode", "appearance", "toggle dark"],
                systemIcon: "circle.lefthalf.filled",
                fallback: "DM",
                scoreBoost: 2,
                actionTitle: "Toggle",
                actionKind: .runProcess(path: "/usr/bin/osascript", arguments: ["-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"])
            ),
            SystemCommand(
                id: "system.toggle-hidden-files",
                title: "Toggle Hidden Files",
                subtitle: "Show or hide dotfiles in Finder",
                aliases: ["hidden files", "show hidden files", "dotfiles", "finder hidden"],
                systemIcon: "eye.slash.fill",
                fallback: "HF",
                scoreBoost: 2,
                actionTitle: "Toggle",
                actionKind: .runProcess(path: "/bin/zsh", arguments: ["-lc", "/usr/bin/defaults write com.apple.finder AppleShowAllFiles -bool $(/usr/bin/defaults read com.apple.finder AppleShowAllFiles 2>/dev/null | /usr/bin/grep -q true && printf false || printf true); /usr/bin/killall Finder"])
            ),
            SystemCommand(
                id: "system.mute-audio",
                title: "Toggle Audio Mute",
                subtitle: "Mute or unmute the Mac's output audio",
                aliases: ["mute", "unmute", "mute volume", "sound mute"],
                systemIcon: "speaker.slash.fill",
                fallback: "MU",
                scoreBoost: 2,
                actionTitle: "Toggle",
                actionKind: .runProcess(path: "/usr/bin/osascript", arguments: ["-e", "set volume output muted not (output muted of (get volume settings))"])
            ),
            SystemCommand(
                id: "system.volume-up",
                title: "Increase Volume",
                subtitle: "Raise output volume by one step",
                aliases: ["volume up", "louder", "increase volume", "turn it up"],
                systemIcon: "speaker.wave.3.fill",
                fallback: "VU",
                scoreBoost: 1,
                actionTitle: "Increase",
                actionKind: .runProcess(path: "/usr/bin/osascript", arguments: ["-e", "set volume output volume ((output volume of (get volume settings)) + 6)"])
            ),
            SystemCommand(
                id: "system.volume-down",
                title: "Decrease Volume",
                subtitle: "Lower output volume by one step",
                aliases: ["volume down", "quieter", "decrease volume", "turn it down"],
                systemIcon: "speaker.wave.1.fill",
                fallback: "VD",
                scoreBoost: 1,
                actionTitle: "Decrease",
                actionKind: .runProcess(path: "/usr/bin/osascript", arguments: ["-e", "set volume output volume ((output volume of (get volume settings)) - 6)"])
            ),
            SystemCommand(
                id: "system.clear-clipboard",
                title: "Clear Clipboard",
                subtitle: "Remove the current contents of the clipboard",
                aliases: ["clear clipboard", "empty clipboard", "wipe clipboard", "clear pasteboard"],
                systemIcon: "clipboard.fill",
                fallback: "CC",
                scoreBoost: 1,
                actionTitle: "Clear",
                actionKind: .runProcess(path: "/usr/bin/pbcopy", arguments: [])
            ),
            SystemCommand(
                id: "system.eject-disks",
                title: "Eject External Disks",
                subtitle: "Eject mounted removable volumes",
                aliases: ["eject disks", "eject drives", "eject usb", "unmount disks"],
                systemIcon: "eject.fill",
                fallback: "EJ",
                scoreBoost: 1,
                actionTitle: "Eject",
                actionKind: .runProcess(path: "/usr/bin/osascript", arguments: ["-e", "tell application \"Finder\" to eject (every disk whose ejectable is true)"])
            ),
            SystemCommand(
                id: "system.screen-saver",
                title: "Start Screen Saver",
                subtitle: "Start the current screen saver",
                aliases: ["screensaver", "screen saver", "saver"],
                systemIcon: "sparkles.rectangle.stack.fill",
                fallback: "SS",
                scoreBoost: 1,
                actionTitle: "Start",
                actionKind: .openApp(path: "/System/Library/CoreServices/ScreenSaverEngine.app", name: "Screen Saver")
            ),
            settingsCommand(
                id: "system.settings",
                title: "Open System Settings",
                subtitle: "Open macOS System Settings",
                aliases: ["preferences", "prefs", "settings"],
                systemIcon: "gearshape.fill",
                fallback: "SE",
                url: "x-apple.systempreferences:"
            ),
            settingsCommand(
                id: "system.settings.accessibility",
                title: "Open Accessibility Settings",
                subtitle: "Review Accessibility permissions and controls",
                aliases: ["accessibility", "permissions", "privacy accessibility"],
                systemIcon: "figure.circle.fill",
                fallback: "AC",
                url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            ),
            settingsCommand(
                id: "system.settings.keyboard",
                title: "Open Keyboard Settings",
                subtitle: "Keyboard shortcuts, input sources, and text input",
                aliases: ["keyboard", "hotkey", "shortcuts"],
                systemIcon: "keyboard.fill",
                fallback: "KB",
                url: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.displays",
                title: "Open Displays Settings",
                subtitle: "Brightness, arrangement, and display options",
                aliases: ["display", "screen", "monitor", "brightness"],
                systemIcon: "display",
                fallback: "DP",
                url: "x-apple.systempreferences:com.apple.Displays-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.sound",
                title: "Open Sound Settings",
                subtitle: "Input, output, and alert audio",
                aliases: ["sound", "audio", "volume", "speaker", "microphone"],
                systemIcon: "speaker.wave.2.fill",
                fallback: "AU",
                url: "x-apple.systempreferences:com.apple.Sound-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.privacy",
                title: "Open Privacy & Security Settings",
                subtitle: "Permissions, security, and privacy controls",
                aliases: ["privacy", "security", "permissions"],
                systemIcon: "hand.raised.fill",
                fallback: "PR",
                url: "x-apple.systempreferences:com.apple.PrivacySecurity.extension"
            ),
            settingsCommand(
                id: "system.settings.login-items",
                title: "Open Login Items Settings",
                subtitle: "Choose which apps launch when you sign in",
                aliases: ["login items", "launch at login", "startup apps", "start on startup", "startup"],
                systemIcon: "arrow.turn.up.right",
                fallback: "LI",
                url: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
            ),
            SystemCommand(
                id: "system.empty-trash",
                title: "Empty Trash",
                subtitle: "Ask Finder to empty the Trash",
                aliases: ["trash", "bin", "delete trash"],
                systemIcon: "trash.fill",
                fallback: "TR",
                scoreBoost: 0,
                actionTitle: "Empty",
                actionKind: .runProcess(path: "/usr/bin/osascript", arguments: ["-e", "tell application \"Finder\" to empty trash"])
            ),
            SystemCommand(
                id: "system.open-screenshot",
                title: "Open Screenshot",
                subtitle: "Open macOS Screenshot controls",
                aliases: ["screenshot", "screen capture", "capture screen", "snipping tool"],
                systemIcon: "camera.viewfinder",
                fallback: "SC",
                scoreBoost: 1,
                actionTitle: "Open",
                actionKind: .openApp(path: "/System/Library/CoreServices/Applications/Screenshot.app", name: "Screenshot")
            ),
            SystemCommand(
                id: "system.open-disk-utility",
                title: "Open Disk Utility",
                subtitle: "Inspect, repair, and erase disks",
                aliases: ["disk utility", "disk management", "partition disk", "repair disk"],
                systemIcon: "internaldrive.fill",
                fallback: "DU",
                scoreBoost: 1,
                actionTitle: "Open",
                actionKind: .openApp(path: "/System/Applications/Utilities/Disk Utility.app", name: "Disk Utility")
            ),
            SystemCommand(
                id: "system.open-console",
                title: "Open Console",
                subtitle: "Inspect macOS logs and diagnostic messages",
                aliases: ["console", "system logs", "mac logs", "view logs"],
                systemIcon: "apple.terminal.fill",
                fallback: "CO",
                scoreBoost: 1,
                actionTitle: "Open",
                actionKind: .openApp(path: "/System/Applications/Utilities/Console.app", name: "Console")
            ),
            SystemCommand(
                id: "system.rebuild-app",
                title: "Rebuild Foundry App",
                subtitle: "Build and sign a fresh Foundry.app bundle",
                aliases: ["rebuild app", "build app", "package app", "sign app", "rebuild foundry"],
                systemIcon: "hammer.fill",
                fallback: "BA",
                scoreBoost: 2,
                actionTitle: "Rebuild",
                actionKind: .rebuildApp
            )
        ]
    }

    private static func settingsCommand(
        id: String,
        title: String,
        subtitle: String,
        aliases: [String],
        systemIcon: String,
        fallback: String,
        url: String
    ) -> SystemCommand {
        SystemCommand(
            id: id,
            title: title,
            subtitle: subtitle,
            aliases: aliases,
            systemIcon: systemIcon,
            fallback: fallback,
            scoreBoost: 1,
            actionTitle: "Open",
            actionKind: .openURL(url)
        )
    }
}

private struct SystemCommand: Sendable {
    let id: String
    let title: String
    let subtitle: String
    let aliases: [String]
    let systemIcon: String
    let fallback: String
    let scoreBoost: Double
    let actionTitle: String
    let actionKind: CommandActionKind
}
