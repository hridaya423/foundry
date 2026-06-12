import Foundation

final class UsageRankingStore {
    private struct StoredUsage: Codable {
        var records: [String: UsageRecord] = [:]
    }

    private struct UsageRecord: Codable {
        var openCount: Int
        var lastOpenedAt: Date
    }

    private let diagnostics: DiagnosticsService
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
        var record = usage.records[resultID] ?? UsageRecord(openCount: 0, lastOpenedAt: now)
        record.openCount += 1
        record.lastOpenedAt = now
        usage.records[resultID] = record
        save()
    }

    func adjustedScore(for result: CommandResult) -> Double {
        guard let record = usage.records[result.id] else { return result.score }

        let frequencyBoost = min(log(Double(record.openCount) + 1) * 4.0, 12.0)
        let hoursSinceOpen = max(Date().timeIntervalSince(record.lastOpenedAt) / 3600, 0)
        let recencyBoost = max(8.0 - hoursSinceOpen * 0.35, 0)

        return result.score + frequencyBoost + recencyBoost
    }

    private func save() {
        do {
            let url = Self.usageURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(usage)
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
