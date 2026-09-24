import XCTest
@testable import Foundry

final class FoundryBackupTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDown() {
        roots.forEach { try? FileManager.default.removeItem(at: $0) }
        super.tearDown()
    }

    private func locations() -> FoundryBackup.Locations {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("backup-\(UUID())")
        roots.append(root)
        return .init(config: root.appendingPathComponent("config.json"), snippets: root.appendingPathComponent("snippets.json"), quicklinks: root.appendingPathComponent("quicklinks.json"), usage: root.appendingPathComponent("data/usage.json"))
    }

    private func scriptStore() -> ScriptDirectoryStore {
        let suite = "foundry.backup.tests.\(UUID())"
        return ScriptDirectoryStore(defaults: UserDefaults(suiteName: suite)!)
    }

    private func seed(_ locations: FoundryBackup.Locations) throws {
        try FileManager.default.createDirectory(at: locations.usage.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(FoundryConfig(hotkey: .optionSpace)).write(to: locations.config)
        try Data("[]".utf8).write(to: locations.snippets)
        try JSONEncoder().encode(QuicklinkTemplate.defaults).write(to: locations.quicklinks)
        try Data(#"{"entries":{}}"#.utf8).write(to: locations.usage)
    }

    func testRoundTripRestoresFilesAndFoldersButNotTrust() throws {
        let source = locations(), destination = locations()
        try seed(source)
        let backup = try FoundryBackup.make(locations: source, scriptDirectories: ["/tmp/scripts"], appVersion: "1.1.0")
        let decoded = try FoundryBackup.decode(backup.encoded())
        XCTAssertEqual(decoded.files.count, 4)

        let scripts = scriptStore()
        try decoded.restore(to: destination, scripts: scripts)
        for (name, url) in source.byName {
            XCTAssertEqual(try Data(contentsOf: destination.byName[name]!), try Data(contentsOf: url), name)
        }
        XCTAssertEqual(scripts.directories, ["/tmp/scripts"])
        XCTAssertFalse(scripts.isTrusted("/tmp/scripts"))
    }

    func testRestoreKeepsPreImportCopiesAndLeavesMissingFilesAlone() throws {
        let source = locations(), destination = locations()
        try FileManager.default.createDirectory(at: source.config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(FoundryConfig()).write(to: source.config)
        try seed(destination)
        let oldConfig = try Data(contentsOf: destination.config)
        let oldSnippets = try Data(contentsOf: destination.snippets)

        let backup = try FoundryBackup.make(locations: source, scriptDirectories: [], appVersion: "1.1.0")
        XCTAssertEqual(Array(backup.files.keys), ["config.json"])
        try backup.restore(to: destination, scripts: scriptStore())

        XCTAssertEqual(try Data(contentsOf: destination.config.appendingPathExtension("pre-import")), oldConfig)
        XCTAssertEqual(try Data(contentsOf: destination.snippets), oldSnippets)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.snippets.appendingPathExtension("pre-import").path))
    }

    func testDecodeRejectsForeignNewerUnknownAndDamagedBackups() throws {
        XCTAssertThrowsError(try FoundryBackup.decode(Data("{}".utf8))) { XCTAssertEqual($0 as? FoundryBackup.BackupError, .notABackup) }

        let source = locations()
        try seed(source)
        var backup = try FoundryBackup.make(locations: source, scriptDirectories: [], appVersion: "1.1.0")

        var newer = backup
        newer.version = FoundryBackup.currentVersion + 1
        XCTAssertThrowsError(try FoundryBackup.decode(newer.encoded())) { XCTAssertEqual($0 as? FoundryBackup.BackupError, .newerVersion) }

        var unknown = backup
        unknown.files["../../.zshrc"] = Data("x".utf8)
        XCTAssertThrowsError(try FoundryBackup.decode(unknown.encoded())) { XCTAssertEqual($0 as? FoundryBackup.BackupError, .damaged("../../.zshrc")) }

        backup.files["config.json"] = Data("not json".utf8)
        XCTAssertThrowsError(try FoundryBackup.decode(backup.encoded())) { XCTAssertEqual($0 as? FoundryBackup.BackupError, .damaged("config.json")) }
    }
}
