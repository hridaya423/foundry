import XCTest
import FoundryDomain
import FoundryServices
@testable import Foundry

@MainActor
final class ScriptCommandTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-scripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDirectiveParsing() throws {
        let script = try XCTUnwrap(ScriptDirectives.parse("""
        #!/bin/bash
        # @raycast.schemaVersion 1
        # @raycast.title Open Project
        # @raycast.mode fullOutput
        # @raycast.packageName Dev
        # @raycast.argument1 { "type": "text", "placeholder": "Name" }
        # @raycast.madeUp yes
        """, path: "/tmp/open.sh"))
        XCTAssertEqual(script.title, "Open Project")
        XCTAssertEqual(script.mode, .fullOutput)
        XCTAssertEqual(script.packageName, "Dev")
        XCTAssertEqual(script.arguments, [ScriptArgument(placeholder: "Name", optional: false)])
        XCTAssertEqual(script.warnings, ["Unknown directive @raycast.madeUp ignored"])
        XCTAssertNil(ScriptDirectives.parse("# @raycast.mode silent", path: "/tmp/x.sh"))
    }

    func testScanOnlyIncludesExecutableScriptsWithTitles() throws {
        try writeScript("a.sh", body: "echo hi", title: "Say Hi")
        try writeScript("b.sh", body: "echo hi", title: "Not Executable", executable: false)
        try writeScript("c.sh", body: "echo hi", title: nil)
        XCTAssertEqual(ScriptCommandProvider.scan(directory.path).map(\.title), ["Say Hi"])
    }

    func testProviderRequiresArgumentThenRunsWithIt() async throws {
        try writeScript("greet.sh", body: "echo \"hi $1\"", title: "Greet", extra: "# @raycast.argument1 { \"type\": \"text\", \"placeholder\": \"Name\" }")
        let store = ScriptDirectoryStore(defaults: defaults)
        store.directories = [directory.path]
        let provider = ScriptCommandProvider(store: store)
        let bare = await provider.results(matching: "greet")
        XCTAssertEqual(bare.first?.primaryAction.kind, .fillQuery("Greet "))
        let filled = await provider.results(matching: "Greet Ada")
        XCTAssertEqual(filled.first?.primaryAction.kind, .runScript(path: directory.appendingPathComponent("greet.sh").path, arguments: ["Ada"], mode: .compact))
    }

    func testUntrustedFolderAsksOnceAndDenialBlocksTheRun() async throws {
        let path = try writeScript("touch.sh", body: "touch \"$PWD/ran\"", title: "Touch")
        let store = ScriptDirectoryStore(defaults: defaults)
        var prompts = 0
        let denied = runner(store: store) { _ in prompts += 1; return false }
        let deniedOutcome = await run(denied, path: path, mode: .silent)
        XCTAssertEqual(deniedOutcome, .denied(message: "Scripts in this folder are not trusted"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ran").path))

        let approving = runner(store: store) { _ in prompts += 1; return true }
        _ = await run(approving, path: path, mode: .silent)
        _ = await run(approving, path: path, mode: .silent)
        XCTAssertEqual(prompts, 2, "approved folders are not asked again")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ran").path))
    }

    func testCompactModeReportsLastLineAndFailuresReportStderr() async throws {
        let store = trustedStore()
        let ok = try writeScript("ok.sh", body: "echo first; echo last", title: "OK")
        let okOutcome = await run(runner(store: store), path: ok, mode: .compact)
        XCTAssertEqual(okOutcome, .success(message: "last"))
        let bad = try writeScript("bad.sh", body: "echo nope >&2; exit 3", title: "Bad")
        let badOutcome = await run(runner(store: store), path: bad, mode: .compact)
        XCTAssertEqual(badOutcome, .failure(message: "nope", retryable: true))
    }

    func testTimeoutAndOutputCap() async throws {
        let store = trustedStore()
        let slow = try writeScript("slow.sh", body: "sleep 5", title: "Slow")
        let slowOutcome = await run(runner(store: store, timeout: 0.3), path: slow, mode: .compact)
        XCTAssertEqual(slowOutcome, .failure(message: "slow.sh timed out after 0 s", retryable: true))

        let chatty = try writeScript("chatty.sh", body: "yes line | head -n 100000; echo END", title: "Chatty")
        let chattyOutcome = await run(runner(store: store, outputLimit: 1024), path: chatty, mode: .compact)
        XCTAssertNotEqual(chattyOutcome, .success(message: "END"), "output past the cap must be dropped")
    }

    private func trustedStore() -> ScriptDirectoryStore {
        let store = ScriptDirectoryStore(defaults: defaults)
        store.setTrusted(true, for: directory.path)
        return store
    }

    private func runner(store: ScriptDirectoryStore, timeout: TimeInterval = 5, outputLimit: Int = 256 * 1024, confirm: @escaping @MainActor (String) -> Bool = { _ in true }) -> ActionRunner {
        ActionRunner(diagnostics: DiagnosticsService(), openURL: { _ in true }, scriptDirectories: store, confirmScriptDirectory: confirm, scriptTimeout: timeout, scriptOutputLimit: outputLimit)
    }

    private func run(_ runner: ActionRunner, path: String, mode: ScriptOutputMode) async -> CommandOutcome {
        await runner.execute(CommandExecutionRequest(commandID: "script", action: CommandAction(id: "script.run", title: "Run", kind: .runScript(path: path, arguments: [], mode: mode)), cancellationID: UUID())) { _ in }
    }

    @discardableResult
    private func writeScript(_ name: String, body: String, title: String?, extra: String = "", executable: Bool = true) throws -> String {
        let url = directory.appendingPathComponent(name)
        let header = title.map { "# @raycast.title \($0)\n" } ?? ""
        try "#!/bin/bash\n\(header)\(extra)\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
        return url.path
    }
}
