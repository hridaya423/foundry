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
    case time(from: TimeConversionEngine.Reading, to: TimeConversionEngine.Reading)
    case date(from: DateMath.Side, to: DateMath.Side)
    case quicklink(id: String)
    case script(path: String)
    case url(URL)
    case note(id: String)
    /// `foundry.quick.*` Ask-AI prompt rows.
    case aiPrompt
    /// A generated value the user copies. The label names what it is ("Hex", "SHA-256").
    case value(label: String)
    /// Feature command rows and transient mode rows with no entity identity.
    case command
}

extension ResultPayload {
    /// Results that answer the query itself. They rank first and show as the card above the list.
    var isAnswer: Bool {
        switch self {
        case .calculation, .calculationConversion, .time, .date: true
        default: false
        }
    }

    /// The fixed rank of a result computed from the query. Such results keep the order their provider gave them.
    var computedScore: Double? {
        switch self {
        case .calculation, .calculationConversion, .time, .date: 10
        case .value: 5
        default: nil
        }
    }

    var usesTheQuery: Bool {
        switch self {
        case .aiPrompt, .quicklink: true
        default: false
        }
    }

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
    let behavior: any ResultAction

    init(id: String, title: String, behavior: any ResultAction) {
        self.id = id
        self.title = title
        self.behavior = behavior
    }

    static func == (lhs: CommandAction, rhs: CommandAction) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
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
    case command(id: String, title: String)
    case quicklinks
    case scripts
    case ai
    case snippets
    case agents

    init(result: CommandResult) {
        switch result.payload {
        case .quicklink: self = .quicklinks
        case .script: self = .scripts
        default: self = .command(id: result.id, title: result.title)
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
    var isDestructive: Bool { behavior.style == .destructive }

    var descriptor: CommandActionDescriptor {
        CommandActionDescriptor(
            id: id,
            title: title,
            isDestructive: behavior.style == .destructive,
            confirmation: behavior.style == .destructive ? .destructive : .never
        )
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
            guard let shortcut = action.behavior.shortcut, assigned.values.contains(shortcut) == false else { continue }
            assigned[action.id] = shortcut
        }
        return assigned
    }
}
