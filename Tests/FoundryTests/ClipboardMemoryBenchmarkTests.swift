import Darwin
import XCTest
@testable import Foundry
import FoundryServices

@MainActor
final class ClipboardMemoryBenchmarkTests: XCTestCase {
    /// Resident-memory footprint of a 1,000-entry clipboard history: items
    /// loaded through the real SQLite store into `ClipboardHistoryState`,
    /// with the filtered `visibleItems` cache materialized. No warm-up —
    /// the delta includes the one-time SQLite/page-cache cost a real
    /// first panel-open pays.
    func testResidentFootprintAtOneThousandEntries() async throws {
        guard let out = ProcessInfo.processInfo.environment["FOUNDRY_BENCH_OUT"] else { throw XCTSkip("set FOUNDRY_BENCH_OUT") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("clip-bench-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ClipboardHistoryStore(directory: directory, legacyURL: directory.appendingPathComponent("legacy.json"))
        let items = Self.fixtureItems(count: 1_000)
        try store.save(items)
        let diskBytes = Self.directoryBytes(directory)

        let baseline = Self.residentBytes()
        let state = ClipboardHistoryState(pasteboard: IdlePasteboard(), persistence: store)
        let visible = state.visibleItems
        let loaded = Self.residentBytes()
        await state.shutdown()

        let report: [String: Any] = [
            "driver": "Tests/FoundryTests/ClipboardMemoryBenchmarkTests.swift (in-process, SQLite store)",
            "entries": 1_000,
            "visibleEntries": visible.count,
            "payloadBytes": items.reduce(0) { $0 + $1.memoryCost },
            "sqliteDiskBytes": diskBytes,
            "rssBaselineBytes": baseline,
            "rssLoadedBytes": loaded,
            "rssDeltaBytes": loaded - baseline
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: out))
        XCTAssertEqual(visible.count, 1_000)
    }

    private static func residentBytes() -> Int {
        var info = task_basic_info_64()
        var count = mach_msg_type_number_t(MemoryLayout<task_basic_info_64>.stride) / 4
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO_64), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }

    private static func directoryBytes(_ directory: URL) -> Int {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return 0 }
        return entries.reduce(0) { total, name in
            let size = (try? FileManager.default.attributesOfItem(
                atPath: directory.appendingPathComponent(name).path)[.size] as? NSNumber)?.intValue
            return total + (size ?? 0)
        }
    }

    /// Text-heavy history mirroring real use: mostly short strings, a
    /// sprinkling of long pastes and links, occasional pinned entries.
    private static func fixtureItems(count: Int) -> [ClipboardHistoryItem] {
        let snippets = [
            "https://github.com/cognition-ai/devin/releases/tag/v2.4.1",
            "git commit -m \"Fix the clipboard merge regression\"",
            "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on",
            "func visibleItems(for query: String) -> [ClipboardHistoryItem] { items.filter { $0.matches(query) } }",
            "meet me at 3pm",
            "The lazy brown fox jumps over the quick dog near the riverbank while the committee reviews the quarterly plan",
            "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
            "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."
        ]
        var items: [ClipboardHistoryItem] = []
        items.reserveCapacity(count)
        for index in 0..<count {
            var text = snippets[index % snippets.count]
            if index % 37 == 0 { text = Array(repeating: text, count: 4).joined(separator: "\n") }
            items.append(ClipboardHistoryItem(
                payload: .text("\(index): \(text)"),
                createdAt: Date().addingTimeInterval(-Double(index) * 137),
                sourceBundleIdentifier: "com.example.source\(index % 7)",
                isPinned: index % 251 == 0
            ))
        }
        return items
    }
}

private final class IdlePasteboard: PasteboardClient {
    var changeCount: Int { 0 }
    func snapshot() -> PasteboardSnapshot? { nil }
    func write(_ payload: ClipboardPayload) {}
}
