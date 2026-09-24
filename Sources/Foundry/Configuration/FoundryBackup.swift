import Foundation

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
        return FoundryBackup(format: formatID, version: currentVersion, createdAt: now, appVersion: appVersion, files: files, scriptDirectories: scriptDirectories)
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
        guard let backup = try? decoder.decode(FoundryBackup.self, from: data), backup.format == formatID else { throw BackupError.notABackup }
        guard backup.version <= currentVersion else { throw BackupError.newerVersion }
        let known = Set(Locations.standard.byName.keys)
        for (name, contents) in backup.files {
            guard known.contains(name) else { throw BackupError.damaged(name) }
            let valid: Bool
            switch name {
            case "config.json": valid = (try? FoundryConfigMigration.migrate(contents)) != nil
            case "snippets.json": valid = (try? JSONDecoder().decode([StoredSnippet].self, from: contents)) != nil
            case "quicklinks.json": valid = (try? JSONDecoder().decode([Quicklink].self, from: contents)) != nil
            default: valid = (try? JSONSerialization.jsonObject(with: contents)) is [String: Any]
            }
            guard valid else { throw BackupError.damaged(name) }
        }
        return backup
    }

    func restore(to locations: Locations = .standard, scripts: ScriptDirectoryStore = .shared) throws {
        let fileManager = FileManager.default
        for (name, url) in locations.byName {
            guard let contents = files[name] else { continue }
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: url.path) {
                let saved = url.appendingPathExtension("pre-import")
                try? fileManager.removeItem(at: saved)
                try fileManager.copyItem(at: url, to: saved)
            }
            try contents.write(to: url, options: .atomic)
        }
        scripts.directories = scriptDirectories
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
