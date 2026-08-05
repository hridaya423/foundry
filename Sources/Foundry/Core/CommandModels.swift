import Foundation
import FoundryDomain

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

struct CommandResult: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: CommandIcon
    let searchAliases: [String]
    let searchKeywords: [String]
    let route: SearchRoute?
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
        primaryAction: CommandAction,
        secondaryActions: [CommandAction]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.searchAliases = searchAliases
        self.searchKeywords = searchKeywords
        self.route = route
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
    case openConfigFolder
    case revealInFinder(path: String)
    case copyToClipboard(String)
    case pasteText(String)
    case createSnippetFromClipboard
    case importSnippets
    case downloadMedia(url: String)
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
    case openDashboard
    case terminateProcess(pid: Int32)
    case quitApplication(bundleID: String?, name: String)
    case toggleKeepAwake
    case terminatePort(Int)
    case setAudioDevice(id: UInt32, kind: AudioDeviceKind)
    case resetRanking(commandID: String)
    case rebuildApp
    case runProcess(path: String, arguments: [String])
    case quit
    case log(String)
}

enum AudioDeviceKind: Hashable, Sendable {
    case output
    case input
}

protocol CommandProvider: Sendable {
    var id: String { get }
    var searchPolicy: CommandProviderSearchPolicy { get }
    var descriptor: CommandProviderDescriptor { get }
    func search(_ request: CommandSearchRequest) async throws -> [CommandResult]
    func defaultResults() async throws -> [CommandResult]
    func isActive(for query: String) -> Bool
    func supplementalResults(matching query: String, sensitivity: SearchSensitivity) -> [CommandResult]
    func fallbackResults(matching query: String, sensitivity: SearchSensitivity) async throws -> [CommandResult]
}

extension CommandProvider {
    var searchPolicy: CommandProviderSearchPolicy { CommandProviderSearchPolicy() }

    func isActive(for _: String) -> Bool { true }

    func supplementalResults(matching _: String, sensitivity _: SearchSensitivity) -> [CommandResult] { [] }

    func fallbackResults(matching _: String, sensitivity _: SearchSensitivity) async throws -> [CommandResult] { [] }

    func results(matching query: String, customAliases: [String: [String]]) async -> [CommandResult] {
        (try? await search(CommandSearchRequest(query: query, customAliases: customAliases))) ?? []
    }

    func results(matching query: String) async -> [CommandResult] {
        (try? await search(CommandSearchRequest(query: query))) ?? []
    }

    func results(matching query: String, customAliases: [String: [String]], sensitivity: SearchSensitivity) async -> [CommandResult] {
        (try? await search(CommandSearchRequest(query: query, customAliases: customAliases, sensitivity: sensitivity))) ?? []
    }

    func results(matching query: String, customAliases: [String: [String]], sensitivity: SearchSensitivity, deadline: ContinuousClock.Instant) async -> [CommandResult] {
        guard ContinuousClock().now < deadline else { return [] }
        return (try? await search(CommandSearchRequest(query: query, customAliases: customAliases, sensitivity: sensitivity, deadline: deadline))) ?? []
    }

    func defaultResults() async throws -> [CommandResult] { [] }

    func defaultResults(deadline: ContinuousClock.Instant) async -> [CommandResult] {
        guard ContinuousClock().now < deadline else { return [] }
        return (try? await defaultResults()) ?? []
    }

    var descriptor: CommandProviderDescriptor {
        CommandProviderDescriptor(
            id: id,
            version: "1",
            availability: .available,
            requiredPermissions: [],
            supportedContexts: ["search", "home"],
            searchPolicy: searchPolicy,
            health: nil
        )
    }
}

extension CommandResult {
    func descriptor(providerID: String, preference: CommandPreference? = nil) -> CommandDescriptor {
        CommandDescriptor(
            id: id,
            sourceID: providerID,
            title: title,
            subtitle: subtitle,
            keywords: searchKeywords + searchAliases + (preference?.aliases ?? []),
            category: providerID,
            icon: icon,
            availability: .available,
            defaultActionID: primaryAction.id,
            argumentSchema: [:],
            capabilities: [.search, .defaultResult],
            executionPolicy: primaryAction.kind.executionPolicy
        )
    }
}

extension CommandAction {
    var descriptor: CommandActionDescriptor {
        CommandActionDescriptor(
            id: id,
            title: title,
            symbol: nil,
            keyboardEquivalent: nil,
            isDestructive: kind.isDestructive,
            confirmation: kind.isDestructive ? .destructive : .never,
            executionRequestID: id
        )
    }
}

extension CommandActionKind {
    var isDestructive: Bool {
        switch self {
        case .terminateProcess, .quitApplication, .terminatePort, .rebuildApp, .quit:
            true
        default:
            false
        }
    }

    var executionPolicy: CommandExecutionPolicy {
        switch self {
        case .copyToClipboard, .openURL, .openQuickAI, .openConfigFolder, .openEmojiPicker, .openFileShelf, .openClipboardHistory, .openSnippets, .openFileConverter, .openCamera, .openTranslator, .openDeveloperTools, .openSettings, .openDashboard, .log:
            .readOnly
        case .openApp, .revealInFinder, .createSnippetFromClipboard, .importSnippets, .pasteText, .chooseMediaDownloadFolder, .setAudioDevice, .resetRanking:
            .localMutation
        case .downloadMedia:
            .network
        case .terminateProcess, .quitApplication, .terminatePort, .rebuildApp, .quit:
            .destructive
        case .runProcess, .toggleKeepAwake:
            .systemMutation
        }
    }
}
