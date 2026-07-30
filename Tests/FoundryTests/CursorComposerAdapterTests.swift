import XCTest
@testable import Foundry

final class CursorComposerAdapterTests: XCTestCase {
    func testQueryReadsCurrentComposerDataFromCursorDiskKV() {
        let query = CursorComposerAdapter.query

        XCTAssertTrue(query.contains("cursorDiskKV"))
        XCTAssertTrue(query.contains("composerData:%"))
        XCTAssertTrue(query.contains("workspaceIdentifier.id"))
        XCTAssertFalse(query.contains("UPDATE"))
        XCTAssertFalse(query.contains("DELETE"))
    }

    func testParsesComposerDataRows() throws {
        let row = [
            hex("composer-1"),
            hex("Performance optimization"),
            hex("Edited 3 files"),
            hex("workspace-1"),
            "1785444000000",
            "1785444060000",
            hex("completed"),
            "0",
            "0",
            "0",
            "1",
            "3",
            "42",
            "18"
        ].joined(separator: "\t")

        let snapshot = try XCTUnwrap(CursorComposerAdapter.snapshots(from: row).first)

        XCTAssertEqual(snapshot.id, "composer-1")
        XCTAssertEqual(snapshot.title, "Performance optimization")
        XCTAssertEqual(snapshot.subtitle, "Edited 3 files")
        XCTAssertEqual(snapshot.workspaceID, "workspace-1")
        XCTAssertEqual(snapshot.status, "completed")
        XCTAssertTrue(snapshot.hasUnreadMessages)
        XCTAssertEqual(snapshot.filesChangedCount, 3)
        XCTAssertEqual(snapshot.totalLinesAdded, 42)
        XCTAssertEqual(snapshot.totalLinesRemoved, 18)
    }

    private func hex(_ value: String) -> String {
        Data(value.utf8).map { String(format: "%02X", $0) }.joined()
    }
}
