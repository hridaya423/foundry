import Foundation

final class UsageRankingStore: @unchecked Sendable {
    private struct StoredUsage: Codable {
        var records: [String: UsageRecord] = [:]
    }

    private struct UsageRecord: Codable {
        var openCount: Int
        var lastOpenedAt: Date
    }

    private let diagnostics: DiagnosticsService
    private let lock = NSLock()
    private var usage: StoredUsage

    init(diagnostics: DiagnosticsService) {
        self.diagnostics = diagnostics
        self.usage = Self.load() ?? StoredUsage()
        diagnostics.log("Loaded usage ranking for \(usage.records.count) results")
    }

    static var usageURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".local/share/foundry/usage.json")
    }

    func recordExecution(resultID: String) {
        let now = Date()
        lock.lock()
        var record = usage.records[resultID] ?? UsageRecord(openCount: 0, lastOpenedAt: now)
        record.openCount += 1
        record.lastOpenedAt = now
        usage.records[resultID] = record
        let snapshot = usage
        lock.unlock()
        save(snapshot)
    }

    func adjustedScore(for result: CommandResult) -> Double {
        lock.lock()
        let record = usage.records[result.id]
        lock.unlock()

        guard let record else { return result.score }

        let frequencyBoost = min(log(Double(record.openCount) + 1) * 4.0, 12.0)
        let hoursSinceOpen = max(Date().timeIntervalSince(record.lastOpenedAt) / 3600, 0)
        let recencyBoost = max(8.0 - hoursSinceOpen * 0.35, 0)

        return result.score + frequencyBoost + recencyBoost
    }

    private func save(_ snapshot: StoredUsage) {
        do {
            let url = Self.usageURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            diagnostics.log("Failed to save usage ranking: \(error.localizedDescription)")
        }
    }

    private static func load() -> StoredUsage? {
        let url = usageURL
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StoredUsage.self, from: data)
    }
}
