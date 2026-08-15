import Foundation
import FoundryDomain
import FoundryServices

final class SystemCommandProvider: CommandProvider, @unchecked Sendable {
    let id = "foundry.system"

    private let commands: [SystemCommand]

    init(diagnostics: DiagnosticsService) {
        self.commands = Self.systemCommands(includeRebuild: SourceRootLocator.locate() != nil)
    }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        commands.compactMap { command in
            guard Task.isCancelled == false else { return nil }
            let aliases = request.customAliases[command.id] ?? []
            guard SearchScoring.match(
                query: request.query,
                title: command.title,
                subtitle: command.subtitle,
                keywords: [],
                aliases: command.aliases + aliases,
                sensitivity: request.sensitivity
            ) != nil else {
                return nil
            }

            return CommandResult(
                id: command.id,
                title: command.title,
                subtitle: command.subtitle,
                icon: CommandIcon(fallback: command.fallback, systemName: command.systemIcon),
                searchAliases: aliases,
                searchKeywords: command.aliases,
                primaryAction: CommandAction(id: "\(command.id).perform", title: command.actionTitle, kind: command.actionKind),
                secondaryActions: []
            )
        }
    }

    private static func systemCommands(includeRebuild: Bool) -> [SystemCommand] {
        var commands = [
            SystemCommand(
                id: "system.lock-screen",
                title: "Lock Screen",
                subtitle: "Secure this Mac immediately",
                aliases: ["lock", "secure", "login window"],
                systemIcon: "lock.fill",
                fallback: "LK",
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
            settingsCommand(
                id: "system.settings.wifi",
                title: "Open Wi-Fi Settings",
                subtitle: "Join and manage wireless networks",
                aliases: ["wifi", "wi-fi", "wireless", "wireless network"],
                systemIcon: "wifi",
                fallback: "WF",
                url: "x-apple.systempreferences:com.apple.wifi-settings.extension"
            ),
            settingsCommand(
                id: "system.settings.bluetooth",
                title: "Open Bluetooth Settings",
                subtitle: "Connect and manage Bluetooth devices",
                aliases: ["bluetooth", "bluetooth devices", "wireless devices"],
                systemIcon: "wave.3.right",
                fallback: "BT",
                url: "x-apple.systempreferences:com.apple.BluetoothSettings"
            ),
            settingsCommand(
                id: "system.settings.network",
                title: "Open Network Settings",
                subtitle: "Configure network connections and services",
                aliases: ["network", "ethernet", "internet", "connections"],
                systemIcon: "network",
                fallback: "NW",
                url: "x-apple.systempreferences:com.apple.Network-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.vpn",
                title: "Open VPN Settings",
                subtitle: "Manage VPN configurations",
                aliases: ["vpn", "virtual private network"],
                systemIcon: "lock.shield.fill",
                fallback: "VP",
                url: "x-apple.systempreferences:com.apple.Network-Settings.extension?path=VPN"
            ),
            settingsCommand(
                id: "system.settings.storage",
                title: "Open Storage Settings",
                subtitle: "Review disk usage and storage recommendations",
                aliases: ["storage", "disk space", "free space", "manage storage", "hard drive"],
                systemIcon: "internaldrive.fill",
                fallback: "ST",
                url: "x-apple.systempreferences:com.apple.settings.Storage"
            ),
            settingsCommand(
                id: "system.settings.battery",
                title: "Open Battery Settings",
                subtitle: "Battery health, usage, and power options",
                aliases: ["battery", "power", "low power mode", "battery health"],
                systemIcon: "battery.100percent",
                fallback: "BA",
                url: "x-apple.systempreferences:com.apple.Battery-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.general",
                title: "Open General Settings",
                subtitle: "System-wide macOS preferences",
                aliases: ["general", "about this mac", "software update", "airdrop", "handoff"],
                systemIcon: "gearshape.2.fill",
                fallback: "GE",
                url: "x-apple.systempreferences:com.apple.General-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.appearance",
                title: "Open Appearance Settings",
                subtitle: "Choose Light, Dark, or accent appearance",
                aliases: ["appearance", "light mode", "dark mode", "accent color"],
                systemIcon: "circle.lefthalf.filled",
                fallback: "AP",
                url: "x-apple.systempreferences:com.apple.Appearance-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.desktop-dock",
                title: "Open Desktop & Dock Settings",
                subtitle: "Customize the desktop, Dock, and menu bar",
                aliases: ["desktop", "dock", "menu bar", "desktop and dock"],
                systemIcon: "dock.rectangle",
                fallback: "DD",
                url: "x-apple.systempreferences:com.apple.Desktop-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.wallpaper",
                title: "Open Wallpaper Settings",
                subtitle: "Choose your desktop wallpaper",
                aliases: ["wallpaper", "desktop picture", "desktop background", "background"],
                systemIcon: "photo.fill",
                fallback: "WP",
                url: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.screen-saver",
                title: "Open Screen Saver Settings",
                subtitle: "Choose and configure the screen saver",
                aliases: ["screen saver", "screensaver"],
                systemIcon: "sparkles.rectangle.stack.fill",
                fallback: "SS",
                url: "x-apple.systempreferences:com.apple.Screen-Saver-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.notifications",
                title: "Open Notifications Settings",
                subtitle: "Control alerts and notification delivery",
                aliases: ["notifications", "alerts", "notification center"],
                systemIcon: "bell.badge.fill",
                fallback: "NO",
                url: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.focus",
                title: "Open Focus Settings",
                subtitle: "Manage Focus modes and schedules",
                aliases: ["focus", "do not disturb", "dnd", "focus mode"],
                systemIcon: "moon.fill",
                fallback: "FO",
                url: "x-apple.systempreferences:com.apple.Focus-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.siri",
                title: "Open Siri & Spotlight Settings",
                subtitle: "Configure Siri, search, and Spotlight",
                aliases: ["siri", "spotlight", "search", "siri and spotlight"],
                systemIcon: "sparkles",
                fallback: "SI",
                url: "x-apple.systempreferences:com.apple.Siri-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.control-center",
                title: "Open Control Center Settings",
                subtitle: "Choose what appears in the menu bar and Control Center",
                aliases: ["control center", "menu bar controls"],
                systemIcon: "switch.2",
                fallback: "CT",
                url: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.lock-screen",
                title: "Open Lock Screen Settings",
                subtitle: "Configure login, sleep, and lock screen behavior",
                aliases: ["lock screen", "login screen", "screen lock"],
                systemIcon: "lock.fill",
                fallback: "LS",
                url: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.touch-id",
                title: "Open Touch ID & Password Settings",
                subtitle: "Manage fingerprints and password requirements",
                aliases: ["touch id", "fingerprint", "password", "touchid"],
                systemIcon: "touchid",
                fallback: "TI",
                url: "x-apple.systempreferences:com.apple.Touch-ID-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.users-groups",
                title: "Open Users & Groups Settings",
                subtitle: "Manage users, groups, and account permissions",
                aliases: ["users", "groups", "accounts", "user accounts"],
                systemIcon: "person.2.fill",
                fallback: "UG",
                url: "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.internet-accounts",
                title: "Open Internet Accounts Settings",
                subtitle: "Manage mail, calendar, and online accounts",
                aliases: ["internet accounts", "mail accounts", "calendar accounts", "online accounts"],
                systemIcon: "person.crop.circle.badge.checkmark",
                fallback: "IA",
                url: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.screen-time",
                title: "Open Screen Time Settings",
                subtitle: "Review usage and app limits",
                aliases: ["screen time", "app limits", "usage limits", "parental controls"],
                systemIcon: "hourglass",
                fallback: "ST",
                url: "x-apple.systempreferences:com.apple.Screen-Time-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.family",
                title: "Open Family Settings",
                subtitle: "Manage Family Sharing and family members",
                aliases: ["family", "family sharing", "family members"],
                systemIcon: "person.3.fill",
                fallback: "FM",
                url: "x-apple.systempreferences:com.apple.Family-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.game-center",
                title: "Open Game Center Settings",
                subtitle: "Manage Game Center account and activity",
                aliases: ["game center", "games", "gaming account"],
                systemIcon: "gamecontroller.fill",
                fallback: "GC",
                url: "x-apple.systempreferences:com.apple.Game-Center-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.wallet",
                title: "Open Wallet & Apple Pay Settings",
                subtitle: "Manage cards and Apple Pay preferences",
                aliases: ["wallet", "apple pay", "cards", "apple wallet"],
                systemIcon: "wallet.pass.fill",
                fallback: "WA",
                url: "x-apple.systempreferences:com.apple.Wallet-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.passwords",
                title: "Open Passwords Settings",
                subtitle: "Manage saved passwords and passkeys",
                aliases: ["passwords", "passkeys", "password manager", "saved passwords"],
                systemIcon: "key.fill",
                fallback: "PW",
                url: "x-apple.systempreferences:com.apple.Passwords-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.mouse",
                title: "Open Mouse Settings",
                subtitle: "Configure mouse tracking, scrolling, and gestures",
                aliases: ["mouse", "mouse settings", "mouse tracking"],
                systemIcon: "computermouse.fill",
                fallback: "MO",
                url: "x-apple.systempreferences:com.apple.Mouse-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.trackpad",
                title: "Open Trackpad Settings",
                subtitle: "Configure trackpad gestures and pointing",
                aliases: ["trackpad", "gesture", "gestures", "touchpad"],
                systemIcon: "rectangle.and.hand.point.up.left.fill",
                fallback: "TP",
                url: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.printers-scanners",
                title: "Open Printers & Scanners Settings",
                subtitle: "Add and manage printers, scanners, and fax devices",
                aliases: ["printers", "scanners", "printer", "scanner", "print"],
                systemIcon: "printer.fill",
                fallback: "PS",
                url: "x-apple.systempreferences:com.apple.Print-Scan-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.game-controllers",
                title: "Open Game Controllers Settings",
                subtitle: "Connect and configure game controllers",
                aliases: ["game controller", "game controllers", "controller", "gamepad"],
                systemIcon: "gamecontroller.fill",
                fallback: "GC",
                url: "x-apple.systempreferences:com.apple.Game-Controller-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.date-time",
                title: "Open Date & Time Settings",
                subtitle: "Configure time zone, clock, and date formats",
                aliases: ["date", "time", "clock", "time zone", "date and time"],
                systemIcon: "clock.fill",
                fallback: "DT",
                url: "x-apple.systempreferences:com.apple.Date-Time-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.language-region",
                title: "Open Language & Region Settings",
                subtitle: "Choose language, region, calendar, and formats",
                aliases: ["language", "region", "locale", "keyboard language", "language and region"],
                systemIcon: "globe",
                fallback: "LR",
                url: "x-apple.systempreferences:com.apple.Localization-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.sharing",
                title: "Open Sharing Settings",
                subtitle: "Manage services shared from this Mac",
                aliases: ["sharing", "file sharing", "screen sharing", "remote login"],
                systemIcon: "square.and.arrow.up.fill",
                fallback: "SH",
                url: "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.extensions",
                title: "Open Extensions Settings",
                subtitle: "Manage app, Finder, and sharing extensions",
                aliases: ["extensions", "app extensions", "finder extensions", "share extensions"],
                systemIcon: "puzzlepiece.extension.fill",
                fallback: "EX",
                url: "x-apple.systempreferences:com.apple.Extensions-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.profiles",
                title: "Open Profiles Settings",
                subtitle: "Review installed configuration profiles",
                aliases: ["profiles", "configuration profiles", "device management"],
                systemIcon: "person.text.rectangle.fill",
                fallback: "PF",
                url: "x-apple.systempreferences:com.apple.Profiles-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.time-machine",
                title: "Open Time Machine Settings",
                subtitle: "Configure backups and backup disks",
                aliases: ["time machine", "backup", "backups"],
                systemIcon: "clock.arrow.circlepath",
                fallback: "TM",
                url: "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.software-update",
                title: "Open Software Update Settings",
                subtitle: "Check for macOS and system updates",
                aliases: ["software update", "updates", "macos update", "system update"],
                systemIcon: "arrow.down.circle.fill",
                fallback: "SU",
                url: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
            ),
            settingsCommand(
                id: "system.settings.transfer-reset",
                title: "Open Transfer or Reset Settings",
                subtitle: "Transfer data or reset this Mac",
                aliases: ["transfer", "reset mac", "erase mac", "migration", "transfer or reset"],
                systemIcon: "arrow.triangle.2.circlepath",
                fallback: "TR",
                url: "x-apple.systempreferences:com.apple.Transfer-Reset-Settings.extension"
            ),
            SystemCommand(
                id: "system.empty-trash",
                title: "Empty Trash",
                subtitle: "Ask Finder to empty the Trash",
                aliases: ["trash", "bin", "delete trash"],
                systemIcon: "trash.fill",
                fallback: "TR",
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
                actionTitle: "Open",
                actionKind: .openApp(path: "/System/Applications/Utilities/Console.app", name: "Console")
            ),
        ]
        if includeRebuild {
            commands.append(SystemCommand(
                id: "system.rebuild-app",
                title: "Rebuild Foundry App",
                subtitle: "Build and sign a fresh Foundry.app bundle",
                aliases: ["rebuild app", "build app", "package app", "sign app", "rebuild foundry"],
                systemIcon: "hammer.fill",
                fallback: "BA",
                actionTitle: "Rebuild",
                actionKind: .rebuildApp
            ))
        }
        return commands
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
    let actionTitle: String
    let actionKind: CommandActionKind
}
