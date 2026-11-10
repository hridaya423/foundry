import Foundation
import FoundryServices

struct FoundryBackup: Codable, Equatable {
    static let formatID = "foundry-backup"
    static let currentVersion = 1
    static let fileExtension = "foundrybackup"

    var format: String
    var version: Int
    var createdAt: Date
    var appVersion: String
    var files: [String: Data]
    var scriptDirectories: [String]

    struct Locations {
        var config: URL
        var snippets: URL
        var quicklinks: URL
        var usage: URL

        static var standard: Locations {
            Locations(config: ConfigService.configURL, snippets: FileSnippetStore().url, quicklinks: QuicklinkStore().url, usage: UsageRankingStore.usageURL)
        }

        var byName: [String: URL] {
            ["config.json": config, "snippets.json": snippets, "quicklinks.json": quicklinks, "usage.json": usage]
        }
    }

    static func make(locations: Locations = .standard, scriptDirectories: [String], appVersion: String, now: Date = Date()) throws -> FoundryBackup {
        var files: [String: Data] = [:]
        for (name, url) in locations.byName where FileManager.default.fileExists(atPath: url.path) {
            files[name] = try Data(contentsOf: url)
        }
        return FoundryBackup(format: formatID, version: currentVersion, createdAt: now, appVersion: appVersion, files: files,
            scriptDirectories: scriptDirectories)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> FoundryBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = BestEffort.attempt("decode backup") {
            try decoder.decode(FoundryBackup.self, from: data)
        }
        guard let backup, backup.format == formatID else { throw BackupError.notABackup }
        guard backup.version <= currentVersion else { throw BackupError.newerVersion }
        let known = Set(Locations.standard.byName.keys)
        for (name, contents) in backup.files {
            guard known.contains(name) else { throw BackupError.damaged(name) }
            let valid: Bool
            switch name {
            case "config.json":
                valid = BestEffort.attempt("validate backup config.json") {
                    try FoundryConfigMigration.migrate(contents)
                } != nil
            case "snippets.json":
                valid = BestEffort.attempt("validate backup snippets.json") {
                    try JSONDecoder().decode([StoredSnippet].self, from: contents)
                } != nil
            case "quicklinks.json":
                valid = BestEffort.attempt("validate backup quicklinks.json") {
                    try JSONDecoder().decode([Quicklink].self, from: contents)
                } != nil
            default:
                valid = BestEffort.attempt("validate backup \(name)") {
                    try JSONSerialization.jsonObject(with: contents)
                } is [String: Any]
            }
            guard valid else { throw BackupError.damaged(name) }
        }
        return backup
    }

    func restore(to locations: Locations = .standard, scripts: ScriptDirectoryStore = .shared, now: Date = Date(),
        write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) throws {
        let fileManager = FileManager.default
        var replaced: [(url: URL, saved: URL?)] = []
        do {
            for (name, url) in locations.byName.sorted(by: { $0.key < $1.key }) {
                guard var contents = files[name] else { continue }
                if name == "config.json" { contents = try Self.keepingLocalTrust(contents, at: url) }
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let saved = fileManager.fileExists(atPath: url.path) ? try fileManager.setAside(url, label: "pre-import", moving: false, now: now) : nil
                replaced.append((url, saved))
                try write(contents, url)
            }
        } catch {
            for (url, saved) in replaced.reversed() {
                BestEffort.attempt("roll back \(url.lastPathComponent)") {
                    if let saved {
                        _ = try fileManager.replaceItemAt(url, withItemAt: saved, backupItemName: nil, options: [])
                        try fileManager.copyItem(at: url, to: saved)
                    } else if fileManager.fileExists(atPath: url.path) {
                        try fileManager.removeItem(at: url)
                    }
                }
            }
            throw error
        }
        scripts.directories = scriptDirectories
    }

    private static func keepingLocalTrust(_ contents: Data, at url: URL) throws -> Data {
        var config = try FoundryConfigMigration.migrate(contents)
        let current = BestEffort.attempt("read current config for script trust") {
            try FoundryConfigMigration.migrate(Data(contentsOf: url))
        }
        config.localState.trustedScriptDirectories = current?.localState.trustedScriptDirectories ?? []
        return try JSONEncoder().encode(config)
    }

    enum BackupError: LocalizedError, Equatable {
        case notABackup
        case newerVersion
        case damaged(String)

        var errorDescription: String? {
            switch self {
            case .notABackup: "This file isn't a Foundry backup."
            case .newerVersion: "This backup was made by a newer version of Foundry."
            case let .damaged(name): "The backup's \(name) is damaged."
            }
        }
    }
}

extension FileManager {
    @discardableResult
    func setAside(_ url: URL, label: String, moving: Bool, now: Date = Date()) throws -> URL {
        let stamp = now.formatted(Date.ISO8601FormatStyle(dateSeparator: .omitted, timeSeparator: .omitted))
        let name = "\(url.lastPathComponent).\(label)-\(stamp)"
        var aside = url.deletingLastPathComponent().appendingPathComponent(name)
        var attempt = 2
        while fileExists(atPath: aside.path) {
            aside = url.deletingLastPathComponent().appendingPathComponent("\(name)-\(attempt)")
            attempt += 1
        }
        if moving { try moveItem(at: url, to: aside) } else { try copyItem(at: url, to: aside) }
        return aside
    }
}
