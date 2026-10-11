import Foundation
import FoundryDomain
import FoundryServices

enum SearchRoute: String, CaseIterable, Hashable, Sendable {
    case calculator
    case translation
    case mediaDownload
    case notesSearch
    case aiResponse
    case macUtility
    case browserTab
    case browserBookmark
    case browserHistory
    case developerTool
}

/// Typed identity of what a result *is*. Dispatch must switch on this —
/// never on `id` string prefixes. `id` remains a stable string key for
/// ranking/favorites bookkeeping.
enum ResultPayload: Hashable, Sendable {
    case app(identity: String)
    case file(URL)
    case snippet(id: String)
    /// Promotable `calculator.*` answer (live result or history row).
    case calculation(expression: String, value: String)
    /// `calculator.convert.*` row — a calculation but never the promoted card.
    case calculationConversion(expression: String, value: String)
    /// `calculator.fallback.*` static rows under a promoted answer.
    case calculatorFallback
    case quicklink(id: String)
    case script(path: String)
    case url(URL)
    case note(id: String)
    /// `foundry.quick.*` Ask-AI prompt rows.
    case aiPrompt
    /// Feature command rows and transient mode rows with no entity identity.
    case command
}

extension ResultPayload {
    var isCalculatorConversion: Bool {
        if case .calculationConversion = self { return true }
        return false
    }

    /// The evaluated expression behind a `calculator.*` result — replaces
    /// recovering it by splitting the subtitle on " · ".
    var calculationExpression: String? {
        switch self {
        case let .calculation(expression, _), let .calculationConversion(expression, _):
            return expression
        default:
            return nil
        }
    }
}

struct CommandResult: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: CommandIcon
    let searchAliases: [String]
    let searchKeywords: [String]
    let normalizedSearchTitle: String
    let normalizedSearchSubtitle: String?
    let normalizedSearchAliases: [String]
    let normalizedSearchKeywords: [String]
    let route: SearchRoute?
    let payload: ResultPayload
    let primaryAction: CommandAction
    let secondaryActions: [CommandAction]

    init(
        id: String,
        title: String,
        subtitle: String?,
        icon: CommandIcon,
        searchAliases: [String] = [],
        searchKeywords: [String] = [],
        route: SearchRoute? = nil,
        payload: ResultPayload,
        primaryAction: CommandAction,
        secondaryActions: [CommandAction]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.searchAliases = searchAliases
        self.searchKeywords = searchKeywords
        self.normalizedSearchTitle = SearchScoring.normalize(title)
        self.normalizedSearchSubtitle = subtitle.map(SearchScoring.normalize)
        self.normalizedSearchAliases = searchAliases.map(SearchScoring.normalize)
        self.normalizedSearchKeywords = searchKeywords.map(SearchScoring.normalize)
        self.route = route
        self.payload = payload
        self.primaryAction = primaryAction
        self.secondaryActions = secondaryActions
    }
}

struct CommandAction: Hashable, Sendable {
    let id: String
    let title: String
    let kind: CommandActionKind

    init(id: String, title: String, kind: CommandActionKind) {
        self.id = id
        self.title = title
        self.kind = kind
    }

    static func == (lhs: CommandAction, rhs: CommandAction) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum CommandActionKind: Hashable, Sendable {
    case openQuickAI(prompt: String)
    case openApp(path: String, name: String)
    case openURL(String)
    case openURLWithApp(url: String, bundleID: String)
    case openConfigFolder
    case openFileWithApp(path: String, appPath: String)
    case copyToClipboard(String)
    case copyFile(path: String)
    case revealFile(path: String)
    case compressFile(path: String)
    case shareFile(path: String)
    case renameFile(path: String)
    case moveToTrash(path: String)
    case addToFileShelf(path: String)
    case pasteText(String, cursorOffset: Int = 0, snippetID: String? = nil)
    case copySnippet(id: String)
    case pasteSnippet(id: String)
    case deleteSnippet(id: String)
    case deleteQuicklink(id: String)
    case createSnippetFromClipboard
    case importSnippets
    case exportSnippets
    case downloadMedia(url: String)
    case downloadMediaBatch(urls: [String])
    case chooseMediaDownloadFolder
    case openEmojiPicker
    case openFileShelf
    case openClipboardHistory
    case openSnippets
    case openFileConverter(path: String? = nil)
    case openCamera
    case openTranslator(text: String? = nil, language: String? = nil)
    case openDeveloperTools(tool: String? = nil)
    case openSettings
    case fillQuery(String)
    case runScript(path: String, arguments: [String], mode: ScriptOutputMode)
    case openWelcomeGuide
    case openHome
    case openMediaDownloads
    case terminateProcess(pid: Int32)
    case quitApplication(bundleID: String?, name: String)
    case forceQuitApplication(bundleID: String?, name: String)
    case hideApplication(bundleID: String, name: String)
    case quitAllApplications
    case toggleKeepAwake
    case extractTextFromImage(path: String?)
    case previewExtractedText(path: String)
    case pickColor
    case generateQRCode
    case generateWiFiQRCode
    case readQRCode
    case recognizeScreenText
    case emptyTrash
    case toggleDesktopIcons
    case pasteClipboardAsPlainText
    case celebrate
    case terminatePort(Int)
    case setAudioDevice(id: UInt32, kind: AudioDeviceKind)
    case resetRanking(commandID: String)
    case toggleFavorite(commandID: String)
    case openCommandSettings(SettingsDeepLink)
    case rebuildApp
    case runProcess(path: String, arguments: [String])
    case tileWindow(WindowPlacement)
    case quit
    case log(String)
}

enum HomeSuggestionRules {
    static let deniedBundleIdentifiers: Set<String> = [
        "com.apple.BluetoothFileExchange",
        "com.apple.DigitalColorMeter",
        "com.apple.audio.AudioMIDISetup",
        "com.apple.ColorSyncUtility",
        "com.apple.Grapher",
        "com.apple.MigrateAssistant",
        "com.apple.VoiceOverUtility",
        "com.apple.bootcampassistant"
    ]

    static func appBundleIdentifier(payload: ResultPayload) -> String? {
        guard case let .app(identity) = payload else { return nil }
        return identity
    }

    static func isSuggestible(payload: ResultPayload, runningBundleIDs: Set<String>, hasUsage: Bool) -> Bool {
        guard let bundleID = appBundleIdentifier(payload: payload) else { return false }
        guard deniedBundleIdentifiers.contains(bundleID) == false else { return false }
        return hasUsage || runningBundleIDs.contains(bundleID)
    }
}

/// Typed target for `.openCommandSettings` — replaces re-parsing result
/// id prefixes in Settings to pick a pane.
enum SettingsDeepLink: Hashable, Sendable {
    case command(id: String)
    case quicklinks
    case scripts

    init(result: CommandResult) {
        switch result.payload {
        case .quicklink: self = .quicklinks
        case .script: self = .scripts
        default: self = .command(id: result.id)
        }
    }
}

enum AudioDeviceKind: Hashable, Sendable {
    case output
    case input
}

protocol CommandProvider: Sendable {
    var id: String { get }
    var searchPolicy: CommandProviderSearchPolicy { get }
    var searchTimeout: Duration? { get }
    func search(_ request: CommandSearchRequest) async throws -> [CommandResult]
    func defaultResults() async throws -> [CommandResult]
    func isActive(for query: String) -> Bool
    func supplementalResults(matching query: String, sensitivity: SearchSensitivity) -> [CommandResult]
    func fallbackResults(matching query: String, sensitivity: SearchSensitivity) async throws -> [CommandResult]
}

extension CommandProvider {
    var searchPolicy: CommandProviderSearchPolicy { CommandProviderSearchPolicy() }

    var searchTimeout: Duration? { nil }

    func isActive(for _: String) -> Bool { true }

    func supplementalResults(matching _: String, sensitivity _: SearchSensitivity) -> [CommandResult] { [] }

    func fallbackResults(matching _: String, sensitivity _: SearchSensitivity) async throws -> [CommandResult] { [] }

    func results(matching query: String) async -> [CommandResult] {
        (await BestEffort.attempt("\(id) search") {
            try await search(CommandSearchRequest(query: query))
        }) ?? []
    }

    func defaultResults() async throws -> [CommandResult] { [] }
}

extension CommandResult {
    func descriptor(providerID: String) -> CommandDescriptor {
        CommandDescriptor(
            id: id,
            sourceID: providerID,
            title: title,
            subtitle: subtitle,
            category: providerID,
            icon: icon
        )
    }
}

extension CommandAction {
    var descriptor: CommandActionDescriptor {
        CommandActionDescriptor(
            id: id,
            title: title,
            isDestructive: kind.isDestructive,
            confirmation: kind.isDestructive ? .destructive : .never
        )
    }
}

extension CommandActionKind {
    var isDestructive: Bool {
        switch self {
        case .terminateProcess, .quitApplication, .forceQuitApplication, .quitAllApplications, .terminatePort, .rebuildApp, .quit, .deleteSnippet, .deleteQuicklink, .moveToTrash:
            true
        default:
            false
        }
    }
}

extension CommandActionKind {
    var shouldHidePanelForHotkey: Bool {
        switch self {
        case .tileWindow:
            true
        default:
            false
        }
    }
}

struct ActionShortcut: Hashable, Sendable {
    enum Modifier: CaseIterable, Sendable { case control, option, shift, command }

    let key: String
    let modifiers: Set<Modifier>

    var display: String {
        let symbols: [Modifier: String] = [.control: "⌃", .option: "⌥", .shift: "⇧", .command: "⌘"]
        let glyph: String
        switch key {
        case "\r": glyph = "↵"
        case "\u{7f}", "\u{8}": glyph = "⌫"
        default: glyph = key.uppercased()
        }
        return Modifier.allCases.filter(modifiers.contains).compactMap { symbols[$0] }.joined() + glyph
    }

    static let secondary = ActionShortcut(key: "\r", modifiers: [.command])

    static func assign(to actions: [CommandAction]) -> [String: ActionShortcut] {
        var assigned: [String: ActionShortcut] = [:]
        if actions.count > 1 { assigned[actions[1].id] = .secondary }
        for action in actions.dropFirst() where assigned[action.id] == nil {
            guard let shortcut = conventional(for: action.kind), assigned.values.contains(shortcut) == false else { continue }
            assigned[action.id] = shortcut
        }
        return assigned
    }

    private static func conventional(for kind: CommandActionKind) -> ActionShortcut? {
        switch kind {
        case .copyToClipboard: ActionShortcut(key: "c", modifiers: [.shift, .command])
        case .copyFile: ActionShortcut(key: "c", modifiers: [.command])
        case .revealFile: ActionShortcut(key: "r", modifiers: [.shift, .command])
        case .renameFile: ActionShortcut(key: "e", modifiers: [.command])
        case .moveToTrash: ActionShortcut(key: "\u{7f}", modifiers: [.command])
        case .toggleFavorite: ActionShortcut(key: "d", modifiers: [.command])
        case .openCommandSettings: ActionShortcut(key: ",", modifiers: [.shift, .command])
        case .deleteSnippet, .deleteQuicklink: ActionShortcut(key: "x", modifiers: [.control])
        default: nil
        }
    }
}
