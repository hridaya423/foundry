import Foundation
import XCTest
@testable import Foundry

final class AgentIntegrationTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoundryAgentIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testClaudeInstallPreservesExistingHooksAndIsIdempotent() throws {
        let settingsURL = temporaryDirectory.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing: [String: Any] = [
            "permissions": ["allow": ["Bash"]],
            "hooks": [
                "PreToolUse": [
                    [
                        "matcher": "Bash",
                        "hooks": [["type": "command", "command": "/usr/local/bin/security-hook"]]
                    ]
                ]
            ]
        ]
        try JSONSerialization.data(withJSONObject: existing).write(to: settingsURL)

        let executableURL = URL(fileURLWithPath: "/Applications/Foundry.app/Contents/MacOS/Foundry")
        let installer = AgentIntegrationInstaller(homeDirectory: temporaryDirectory, executableURL: executableURL)
        try installer.install(.claude)
        try installer.install(.claude)

        let data = try Data(contentsOf: settingsURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((root["permissions"] as? [String: Any])?["allow"] as? [String], ["Bash"])
        XCTAssertTrue(installer.status(for: .claude).installed)

        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let preToolGroups = try XCTUnwrap(hooks["PreToolUse"] as? [Any])
        let managedHandlers = preToolGroups.compactMap { $0 as? [String: Any] }
            .flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
            .filter { $0["args"] as? [String] == ["--agent-bridge", "claude"] }
        XCTAssertEqual(managedHandlers.count, 1)
    }

    func testOpenCodeInstallRefusesToReplaceUnrelatedPlugin() throws {
        let pluginURL = temporaryDirectory.appendingPathComponent(".config/opencode/plugins/foundry-agent-bridge.js")
        try FileManager.default.createDirectory(at: pluginURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "export const ExistingPlugin = async () => ({})".write(to: pluginURL, atomically: true, encoding: .utf8)

        let installer = AgentIntegrationInstaller(homeDirectory: temporaryDirectory, executableURL: URL(fileURLWithPath: "/Foundry"))
        XCTAssertThrowsError(try installer.install(.opencode)) { error in
            XCTAssertEqual(error as? AgentIntegrationInstallError, .existingPlugin(pluginURL))
        }
    }

    func testOpenCodeInstallIsIdempotent() throws {
        let installer = AgentIntegrationInstaller(homeDirectory: temporaryDirectory, executableURL: URL(fileURLWithPath: "/Foundry"))
        try installer.install(.opencode)
        let first = try String(contentsOf: installer.openCodePluginURL, encoding: .utf8)
        try installer.install(.opencode)
        let second = try String(contentsOf: installer.openCodePluginURL, encoding: .utf8)

        XCTAssertEqual(first, second)
        XCTAssertTrue(second.contains(AgentIntegrationInstaller.managedOpenCodeMarker))
        XCTAssertTrue(second.contains(#"["--agent-bridge", "opencode"]"#))
        XCTAssertTrue(second.contains("const foundryExecutable = "))
        XCTAssertTrue(second.contains("Foundry"))
        XCTAssertFalse(second.contains("agents.sock"))
        XCTAssertTrue(installer.status(for: .opencode).installed)
    }

    func testOpenCodeInstallUpgradesLegacyManagedPlugin() throws {
        let installer = AgentIntegrationInstaller(homeDirectory: temporaryDirectory, executableURL: URL(fileURLWithPath: "/Foundry"))
        try FileManager.default.createDirectory(at: installer.openCodePluginURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "const foundryAgentBridgeVersion = \"foundry-agent-bridge-v1\"".write(to: installer.openCodePluginURL, atomically: true, encoding: .utf8)

        try installer.install(.opencode)

        let content = try String(contentsOf: installer.openCodePluginURL, encoding: .utf8)
        XCTAssertTrue(content.contains(AgentIntegrationInstaller.managedOpenCodeMarker))
        XCTAssertFalse(content.contains(AgentIntegrationInstaller.legacyOpenCodeMarker))
    }

    func testClaudeHookPayloadNormalizesToolInput() throws {
        let envelope = try XCTUnwrap(AgentHookBridge.normalize(
            provider: .claude,
            object: [
                "hook_event_name": "PreToolUse",
                "session_id": "session-1",
                "tool_name": "Bash",
                "tool_input": ["command": "pwd"],
                "cwd": "/tmp/foundry"
            ]
        ))

        XCTAssertEqual(envelope.provider, .claude)
        XCTAssertEqual(envelope.sessionID, "session-1")
        XCTAssertEqual(envelope.origin, .hook)
        guard case let .toolActivity(name, detail, running) = envelope.event else {
            return XCTFail("Expected a tool activity event")
        }
        XCTAssertEqual(name, "Bash")
        XCTAssertEqual(detail, #"{"command":"pwd"}"#)
        XCTAssertTrue(running)
    }

    func testOpenCodeSessionPayloadNormalizesInfoMetadata() throws {
        let envelope = try XCTUnwrap(AgentHookBridge.normalize(
            provider: .opencode,
            object: [
                "type": "session.created",
                "properties": [
                    "info": [
                        "id": "session-1",
                        "title": "Foundry work",
                        "directory": "/tmp/foundry"
                    ]
                ]
            ]
        ))

        XCTAssertEqual(envelope.provider, .opencode)
        XCTAssertEqual(envelope.sessionID, "session-1")
        guard case let .sessionStart(metadata) = envelope.event else {
            return XCTFail("Expected a session start event")
        }
        XCTAssertEqual(metadata?.title, "Foundry work")
        XCTAssertEqual(metadata?.workingDirectory, "/tmp/foundry")
        XCTAssertEqual(metadata?.project, "foundry")
    }

    func testOpenCodeIdleStatusDoesNotReportWorking() throws {
        let envelope = try XCTUnwrap(AgentHookBridge.normalize(
            provider: .opencode,
            object: [
                "type": "session.status",
                "properties": [
                    "sessionID": "session-1",
                    "status": ["type": "idle"]
                ]
            ]
        ))

        XCTAssertEqual(envelope.event, .status(.recent))
    }

    func testCodexInstallPreservesConfigurationAndIsIdempotent() throws {
        let installer = AgentIntegrationInstaller(homeDirectory: temporaryDirectory, executableURL: URL(fileURLWithPath: "/Applications/Foundry.app/Contents/MacOS/Foundry"))
        try FileManager.default.createDirectory(at: installer.codexHooksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "/usr/local/bin/existing"]]]]]]
        try JSONSerialization.data(withJSONObject: existing).write(to: installer.codexHooksURL)
        try "model = \"gpt-5\"\n\n[features]\nhooks = false\n".write(to: installer.codexConfigURL, atomically: true, encoding: .utf8)

        try installer.install(.codex)
        let first = try Data(contentsOf: installer.codexHooksURL)
        try installer.install(.codex)

        XCTAssertEqual(first, try Data(contentsOf: installer.codexHooksURL))
        XCTAssertTrue(installer.status(for: .codex).installed)
        let installedRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: first) as? [String: Any])
        let installedHooks = try XCTUnwrap(installedRoot["hooks"] as? [String: Any])
        let stopGroups = try XCTUnwrap(installedHooks["Stop"] as? [[String: Any]])
        XCTAssertTrue(stopGroups.contains { group in
            (group["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String) == "/usr/local/bin/existing" } == true
        })
        XCTAssertTrue(try String(contentsOf: installer.codexConfigURL, encoding: .utf8).contains("model = \"gpt-5\""))
    }

    func testCodexFeatureUpdateDoesNotRewriteOtherTables() {
        let input = "[provider]\nhooks = false\n\n[features]\nsearch = true\n"
        let updated = AgentIntegrationInstaller.upsertCodexHooksFeature(input)

        XCTAssertTrue(updated.contains("[provider]\nhooks = false"))
        XCTAssertTrue(updated.contains("[features]\nhooks = true\nsearch = true"))
    }

    func testCodexStopRemainsAvailableForAnotherTurn() throws {
        let envelope = try XCTUnwrap(AgentHookBridge.normalize(
            provider: .codex,
            object: ["hook_event_name": "Stop", "session_id": "session-1"]
        ))

        XCTAssertEqual(envelope.event, .status(.recent))
    }

    func testCursorInstallPreservesUnrelatedHooksAndRemovesLegacyInteractiveBridge() throws {
        let installer = AgentIntegrationInstaller(homeDirectory: temporaryDirectory, executableURL: URL(fileURLWithPath: "/Applications/Foundry.app/Contents/MacOS/Foundry"))
        try FileManager.default.createDirectory(at: installer.cursorHooksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing: [String: Any] = [
            "custom": true,
            "hooks": [
                "sessionStart": [["command": "/usr/local/bin/existing"]],
                "beforeShellExecution": [["command": "'/old/Foundry' --agent-bridge cursor"]]
            ]
        ]
        try JSONSerialization.data(withJSONObject: existing).write(to: installer.cursorHooksURL)

        try installer.install(.cursor)

        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: installer.cursorHooksURL)) as? [String: Any])
        XCTAssertEqual(root["custom"] as? Bool, true)
        XCTAssertTrue(installer.status(for: .cursor).installed)
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual((hooks["sessionStart"] as? [[String: Any]])?.count, 2)
        XCTAssertNil(hooks["beforeShellExecution"])
    }

    func testCursorPayloadUsesStableParentConversationIdentity() throws {
        let envelope = try XCTUnwrap(AgentHookBridge.normalize(
            provider: .cursor,
            object: [
                "hook_event_name": "beforeSubmitPrompt",
                "parent_conversation_id": "parent-1",
                "conversation_id": "child-1",
                "prompt": "Continue",
                "cwd": "/tmp/foundry"
            ]
        ))

        XCTAssertEqual(envelope.provider, .cursor)
        XCTAssertEqual(envelope.sessionID, "parent-1")
        XCTAssertEqual(envelope.event, .userPrompt("Continue"))
    }

    func testBridgeSendsEnvelopeToSocketServer() {
        let socketDirectory = URL(fileURLWithPath: "/tmp/foundry-agent-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: socketDirectory, withIntermediateDirectories: true)
        let socketURL = socketDirectory.appendingPathComponent("agents.sock")
        let server = AgentEventSocketServer(socketURL: socketURL)
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: socketDirectory)
        }
        XCTAssertTrue(server.start { envelope in
            .accepted(requestID: envelope.requestID)
        })

        let envelope = AgentEventEnvelope(
            requestID: "request-1",
            provider: .claude,
            sessionID: "session-1",
            origin: .hook,
            event: .sessionStart(metadata: nil)
        )
        XCTAssertTrue(AgentHookBridge.send(envelope, socketURL: socketURL))
    }
}
