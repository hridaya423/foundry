import Foundation
import XCTest
@testable import Foundry

final class CodexDesktopThreadAdapterTests: XCTestCase {
    func testQueryTargetsAuthoritativeDesktopCatalog() {
        let query = CodexDesktopThreadAdapter.threadsQuery(limit: 9)

        XCTAssertTrue(query.contains("source = 'vscode'"))
        XCTAssertTrue(query.contains("archived = 0"))
        XCTAssertTrue(query.contains("hex(rollout_path)"))
        XCTAssertTrue(query.contains("LIMIT 9"))
        XCTAssertFalse(query.contains("INSERT"))
        XCTAssertFalse(query.contains("UPDATE"))
        XCTAssertFalse(query.contains("DELETE"))
    }

    func testParsesHexRowsAndDeduplicatesThreads() throws {
        let now = Date()
        let row = makeRow(
            id: "thread-1",
            rolloutPath: "/tmp/rollout.jsonl",
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now,
            title: "Title\nignored",
            cwd: "/tmp/foundry",
            modelProvider: "openai",
            model: "gpt-test",
            gitBranch: "main",
            firstUserMessage: "Prompt",
            preview: "Preview\nignored",
            threadSource: "user"
        )

        let snapshots = CodexDesktopThreadAdapter.snapshots(
            fromSQLiteOutput: row + "\n" + row,
            now: now,
            activityResolver: { _, _, _ in true }
        )
        let snapshot = try XCTUnwrap(snapshots.first)

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshot.title, "Title")
        XCTAssertEqual(snapshot.preview, "Preview")
        XCTAssertEqual(snapshot.cwd, "/tmp/foundry")
        XCTAssertEqual(snapshot.model, "gpt-test")
        XCTAssertTrue(snapshot.isProcessing)
        XCTAssertFalse(snapshot.titleIsPrompt)
    }

    func testPromptTitleIsMarkedForSummarization() throws {
        let now = Date()
        let row = makeRow(
            id: "thread-1",
            rolloutPath: "/tmp/rollout.jsonl",
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now,
            title: "Research wearable health tracking",
            cwd: "/tmp/foundry",
            modelProvider: "openai",
            model: "gpt-test",
            gitBranch: "main",
            firstUserMessage: "Research wearable health tracking",
            preview: "Research wearable health tracking",
            threadSource: "user"
        )

        let snapshot = try XCTUnwrap(CodexDesktopThreadAdapter.snapshots(
            fromSQLiteOutput: row,
            now: now,
            activityResolver: { _, _, _ in false }
        ).first)

        XCTAssertTrue(snapshot.titleIsPrompt)
    }

    func testCompletedRolloutIsNotProcessing() throws {
        let rollout = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-codex-\(UUID().uuidString).jsonl")
        try Data("""
        {"payload":{"type":"task_started"}}
        {"payload":{"type":"task_complete"}}
        """.utf8).write(to: rollout)
        defer { try? FileManager.default.removeItem(at: rollout) }

        XCTAssertFalse(CodexDesktopThreadAdapter.isRolloutProcessing(
            rolloutPath: rollout.path,
            updatedAt: Date(),
            now: Date()
        ))
    }

    func testRecentNonterminalRolloutIsProcessing() throws {
        let rollout = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-codex-\(UUID().uuidString).jsonl")
        try Data("""
        {"payload":{"type":"task_started"}}
        {"payload":{"type":"custom_tool_call"}}
        """.utf8).write(to: rollout)
        defer { try? FileManager.default.removeItem(at: rollout) }

        XCTAssertTrue(CodexDesktopThreadAdapter.isRolloutProcessing(
            rolloutPath: rollout.path,
            updatedAt: Date(),
            now: Date()
        ))
    }

    private func makeRow(
        id: String,
        rolloutPath: String,
        createdAt: Date,
        updatedAt: Date,
        title: String,
        cwd: String,
        modelProvider: String,
        model: String,
        gitBranch: String,
        firstUserMessage: String,
        preview: String,
        threadSource: String
    ) -> String {
        [
            hex(id),
            hex(rolloutPath),
            String(Int(createdAt.timeIntervalSince1970 * 1_000)),
            String(Int(updatedAt.timeIntervalSince1970 * 1_000)),
            hex(title),
            hex(cwd),
            "0",
            hex(modelProvider),
            hex(model),
            hex(gitBranch),
            hex(firstUserMessage),
            hex(preview),
            hex(threadSource)
        ].joined(separator: CodexDesktopThreadAdapter.sqliteSeparator)
    }

    private func hex(_ value: String) -> String {
        Data(value.utf8).map { String(format: "%02X", $0) }.joined()
    }
}
