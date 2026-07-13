import AppKit
import Foundation

final class BrowserProvider: CommandProvider, @unchecked Sendable {
    let id = "foundry.browsers"

    private let homeDirectory: URL
    private let liveTabsCache = BrowserLiveTabsCache()

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func results(matching query: String) async -> [CommandResult] {
        let request = BrowserSearchRequest(query: query)
        guard request.isBrowserIntent else { return [] }

        let sources: [BrowserSource] = request.browser.map { [$0] } ?? BrowserSource.allCases
        var allRecords: [BrowserRecord] = []
        for source in sources {
            allRecords.append(contentsOf: records(for: source, kind: request.kind))
        }

        return allRecords
            .filter { request.search.isEmpty || $0.matches(request.search) }
            .prefix(12)
            .map(makeResult)
    }

    func defaultResults() async -> [CommandResult] {
        let source = selectedMainBrowser
        Task.detached { [weak self] in
            guard let self else { return }
            _ = self.liveTabs(for: source)
        }
        return BrowserSource.allCases.map(browserLaunchResult)
    }

    func cachedResults(matching query: String) -> [CommandResult] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard search.count >= 2, let tabs = liveTabsCache.value(for: selectedMainBrowser) else { return [] }
        return tabs.filter { $0.matches(search) }.prefix(6).map(makeResult)
    }

    func fallbackResults(matching query: String) async -> [CommandResult] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard search.count >= 2 else { return [] }
        let source = selectedMainBrowser
        return records(for: source, kind: nil)
            .filter { $0.matches(search) }
            .prefix(12)
            .map(makeResult)
    }

    private func records(for source: BrowserSource, kind: BrowserRecordKind?) -> [BrowserRecord] {
        var records: [BrowserRecord] = []
        if kind == nil || kind == .tab { records += liveTabs(for: source) }
        if kind == nil || kind == .history { records += history(for: source) }
        if kind == nil || kind == .bookmark { records += bookmarks(for: source) }
        return records
    }

    private func history(for source: BrowserSource) -> [BrowserRecord] {
        let query: String
        switch source {
        case .firefox:
            query = "SELECT moz_places.id, moz_places.title, moz_places.url, moz_historyvisits.visit_date FROM moz_historyvisits JOIN moz_places ON moz_places.id = moz_historyvisits.place_id ORDER BY moz_historyvisits.visit_date DESC LIMIT 100;"
        case .safari:
            query = "SELECT history_items.id, history_items.title, history_items.url, history_visits.visit_time FROM history_visits JOIN history_items ON history_items.id = history_visits.history_item ORDER BY history_visits.visit_time DESC LIMIT 100;"
        default:
            query = "SELECT urls.id, urls.title, urls.url, visits.visit_time FROM visits JOIN urls ON urls.id = visits.url ORDER BY visits.visit_time DESC LIMIT 100;"
        }

        return source.historyDatabases(in: homeDirectory).flatMap { database in
            LocalSQLite.rows(database: database, query: query).compactMap { row in
                guard let url = row["url"], let parsedURL = URL(string: url), parsedURL.scheme != nil else { return nil }
                let title = row["title"]?.isEmpty == false ? row["title"]! : url
                return BrowserRecord(
                    id: "history-\(source.rawValue)-\(database.lastPathComponent)-\(row["id"] ?? url)",
                    kind: .history,
                    browser: source,
                    title: title,
                    subtitle: "History - \(url)",
                    url: parsedURL,
                    icon: "clock.arrow.circlepath"
                )
            }
        }
    }

    private func bookmarks(for source: BrowserSource) -> [BrowserRecord] {
        switch source {
        case .safari:
            return source.bookmarkFiles(in: homeDirectory).flatMap { file in
                guard let object = NSDictionary(contentsOf: file) else { return [BrowserRecord]() }
                return SafariBookmarkParser.parse(object).compactMap { makeBookmark($0, source: source) }
            }
        case .firefox:
            let query = "SELECT moz_bookmarks.id, moz_bookmarks.title, moz_places.url FROM moz_bookmarks JOIN moz_places ON moz_places.id = moz_bookmarks.fk WHERE moz_bookmarks.type = 1 AND moz_places.url IS NOT NULL LIMIT 500;"
            return source.bookmarkFiles(in: homeDirectory).flatMap { file in
                LocalSQLite.rows(database: file, query: query).compactMap { row in
                    guard let url = row["url"] else { return nil }
                    return makeBookmark(ParsedBookmark(title: row["title"] ?? "", url: url), source: source)
                }
            }
        default:
            return source.bookmarkFiles(in: homeDirectory).flatMap { file in
                guard let data = try? Data(contentsOf: file), let object = try? JSONSerialization.jsonObject(with: data) else { return [BrowserRecord]() }
                return ChromeBookmarkParser.parse(object).compactMap { makeBookmark($0, source: source) }
            }
        }
    }

    private func makeBookmark(_ bookmark: ParsedBookmark, source: BrowserSource) -> BrowserRecord? {
        guard let url = URL(string: bookmark.url), url.scheme != nil else { return nil }
        return BrowserRecord(
            id: "bookmark-\(source.rawValue)-\(bookmark.url)",
            kind: .bookmark,
            browser: source,
            title: bookmark.title.isEmpty ? bookmark.url : bookmark.title,
            subtitle: "Bookmark - \(source.displayName)",
            url: url,
            icon: "bookmark"
        )
    }

    private func liveTabs(for source: BrowserSource) -> [BrowserRecord] {
        if let cached = liveTabsCache.value(for: source) { return cached }
        if source == .firefox {
            let records = firefoxSessionTabs()
            liveTabsCache.store(records, for: source)
            return records
        }
        guard source.supportsAppleScriptTabs else { return [] }
        guard NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == source.applicationBundleIdentifier || $0.localizedName == source.applicationName
        }) else { return [] }
        let script: String
        switch source {
        case .safari:
            script = "function run() { const app = Application('Safari'); return JSON.stringify(app.windows().flatMap(w => w.tabs().map(t => ({title: t.name(), url: t.url()})))); }"
        default:
            script = "function run() { const app = Application('\(source.applicationName)'); return JSON.stringify(app.windows().flatMap(w => w.tabs().map(t => ({title: t.title(), url: t.url()})))); }"
        }
        guard let output = runOSAScript(script), let data = output.data(using: .utf8), let tabs = try? JSONDecoder().decode([LiveTab].self, from: data) else { return [] }
        let records: [BrowserRecord] = tabs.compactMap { tab in
            guard let url = URL(string: tab.url), url.scheme != nil else { return nil }
            return BrowserRecord(id: "tab-\(source.rawValue)-\(tab.url)", kind: .tab, browser: source, title: tab.title.isEmpty ? tab.url : tab.title, subtitle: "Open tab - \(source.displayName)", url: url, icon: "rectangle.on.rectangle")
        }
        liveTabsCache.store(records, for: source)
        return records
    }

    private func firefoxSessionTabs() -> [BrowserRecord] {
        if let liveTabs = firefoxNativeTabs(), liveTabs.isEmpty == false {
            return liveTabs
        }
        return BrowserSource.firefox.sessionStoreFiles(in: homeDirectory).flatMap { file in
            guard let data = try? Data(contentsOf: file), let session = FirefoxSessionParser.parse(data) else { return [BrowserRecord]() }
            return session.tabs.enumerated().compactMap { index, tab in
                guard let url = URL(string: tab.url), url.scheme != nil else { return nil }
                return BrowserRecord(
                    id: "tab-firefox-\(file.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent)-\(index)-\(tab.url)",
                    kind: .tab,
                    browser: .firefox,
                    title: tab.title.isEmpty ? tab.url : tab.title,
                    subtitle: "Open tab - Firefox",
                    url: url,
                    icon: "rectangle.on.rectangle"
                )
            }
        }
    }

    private func firefoxNativeTabs() -> [BrowserRecord]? {
        let file = FirefoxNativeTabsStore.url(home: homeDirectory)
        guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
              let modifiedAt = values.contentModificationDate,
              Date().timeIntervalSince(modifiedAt) < 600,
              let data = try? Data(contentsOf: file),
              let payload = try? JSONDecoder().decode(FirefoxLiveTabs.self, from: data) else { return nil }
        return payload.tabs.enumerated().compactMap { index, tab in
            guard let url = URL(string: tab.url), url.scheme != nil else { return nil }
            return BrowserRecord(id: "tab-firefox-live-\(index)-\(tab.url)", kind: .tab, browser: .firefox, title: tab.title.isEmpty ? tab.url : tab.title, subtitle: "Open tab - Firefox", url: url, icon: "rectangle.on.rectangle")
        }
    }

    private func runOSAScript(_ script: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() } catch { return nil }
        guard process.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeResult(_ record: BrowserRecord) -> CommandResult {
        CommandResult(
            id: "browser.\(record.id)",
            title: record.title,
            subtitle: record.subtitle,
            icon: CommandIcon(fallback: record.browser.abbreviation, systemName: record.icon),
            score: record.kind == .tab ? 122 : (record.kind == .bookmark ? 118 : 112),
            primaryAction: CommandAction(id: "browser.open.\(record.id)", title: "Open in \(record.browser.displayName)", kind: .runProcess(path: "/usr/bin/open", arguments: ["-a", record.browser.applicationName, record.url.absoluteString])),
            secondaryActions: [CommandAction(id: "browser.copy.\(record.id)", title: "Copy URL", kind: .copyToClipboard(record.url.absoluteString))]
        )
    }

    private func browserLaunchResult(_ browser: BrowserSource) -> CommandResult {
        CommandResult(id: "foundry.browser.\(browser.rawValue)", title: browser.displayName, subtitle: "Search tabs, history, and bookmarks with: \(browser.rawValue) <text>", icon: CommandIcon(fallback: browser.abbreviation, systemName: "globe"), score: 0, primaryAction: CommandAction(id: "foundry.browser.launch.\(browser.rawValue)", title: "Open", kind: .runProcess(path: "/usr/bin/open", arguments: ["-a", browser.applicationName])), secondaryActions: [])
    }

    private var selectedMainBrowser: BrowserSource {
        UserDefaults.standard.string(forKey: "foundry.mainBrowser").flatMap(BrowserSource.init(rawValue:)) ?? .safari
    }
}

struct BrowserSearchRequest {
    let search: String
    let browser: BrowserSource?
    let kind: BrowserRecordKind?
    let isBrowserIntent: Bool

    init(query: String) {
        var value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = value.lowercased()
        browser = BrowserSource.allCases.first { lowercased.hasPrefix($0.rawValue + " ") || lowercased == $0.rawValue }
        if let browser { value = String(value.dropFirst(browser.rawValue.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
        let lowerValue = value.lowercased()
        if lowerValue.hasPrefix("tabs ") || lowerValue == "tabs" || lowerValue.hasPrefix("tab ") || lowerValue == "tab" {
            kind = .tab
            value = String(value.drop { $0 != " " }).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if lowerValue.hasPrefix("history ") || lowerValue == "history" {
            kind = .history
            value = String(value.drop { $0 != " " }).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if lowerValue.hasPrefix("bookmarks ") || lowerValue == "bookmarks" || lowerValue.hasPrefix("bookmark ") {
            kind = .bookmark
            value = String(value.drop { $0 != " " }).trimmingCharacters(in: .whitespacesAndNewlines)
        } else { kind = nil }
        search = value.lowercased()
        isBrowserIntent = kind != nil || (browser != nil && search.isEmpty == false)
    }
}

enum BrowserSource: String, CaseIterable, Sendable, Hashable {
    case safari, chrome, firefox, arc, dia, helium, brave, edge, vivaldi, opera, operaGX, chromium, duckduckgo, orion, mullvad, tor, yandex, zen

    var displayName: String { rawValue.capitalized }
    var abbreviation: String {
        switch self {
        case .safari: "SF"
        case .firefox: "FF"
        case .chrome: "CH"
        case .arc: "AR"
        case .dia: "DI"
        case .helium: "HE"
        case .brave: "BR"
        case .edge: "ED"
        case .vivaldi: "VI"
        case .opera: "OP"
        case .chromium: "CR"
        case .operaGX: "OG"
        case .duckduckgo: "DD"
        case .orion: "OR"
        case .mullvad: "MU"
        case .tor: "TO"
        case .yandex: "YA"
        case .zen: "ZE"
        }
    }

    var applicationName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Google Chrome"
        case .firefox: "Firefox"
        case .arc: "Arc"
        case .dia: "Dia"
        case .helium: "Helium"
        case .brave: "Brave Browser"
        case .edge: "Microsoft Edge"
        case .vivaldi: "Vivaldi"
        case .opera: "Opera"
        case .chromium: "Chromium"
        case .operaGX: "Opera GX"
        case .duckduckgo: "DuckDuckGo"
        case .orion: "Orion"
        case .mullvad: "Mullvad Browser"
        case .tor: "Tor Browser"
        case .yandex: "Yandex"
        case .zen: "Zen"
        }
    }

    var applicationBundleIdentifier: String {
        switch self {
        case .safari: "com.apple.Safari"
        case .chrome: "com.google.Chrome"
        case .firefox: "org.mozilla.firefox"
        case .arc: "company.thebrowser.Browser"
        case .dia: "company.thebrowser.dia"
        case .helium: "net.imput.helium"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        case .vivaldi: "com.vivaldi.Vivaldi"
        case .opera: "com.operasoftware.Opera"
        case .chromium: "org.chromium.Chromium"
        case .operaGX: "com.operasoftware.OperaGX"
        case .duckduckgo: "com.duckduckgo.macos.browser"
        case .orion: "com.kagi.Orion"
        case .mullvad: "net.mullvad.mullvadbrowser"
        case .tor: "org.torproject.torbrowser"
        case .yandex: "ru.yandex.desktop.yandex-browser"
        case .zen: "app.zen-browser.zen"
        }
    }

    var isInstalled: Bool {
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: applicationBundleIdentifier) != nil { return true }
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        return roots.contains { root in
            FileManager.default.fileExists(atPath: root.appendingPathComponent("\(applicationName).app").path)
        }
    }

    var supportsAppleScriptTabs: Bool { self != .firefox }

    private var dataRoots: [String] {
        switch self {
        case .safari: []
        case .chrome: ["Library/Application Support/Google/Chrome"]
        case .firefox: ["Library/Application Support/Firefox/Profiles"]
        case .arc: ["Library/Application Support/Arc/User Data"]
        case .dia: ["Library/Application Support/Dia/User Data", "Library/Application Support/Dia"]
        case .helium: ["Library/Application Support/net.imput.helium", "Library/Application Support/Helium"]
        case .brave: ["Library/Application Support/BraveSoftware/Brave-Browser"]
        case .edge: ["Library/Application Support/Microsoft Edge"]
        case .vivaldi: ["Library/Application Support/Vivaldi"]
        case .opera: ["Library/Application Support/com.operasoftware.Opera"]
        case .chromium: ["Library/Application Support/Chromium"]
        case .operaGX: ["Library/Application Support/com.operasoftware.OperaGX"]
        case .duckduckgo: ["Library/Application Support/DuckDuckGo"]
        case .orion: ["Library/Application Support/Orion"]
        case .mullvad: ["Library/Application Support/Mullvad Browser"]
        case .tor: ["Library/Application Support/TorBrowser-Data"]
        case .yandex: ["Library/Application Support/Yandex/YandexBrowser"]
        case .zen: ["Library/Application Support/zen"]
        }
    }

    func historyDatabases(in home: URL) -> [URL] {
        if self == .safari { return existing([home.appendingPathComponent("Library/Safari/History.db")]) }
        return profileDirectories(in: home).map { $0.appendingPathComponent("places.sqlite") }.filter { FileManager.default.fileExists(atPath: $0.path) || self != .firefox }.compactMap { file in
            let history = self == .firefox ? file : file.deletingLastPathComponent().appendingPathComponent("History")
            return FileManager.default.fileExists(atPath: history.path) ? history : nil
        }
    }

    func bookmarkFiles(in home: URL) -> [URL] {
        if self == .safari { return existing([home.appendingPathComponent("Library/Safari/Bookmarks.plist")]) }
        if self == .firefox { return historyDatabases(in: home) }
        return profileDirectories(in: home).map { $0.appendingPathComponent("Bookmarks") }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func sessionStoreFiles(in home: URL) -> [URL] {
        guard self == .firefox else { return [] }
        return profileDirectories(in: home).flatMap { profile in
            let backup = profile.appendingPathComponent("sessionstore-backups")
            let preferred = [
                backup.appendingPathComponent("recovery.jsonlz4"),
                backup.appendingPathComponent("recovery.baklz4"),
                profile.appendingPathComponent("sessionstore.jsonlz4"),
                backup.appendingPathComponent("previous.jsonlz4"),
                profile.appendingPathComponent("sessionstore.js"),
                backup.appendingPathComponent("recovery.js"),
                backup.appendingPathComponent("recovery.bak"),
                backup.appendingPathComponent("previous.js")
            ]
            let upgradeBackups = (try? FileManager.default.contentsOfDirectory(at: backup, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]))?
                .filter { $0.lastPathComponent.hasPrefix("upgrade.jsonlz4-") }
                .sorted { lhs, rhs in
                    let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return left > right
                } ?? []
            return (preferred + upgradeBackups).filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    private func profileDirectories(in home: URL) -> [URL] {
        dataRoots.flatMap { root in
            let directory = home.appendingPathComponent(root)
            guard FileManager.default.fileExists(atPath: directory.path) else { return [URL]() }
            guard let children = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [URL]() }
            let profiles = children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            if profiles.isEmpty { return [directory] }
            return profiles
        }
    }

    private func existing(_ urls: [URL]) -> [URL] {
        urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}

enum BrowserRecordKind: Sendable, Equatable { case tab, history, bookmark }

private final class BrowserLiveTabsCache: @unchecked Sendable {
    private struct Entry {
        let createdAt: Date
        let records: [BrowserRecord]
    }

    private let lock = NSLock()
    private var entries: [BrowserSource: Entry] = [:]
    private let lifetime: TimeInterval = 10.0

    func value(for source: BrowserSource) -> [BrowserRecord]? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[source], Date().timeIntervalSince(entry.createdAt) < lifetime else {
            entries[source] = nil
            return nil
        }
        return entry.records
    }

    func store(_ records: [BrowserRecord], for source: BrowserSource) {
        lock.lock()
        entries[source] = Entry(createdAt: Date(), records: records)
        lock.unlock()
    }
}

struct BrowserRecord: Sendable {
    let id: String
    let kind: BrowserRecordKind
    let browser: BrowserSource
    let title: String
    let subtitle: String
    let url: URL
    let icon: String

    func matches(_ query: String) -> Bool {
        let haystack = "\(title) \(subtitle) \(url.absoluteString)".lowercased()
        return haystack.contains(query)
    }
}

struct LiveTab: Decodable { let title: String; let url: String }
struct FirefoxLiveTabs: Decodable {
    let tabs: [LiveTab]
}
struct ParsedBookmark: Sendable { let title: String; let url: String }

struct FirefoxSessionTab: Sendable {
    let title: String
    let url: String
}

struct FirefoxSession: Sendable {
    let tabs: [FirefoxSessionTab]
}

enum FirefoxSessionParser {
    private static let header = Data([0x6d, 0x6f, 0x7a, 0x4c, 0x7a, 0x34, 0x30, 0x00])

    static func parse(_ data: Data) -> FirefoxSession? {
        guard let json = decode(data),
              let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let windows = root["windows"] as? [[String: Any]] else { return nil }

        let tabs = windows.flatMap { window in
            (window["tabs"] as? [[String: Any]] ?? []).compactMap { tab -> FirefoxSessionTab? in
                guard let entries = tab["entries"] as? [[String: Any]], entries.isEmpty == false else { return nil }
                let rawIndex = tab["index"] as? Int ?? entries.count
                let index = min(max(rawIndex - 1, 0), entries.count - 1)
                guard let url = entries[index]["url"] as? String, url.isEmpty == false else { return nil }
                return FirefoxSessionTab(title: entries[index]["title"] as? String ?? "", url: url)
            }
        }
        return FirefoxSession(tabs: tabs)
    }

    private static func decode(_ data: Data) -> Data? {
        guard data.starts(with: header) else { return data }
        let sizeOffset = header.count
        guard data.count >= sizeOffset + 4 else { return nil }
        let size = data[sizeOffset..<(sizeOffset + 4)].enumerated().reduce(UInt32(0)) { result, item in
            result | UInt32(item.element) << UInt32(item.offset * 8)
        }
        guard size > 0, size <= UInt32.max else { return nil }
        let compressed = Array(data[(sizeOffset + 4)...])
        return decodeLZ4Block(compressed, outputSize: Int(size))
    }

    private static func decodeLZ4Block(_ input: [UInt8], outputSize: Int) -> Data? {
        var output: [UInt8] = []
        output.reserveCapacity(outputSize)
        var inputIndex = 0

        while inputIndex < input.count {
            let token = input[inputIndex]
            inputIndex += 1

            var literalLength = Int(token >> 4)
            if literalLength == 15 {
                guard let length = readExtendedLength(input, index: &inputIndex) else { return nil }
                literalLength += length
            }
            guard inputIndex + literalLength <= input.count else { return nil }
            output.append(contentsOf: input[inputIndex..<(inputIndex + literalLength)])
            inputIndex += literalLength

            if inputIndex == input.count { break }
            guard inputIndex + 2 <= input.count else { return nil }
            let offset = Int(input[inputIndex]) | (Int(input[inputIndex + 1]) << 8)
            inputIndex += 2
            guard offset > 0, offset <= output.count else { return nil }

            var matchLength = Int(token & 0x0f) + 4
            if matchLength - 4 == 15 {
                guard let length = readExtendedLength(input, index: &inputIndex) else { return nil }
                matchLength += length
            }
            let matchStart = output.count - offset
            for index in 0..<matchLength {
                output.append(output[matchStart + index])
            }
        }

        guard output.count == outputSize else { return nil }
        return Data(output)
    }

    private static func readExtendedLength(_ input: [UInt8], index: inout Int) -> Int? {
        var length = 0
        while true {
            guard index < input.count else { return nil }
            let value = Int(input[index])
            index += 1
            length += value
            if value != 255 { return length }
        }
    }
}

enum ChromeBookmarkParser {
    static func parse(_ object: Any) -> [ParsedBookmark] {
        guard let root = object as? [String: Any] else { return [] }
        return root.values.flatMap(parseNode)
    }

    private static func parseNode(_ object: Any) -> [ParsedBookmark] {
        guard let node = object as? [String: Any] else { return [] }
        var results: [ParsedBookmark] = []
        if node["type"] as? String == "url", let url = node["url"] as? String { results.append(ParsedBookmark(title: node["name"] as? String ?? "", url: url)) }
        if let children = node["children"] as? [Any] { results += children.flatMap(parseNode) }
        return results
    }
}

enum SafariBookmarkParser {
    static func parse(_ object: NSDictionary) -> [ParsedBookmark] { parseNode(object) }

    private static func parseNode(_ object: NSDictionary) -> [ParsedBookmark] {
        var results: [ParsedBookmark] = []
        if object["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf", let url = object["URLString"] as? String { results.append(ParsedBookmark(title: object["URIDictionary"] is NSDictionary ? ((object["URIDictionary"] as? NSDictionary)?["title"] as? String ?? "") : "", url: url)) }
        if let children = object["Children"] as? [NSDictionary] { results += children.flatMap(parseNode) }
        return results
    }
}

private enum LocalSQLite {
    static func rows(database: URL, query: String) -> [[String: String]] {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-browser-\(UUID().uuidString).db")
        let sidecars = ["-wal", "-shm"].map { suffix in
            (source: URL(fileURLWithPath: database.path + suffix), destination: URL(fileURLWithPath: temporary.path + suffix))
        }
        defer {
            try? FileManager.default.removeItem(at: temporary)
            sidecars.forEach { try? FileManager.default.removeItem(at: $0.destination) }
        }
        guard (try? FileManager.default.copyItem(at: database, to: temporary)) != nil else { return [] }
        for sidecar in sidecars where FileManager.default.fileExists(atPath: sidecar.source.path) {
            try? FileManager.default.copyItem(at: sidecar.source, to: sidecar.destination)
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", temporary.path, query]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() } catch { return [] }
        guard process.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return objects.map { row in row.reduce(into: [String: String]()) { result, item in result[item.key] = String(describing: item.value) } }
    }
}
