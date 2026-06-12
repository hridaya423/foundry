import AppKit
import Foundation

final class SystemCommandProvider: CommandProvider {
    let id = "foundry.system"

    private let diagnostics: DiagnosticsService

    init(diagnostics: DiagnosticsService) {
        self.diagnostics = diagnostics
    }

    func results(matching query: String) -> [CommandResult] {
        systemCommands().compactMap { command in
            guard let score = SearchScoring.score(query: query, title: command.title, aliases: command.aliases) else {
                return nil
            }

            return CommandResult(
                id: command.id,
                title: command.title,
                subtitle: command.subtitle,
                icon: CommandIcon(fallback: command.fallback, systemName: command.systemIcon),
                score: score + command.scoreBoost,
                primaryAction: CommandAction(id: "\(command.id).perform", title: command.actionTitle) { [diagnostics] in
                    diagnostics.log("Running system command: \(command.title)")
                    command.perform(diagnostics)
                },
                secondaryActions: []
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
            return lhs.score > rhs.score
        }
    }

    private func systemCommands() -> [SystemCommand] {
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
                perform: { _ in runProcess("/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession", ["-suspend"]) }
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
                perform: { _ in runProcess("/usr/bin/pmset", ["sleepnow"]) }
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
                perform: { _ in openApplication(at: "/System/Library/CoreServices/ScreenSaverEngine.app") }
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
                perform: { _ in runProcess("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"]) }
            )
        ]
    }

    private func settingsCommand(
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
            perform: { diagnostics in
                guard let settingsURL = URL(string: url) else {
                    diagnostics.log("Invalid settings URL: \(url)")
                    return
                }
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(settingsURL)
                }
            }
        )
    }
}

private struct SystemCommand {
    let id: String
    let title: String
    let subtitle: String
    let aliases: [String]
    let systemIcon: String
    let fallback: String
    let scoreBoost: Double
    let actionTitle: String
    let perform: (DiagnosticsService) -> Void
}

private func openApplication(at path: String) {
    DispatchQueue.main.async {
        let url = URL(fileURLWithPath: path)
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}

private func runProcess(_ launchPath: String, _ arguments: [String]) {
    DispatchQueue.global(qos: .userInitiated).async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        do {
            try process.run()
        } catch {
            fputs("[Foundry] Failed to run \(launchPath): \(error.localizedDescription)\n", stderr)
        }
    }
}
