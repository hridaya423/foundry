import XCTest
@testable import Foundry
import FoundryDomain

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
        ScriptDirectoryStore(localState: LocalStateStore())
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
        for (name, url) in source.byName where url != source.config {
            XCTAssertEqual(try Data(contentsOf: destination.byName[name]!), try Data(contentsOf: url), name)
        }
        XCTAssertEqual(try JSONDecoder().decode(FoundryConfig.self, from: Data(contentsOf: destination.config)),
                       try JSONDecoder().decode(FoundryConfig.self, from: Data(contentsOf: source.config)))
        XCTAssertEqual(scripts.directories, ["/tmp/scripts"])
        XCTAssertFalse(scripts.isTrusted("/tmp/scripts"))
    }

    func testRestoreKeepsThisMachinesScriptTrustNotTheBackups() throws {
        let source = locations(), destination = locations()
        var imported = FoundryConfig()
        imported.localState.trustedScriptDirectories = ["/tmp/evil"]
        var local = FoundryConfig()
        local.localState.trustedScriptDirectories = ["/tmp/mine"]
        for (config, url) in [(imported, source.config), (local, destination.config)] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(config).write(to: url)
        }

        let backup = try FoundryBackup.decode(FoundryBackup.make(locations: source, scriptDirectories: [], appVersion: "1.1.0").encoded())
        try backup.restore(to: destination, scripts: scriptStore())

        let restored = try JSONDecoder().decode(FoundryConfig.self, from: Data(contentsOf: destination.config))
        XCTAssertEqual(restored.localState.trustedScriptDirectories, ["/tmp/mine"])
    }

    /// Browser, media folder, consent, and recents now live on config.json —
    /// the backup carries them for free.
    func testRoundTripCarriesLocalStateInsideConfig() throws {
        let source = locations(), destination = locations()
        var config = FoundryConfig()
        config.localState.mainBrowser = "firefox"
        config.localState.mediaDownloadFolder = "/tmp/dl"
        config.localState.launchAtLoginConsent = true
        config.localState.colorPickerRecents = ["#FF0000"]
        try FileManager.default.createDirectory(at: source.config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(config).write(to: source.config)

        let backup = try FoundryBackup.make(locations: source, scriptDirectories: [], appVersion: "1.1.0")
        let decoded = try FoundryBackup.decode(backup.encoded())
        try decoded.restore(to: destination, scripts: scriptStore())

        let restored = try JSONDecoder().decode(FoundryConfig.self, from: Data(contentsOf: destination.config))
        XCTAssertEqual(restored.localState.mainBrowser, "firefox")
        XCTAssertEqual(restored.localState.mediaDownloadFolder, "/tmp/dl")
        XCTAssertTrue(restored.localState.launchAtLoginConsent)
        XCTAssertEqual(restored.localState.colorPickerRecents, ["#FF0000"])
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

        XCTAssertEqual(try preImportCopies(of: destination.config).map { try Data(contentsOf: $0) }, [oldConfig])
        XCTAssertEqual(try Data(contentsOf: destination.snippets), oldSnippets)
        XCTAssertEqual(try preImportCopies(of: destination.snippets), [])
    }

    func testEachImportKeepsItsOwnPreImportCopy() throws {
        let source = locations(), destination = locations()
        try seed(source)
        try seed(destination)
        let original = try Data(contentsOf: destination.config)
        let backup = try FoundryBackup.make(locations: source, scriptDirectories: [], appVersion: "1.1.0")

        try backup.restore(to: destination, scripts: scriptStore(), now: Date(timeIntervalSince1970: 1_000))
        try backup.restore(to: destination, scripts: scriptStore(), now: Date(timeIntervalSince1970: 2_000))

        let copies = try preImportCopies(of: destination.config)
        XCTAssertEqual(copies.count, 2)
        XCTAssertTrue(try copies.contains { try Data(contentsOf: $0) == original })
    }

    func testFailedRestorePutsBackEveryFileItReplaced() throws {
        let source = locations(), destination = locations()
        try seed(source)
        try JSONEncoder().encode([StoredSnippet(title: "From backup", content: "x")]).write(to: source.snippets)
        try Data("[]".utf8).write(to: source.quicklinks)
        try seed(destination)
        let before = try destination.byName.mapValues { try Data(contentsOf: $0) }
        let backup = try FoundryBackup.make(locations: source, scriptDirectories: ["/tmp/new"], appVersion: "1.1.0")
        XCTAssertNotEqual(backup.files["quicklinks.json"], before["quicklinks.json"])
        let scripts = scriptStore()
        let scriptsBefore = scripts.directories
        struct DiskFull: Error {}

        XCTAssertThrowsError(try backup.restore(to: destination, scripts: scripts) { data, url in
            guard url != destination.snippets else { throw DiskFull() }
            try data.write(to: url, options: .atomic)
        })

        for (name, url) in destination.byName {
            XCTAssertEqual(try Data(contentsOf: url), before[name], name)
        }
        XCTAssertEqual(scripts.directories, scriptsBefore)
    }

    private func preImportCopies(of url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("\(url.lastPathComponent).pre-import-") }
    }

    func testDecodeRefusesAGlobalShortcutWithNoModifier() throws {
        let source = locations()
        try seed(source)
        var config = FoundryConfig()
        config.commandPreferences["system.lock"] = CommandPreference(globalHotkey: CommandHotkey(keyCode: 0, modifiers: 0, displayName: "A"))
        try JSONEncoder().encode(config).write(to: source.config)
        let backup = try FoundryBackup.make(locations: source, scriptDirectories: [], appVersion: "1.1.0")

        XCTAssertThrowsError(try FoundryBackup.decode(backup.encoded())) { XCTAssertEqual($0 as? FoundryBackup.BackupError, .bareHotkey("A")) }
    }

    func testImportSummaryNamesNewShortcutsEndpointsAndScriptFolders() throws {
        let source = locations()
        try seed(source)
        var config = FoundryConfig(hotkey: .optionSpace)
        config.commandPreferences["system.lock"] = CommandPreference(globalHotkey: CommandHotkey(keyCode: 37, modifiers: 256, displayName: "⌘L"))
        var profile = AIProviderProfile.ollamaDefault
        profile.endpoint = "https://ai.attacker.example"
        config.ai.profiles = [profile]
        try JSONEncoder().encode(config).write(to: source.config)
        let backup = try FoundryBackup.make(locations: source, scriptDirectories: ["/tmp/kept", "/tmp/new-scripts"], appVersion: "1.1.0")

        let changes = backup.sensitiveChanges(from: FoundryConfig(), scriptDirectories: ["/tmp/kept"])

        guard changes.count == 4 else { return XCTFail("expected four changes, got \(changes)") }
        XCTAssertTrue(changes[1].contains("⌘L for system.lock"))
        XCTAssertTrue(changes[2].contains("https://ai.attacker.example"))
        XCTAssertEqual(changes[3], "Script folders: /tmp/new-scripts")
        XCTAssertEqual(backup.sensitiveChanges(from: config, scriptDirectories: ["/tmp/kept", "/tmp/new-scripts"]), [])
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
