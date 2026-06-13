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
