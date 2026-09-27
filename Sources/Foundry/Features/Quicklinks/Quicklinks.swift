import Foundation
import FoundryDomain

struct Quicklink: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var link: String
    var keyword: String = ""
    var openWithBundleID: String?
    var useFavicon: Bool?

    var takesArgument: Bool { QuicklinkTemplate.argumentRange(in: link) != nil }
}

enum QuicklinkTemplate {
    static func argumentRange(in link: String) -> Range<String.Index>? {
        link.range(of: #"\{(argument[^}]*|query)\}"#, options: [.regularExpression, .caseInsensitive])
    }

    static func expand(_ link: String, argument: String, context: SnippetRenderContext) -> String {
        let isURL = link.contains("://") || link.hasPrefix("mailto:")
        func value(_ raw: String) -> String {
            guard isURL else { return raw }
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&+=?#/")
            return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
        }
        var result = link
        while let range = argumentRange(in: result) {
            result.replaceSubrange(range, with: value(argument))
        }
        for token in ["{clipboard}", "{selection}", "{date}", "{time}"] where result.contains(token) {
            let raw = token == "{clipboard}" ? context.clipboard : SnippetRenderer.render(token, context: context).text
            result = result.replacingOccurrences(of: token, with: value(raw))
        }
        return result
    }

    static let defaults: [Quicklink] = [
        Quicklink(id: "google", name: "Search Google", link: "https://www.google.com/search?q={argument}", keyword: "g"),
        Quicklink(id: "github", name: "Search GitHub", link: "https://github.com/search?q={argument}", keyword: "gh"),
        Quicklink(id: "youtube", name: "Search YouTube", link: "https://www.youtube.com/results?search_query={argument}", keyword: "yt"),
        Quicklink(id: "maps", name: "Search Maps", link: "maps://?q={argument}", keyword: "maps"),
        Quicklink(id: "translate", name: "Google Translate", link: "https://translate.google.com/?sl=auto&text={argument}", keyword: "gt"),
        Quicklink(id: "search-files", name: "Search Files", link: "foundry://files/{argument}", keyword: "sf")
    ]

    static func importRaycast(_ data: Data) throws -> [Quicklink] {
        struct Exported: Decodable {
            let name: String
            let link: String
            let openWithBundleID: String?
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decode(String.self, forKey: .name)
                link = try container.decode(String.self, forKey: .link)
                if let bundleID = try? container.decode(String.self, forKey: .openWith) {
                    openWithBundleID = bundleID.isEmpty ? nil : bundleID
                } else if let app = try? container.decode([String: String].self, forKey: .openWith) {
                    openWithBundleID = app["bundleIdentifier"].flatMap { $0.isEmpty ? nil : $0 }
                } else {
                    openWithBundleID = nil
                }
            }
            enum CodingKeys: String, CodingKey { case name, link, openWith }
        }
        return try JSONDecoder().decode([Exported].self, from: data).map {
            Quicklink(name: $0.name, link: $0.link, openWithBundleID: $0.openWithBundleID)
        }
    }
}

final class QuicklinkStore: @unchecked Sendable {
    static let shared = QuicklinkStore()

    let url: URL
    private let lock = NSLock()
    private var cached: [Quicklink]?

    init(url: URL = ConfigService.configURL.deletingLastPathComponent().appendingPathComponent("quicklinks.json")) {
        self.url = url
    }

    func load() -> [Quicklink] {
        lock.withLock {
            if let cached { return cached }
            let loaded: [Quicklink]
            if let data = try? Data(contentsOf: url) {
                loaded = (try? JSONDecoder().decode([Quicklink].self, from: data)) ?? []
            } else {
                loaded = QuicklinkTemplate.defaults
            }
            cached = loaded
            return loaded
        }
    }

    func save(_ links: [Quicklink]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(links).write(to: url, options: .atomic)
        lock.withLock { cached = links }
    }
}

final class QuicklinkProvider: CommandProvider, @unchecked Sendable {
    let id = "foundry.quicklinks"
    private let store: QuicklinkStore
    private let context: @Sendable () -> SnippetRenderContext

    init(store: QuicklinkStore = .shared, context: @escaping @Sendable () -> SnippetRenderContext = { .current() }) {
        self.store = store
        self.context = context
    }

    static let createCommand = CommandResult(
        id: "quicklink.create",
        title: "Create Quicklink",
        subtitle: "Name, link with {argument}, keyword — edit in Settings",
        icon: CommandIcon(fallback: "QL", systemName: "plus.link"),
        primaryAction: CommandAction(id: "quicklink.create.open", title: "Create", kind: .openCommandSettings(commandID: "quicklink.create")),
        secondaryActions: []
    )

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        let query = request.query.trimmingCharacters(in: .whitespaces)
        guard query.isEmpty == false else { return [] }
        let create = SearchScoring.match(query: query, title: Self.createCommand.title, subtitle: nil, keywords: ["new quicklink", "add quicklink"], aliases: [], sensitivity: request.sensitivity) != nil ? [Self.createCommand] : []
        return create + store.load().compactMap { link in
            if link.takesArgument, let argument = argument(in: query, for: link) {
                return result(for: link, argument: argument, aliases: request.customAliases["quicklink.\(link.id)"] ?? [])
            }
            let aliases = request.customAliases["quicklink.\(link.id)"] ?? []
            guard SearchScoring.match(query: query, title: link.name, subtitle: nil, keywords: [], aliases: aliases + [link.keyword].filter { !$0.isEmpty }, sensitivity: request.sensitivity) != nil else { return nil }
            return result(for: link, argument: nil, aliases: aliases)
        }
    }

    func defaultResults() async -> [CommandResult] { [Self.createCommand] }

    func fallbackResults(matching query: String, sensitivity _: SearchSensitivity) async -> [CommandResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false, let google = store.load().first(where: { $0.id == "google" && $0.takesArgument }) else { return [] }
        return [result(for: google, argument: query, aliases: [])]
    }

    private func argument(in query: String, for link: Quicklink) -> String? {
        for prefix in [link.keyword, link.name] where prefix.isEmpty == false {
            guard query.count > prefix.count, query.lowercased().hasPrefix(prefix.lowercased() + " ") else { continue }
            let argument = query.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            if argument.isEmpty == false { return argument }
        }
        return nil
    }

    static func faviconURL(for template: String) -> URL? {
        guard let match = template.range(of: #"https?://[^/{}\s]+"#, options: .regularExpression) else { return nil }
        return URL(string: "\(template[match])/favicon.ico")
    }

    static let fileSearchLinkPrefix = "foundry://files/"

    private func result(for link: Quicklink, argument: String?, aliases: [String]) -> CommandResult {
        let id = "quicklink.\(link.id)"
        let prefix = link.keyword.isEmpty ? link.name : link.keyword
        let isFileSearch = link.link.hasPrefix(Self.fileSearchLinkPrefix)
        let primary: CommandAction
        let title: String
        if isFileSearch {
            title = argument.map { "\(link.name) for “\($0)”" } ?? link.name
            primary = CommandAction(id: "\(id).open", title: "Search Files", kind: .fillQuery(FileSearchProvider.prefix + (argument ?? "")))
        } else if let argument {
            title = "\(link.name) for “\(argument)”"
            let expanded = QuicklinkTemplate.expand(link.link, argument: argument, context: context())
            let kind: CommandActionKind = link.openWithBundleID.map { .openURLWithApp(url: expanded, bundleID: $0) } ?? .openURL(expanded)
            primary = CommandAction(id: "\(id).open", title: "Open", kind: kind)
        } else if link.takesArgument {
            title = link.name
            primary = CommandAction(id: "\(id).fill", title: "Enter Query", kind: .fillQuery("\(prefix) "))
        } else {
            title = link.name
            let expanded = QuicklinkTemplate.expand(link.link, argument: "", context: context())
            let kind: CommandActionKind = link.openWithBundleID.map { .openURLWithApp(url: expanded, bundleID: $0) } ?? .openURL(expanded)
            primary = CommandAction(id: "\(id).open", title: "Open", kind: kind)
        }
        return CommandResult(
            id: id,
            title: title,
            subtitle: isFileSearch ? "Spotlight file search" : (link.takesArgument && argument == nil ? "Type \(prefix) then your query" : Self.displayURL(link.link, argument: argument)),
            icon: CommandIcon(fallback: String(link.name.prefix(2)).uppercased(), systemName: isFileSearch ? "doc.text.magnifyingglass" : "link", remoteIconURL: link.useFavicon == false ? nil : Self.faviconURL(for: link.link)),
            searchAliases: aliases,
            searchKeywords: [link.keyword].filter { !$0.isEmpty },
            primaryAction: primary,
            secondaryActions: [
                CommandAction(id: "\(id).copy", title: "Copy Link", kind: .copyToClipboard(argument.map { QuicklinkTemplate.expand(link.link, argument: $0, context: context()) } ?? link.link)),
                CommandAction(id: "\(id).delete", title: "Delete Quicklink", kind: .deleteQuicklink(id: link.id))
            ]
        )
    }

    private static func displayURL(_ link: String, argument: String?) -> String {
        var display = link
        while let range = QuicklinkTemplate.argumentRange(in: display) {
            display.replaceSubrange(range, with: argument ?? "")
        }
        if let scheme = display.range(of: "://") {
            display.removeSubrange(display.startIndex..<scheme.upperBound)
        }
        if display.hasPrefix("www.") { display.removeFirst(4) }
        return display
    }
}
