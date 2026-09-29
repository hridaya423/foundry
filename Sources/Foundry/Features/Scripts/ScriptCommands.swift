import Foundation
import FoundryDomain

enum ScriptOutputMode: String, Codable, Hashable, Sendable {
    case silent, compact, fullOutput, inline
}

struct ScriptArgument: Hashable, Sendable {
    let placeholder: String
    let optional: Bool
}

struct ScriptCommand: Hashable, Sendable {
    let path: String
    let title: String
    let mode: ScriptOutputMode
    let packageName: String?
    let icon: String?
    let arguments: [ScriptArgument]
    let warnings: [String]
}

enum ScriptDirectives {
    static let known: Set<String> = ["schemaVersion", "title", "mode", "packageName", "icon", "iconDark", "argument1", "argument2", "argument3", "refreshTime", "currentDirectoryPath", "needsConfirmation", "author", "authorURL", "description"]

    static func parse(_ contents: String, path: String) -> ScriptCommand? {
        var values: [String: String] = [:]
        var warnings: [String] = []
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false).prefix(40) {
            guard let range = line.range(of: "@raycast.") else { continue }
            let rest = line[range.upperBound...]
            let key = String(rest.prefix { $0.isLetter || $0.isNumber })
            let value = rest.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
            if known.contains(key) { values[key] = value } else { warnings.append("Unknown directive @raycast.\(key) ignored") }
        }
        guard let title = values["title"], title.isEmpty == false else { return nil }
        let arguments = ["argument1", "argument2", "argument3"].compactMap { key -> ScriptArgument? in
            guard let json = values[key]?.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
            return ScriptArgument(placeholder: object["placeholder"] as? String ?? "Argument", optional: object["optional"] as? Bool ?? false)
        }
        return ScriptCommand(
            path: path,
            title: title,
            mode: values["mode"].flatMap(ScriptOutputMode.init(rawValue:)) ?? .compact,
            packageName: values["packageName"],
            icon: values["icon"],
            arguments: arguments,
            warnings: warnings
        )
    }
}

final class ScriptDirectoryStore: @unchecked Sendable {
    static let shared = ScriptDirectoryStore()
    static let defaultDirectory = ConfigService.configURL.deletingLastPathComponent().appendingPathComponent("scripts").path

    private let defaults: UserDefaults
    private let directoriesKey = "foundry.scripts.directories"
    private let trustedKey = "foundry.scripts.trusted"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var directories: [String] {
        get { defaults.stringArray(forKey: directoriesKey) ?? [Self.defaultDirectory] }
        set { defaults.set(newValue, forKey: directoriesKey) }
    }

    func isTrusted(_ directory: String) -> Bool {
        Set(defaults.stringArray(forKey: trustedKey) ?? []).contains(Self.canonical(directory))
    }

    func setTrusted(_ trusted: Bool, for directory: String) {
        var set = Set(defaults.stringArray(forKey: trustedKey) ?? [])
        if trusted { set.insert(Self.canonical(directory)) } else { set.remove(Self.canonical(directory)) }
        defaults.set(set.sorted(), forKey: trustedKey)
    }

    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

final class ScriptCommandProvider: CommandProvider, @unchecked Sendable {
    let id = "foundry.scripts"
    private let store: ScriptDirectoryStore
    private let lock = NSLock()
    private var cache: [String: (modified: Date?, scripts: [ScriptCommand])] = [:]

    init(store: ScriptDirectoryStore = .shared) {
        self.store = store
    }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        let query = request.query.trimmingCharacters(in: .whitespaces)
        guard query.isEmpty == false else { return [] }
        return scripts().compactMap { script in
            let id = "script.\(script.path)"
            let aliases = request.customAliases[id] ?? []
            if script.arguments.isEmpty == false, query.lowercased().hasPrefix(script.title.lowercased() + " ") {
                let argument = query.dropFirst(script.title.count).trimmingCharacters(in: .whitespaces)
                return result(script, id: id, aliases: aliases, argument: argument)
            }
            guard SearchScoring.match(query: query, title: script.title, subtitle: script.packageName, keywords: ["script"], aliases: aliases, sensitivity: request.sensitivity) != nil else { return nil }
            return result(script, id: id, aliases: aliases, argument: nil)
        }
    }

    private func result(_ script: ScriptCommand, id: String, aliases: [String], argument: String?) -> CommandResult {
        let needsArgument = script.arguments.contains { $0.optional == false } && (argument ?? "").isEmpty
        let primary = needsArgument
            ? CommandAction(id: "\(id).fill", title: "Enter \(script.arguments[0].placeholder)", kind: .fillQuery("\(script.title) "))
            : CommandAction(id: "\(id).run", title: "Run Script", kind: .runScript(path: script.path, arguments: argument.map { [$0] } ?? [], mode: script.mode))
        let subtitle = needsArgument ? "Type \(script.arguments.map(\.placeholder).joined(separator: ", "))" : (script.packageName ?? "Script Command")
        return CommandResult(
            id: id,
            title: argument.map { "\(script.title) “\($0)”" } ?? script.title,
            subtitle: subtitle,
            icon: CommandIcon(fallback: script.icon.map { String($0.prefix(2)) } ?? "SH", systemName: "terminal"),
            searchAliases: aliases,
            searchKeywords: ["script"],
            primaryAction: primary,
            secondaryActions: []
        )
    }

    func scripts() -> [ScriptCommand] {
        store.directories.flatMap { directory -> [ScriptCommand] in
            let modified = (try? FileManager.default.attributesOfItem(atPath: directory))?[.modificationDate] as? Date
            if let cached = lock.withLock({ cache[directory] }), cached.modified == modified { return cached.scripts }
            let scripts = Self.scan(directory)
            lock.withLock { cache[directory] = (modified, scripts) }
            return scripts
        }
    }

    static func scan(_ directory: String) -> [ScriptCommand] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return files.sorted().compactMap { name in
            let path = (directory as NSString).appendingPathComponent(name)
            guard name.hasPrefix(".") == false, FileManager.default.isExecutableFile(atPath: path),
                  let handle = FileHandle(forReadingAtPath: path) else { return nil }
            defer { try? handle.close() }
            let head = String(decoding: handle.readData(ofLength: 8 * 1024), as: UTF8.self)
            return ScriptDirectives.parse(head, path: path)
        }
    }
}
