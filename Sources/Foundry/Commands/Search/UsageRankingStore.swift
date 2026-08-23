import Foundation
import FoundryDomain
import FoundryServices

final class UsageRankingStore: @unchecked Sendable {
    private struct StoredUsage: Codable {
        var records: [String: UsageRecord] = [:]
        var queryRecords: [String: [String: UsageRecord]] = [:]

        private enum CodingKeys: String, CodingKey {
            case records
            case queryRecords
        }

        init(records: [String: UsageRecord] = [:], queryRecords: [String: [String: UsageRecord]] = [:]) {
            self.records = records
            self.queryRecords = queryRecords
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            records = try container.decodeIfPresent([String: UsageRecord].self, forKey: .records) ?? [:]
            queryRecords = try container.decodeIfPresent([String: [String: UsageRecord]].self, forKey: .queryRecords) ?? [:]
        }
    }

    private struct UsageRecord: Codable {
        var openCount: Int
        var lastOpenedAt: Date
    }

    private let diagnostics: DiagnosticsService
    private let storageURL: URL
    private let lock = NSLock()
    private let persistenceLock = NSLock()
    private var usage: StoredUsage
    private var revision = 0
    private var persistedRevision = 0

    init(diagnostics: DiagnosticsService, url: URL = UsageRankingStore.usageURL) {
        self.diagnostics = diagnostics
        self.storageURL = url
        self.usage = Self.load(from: url) ?? StoredUsage()
        diagnostics.log("Loaded usage ranking for \(usage.records.count) results")
    }

    static var usageURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".local/share/foundry/usage.json")
    }

    func recordExecution(resultID: String, query: String? = nil) {
        let now = Date()
        let snapshot: (StoredUsage, Int) = lock.withLock {
            var record = usage.records[resultID] ?? UsageRecord(openCount: 0, lastOpenedAt: now)
            record.openCount += 1
            record.lastOpenedAt = now
            usage.records[resultID] = record
            for queryKey in queryKeys(for: query).map(\.key) {
                var queryRecords = usage.queryRecords[queryKey] ?? [:]
                var queryRecord = queryRecords[resultID] ?? UsageRecord(openCount: 0, lastOpenedAt: now)
                queryRecord.openCount += 1
                queryRecord.lastOpenedAt = now
                queryRecords[resultID] = queryRecord
                if queryRecords.count > 16 {
                    let retainedIDs = queryRecords
                        .sorted { $0.value.lastOpenedAt > $1.value.lastOpenedAt }
                        .prefix(16)
                        .map(\.key)
                    queryRecords = queryRecords.filter { retainedIDs.contains($0.key) }
                }
                usage.queryRecords[queryKey] = queryRecords
                trimQueryRecords()
            }
            revision += 1
            return (usage, revision)
        }
        save(snapshot.0, revision: snapshot.1)
    }

    func usageBoost(for resultID: String, query: String? = nil) -> Double {
        lock.lock()
        let globalRecord = usage.records[resultID]
        let queryBoost = queryKeys(for: query)
            .compactMap { key, weight in
                usage.queryRecords[key]?[resultID].map { boost(for: $0, frequencyScale: 0.7, frequencyCap: 2.0, recencyCap: 1.2, recencyDecay: 0.05) * weight }
            }
            .max() ?? 0
        lock.unlock()

        let globalBoost = boost(for: globalRecord, frequencyScale: 0.16, frequencyCap: 0.5, recencyCap: 0.35, recencyDecay: 0.05)
        return globalBoost + queryBoost
    }

    func usageBoosts(for resultIDs: [String], query: String?) -> [String: Double] {
        let keys = queryKeys(for: query)
        let now = Date()
        return lock.withLock {
            Dictionary(resultIDs.map { resultID in
                let globalBoost = boost(
                    for: usage.records[resultID],
                    now: now,
                    frequencyScale: 0.16,
                    frequencyCap: 0.5,
                    recencyCap: 0.35,
                    recencyDecay: 0.05
                )
                let queryBoost = keys.compactMap { key, weight in
                    usage.queryRecords[key]?[resultID].map {
                        boost(
                            for: $0,
                            now: now,
                            frequencyScale: 0.7,
                            frequencyCap: 2.0,
                            recencyCap: 1.2,
                            recencyDecay: 0.05
                        ) * weight
                    }
                }.max() ?? 0
                return (resultID, globalBoost + queryBoost)
            }, uniquingKeysWith: { _, last in last })
        }
    }

    func resetRanking(for resultID: String) {
        let snapshot: (StoredUsage, Int) = lock.withLock {
            usage.records.removeValue(forKey: resultID)
            for key in usage.queryRecords.keys {
                usage.queryRecords[key]?.removeValue(forKey: resultID)
                if usage.queryRecords[key]?.isEmpty == true {
                    usage.queryRecords.removeValue(forKey: key)
                }
            }
            revision += 1
            return (usage, revision)
        }
        save(snapshot.0, revision: snapshot.1)
    }

    private func boost(for record: UsageRecord?, frequencyScale: Double, frequencyCap: Double, recencyCap: Double, recencyDecay: Double) -> Double {
        boost(
            for: record,
            now: Date(),
            frequencyScale: frequencyScale,
            frequencyCap: frequencyCap,
            recencyCap: recencyCap,
            recencyDecay: recencyDecay
        )
    }

    private func boost(for record: UsageRecord?, now: Date, frequencyScale: Double, frequencyCap: Double, recencyCap: Double, recencyDecay: Double) -> Double {
        guard let record else { return 0 }

        let frequencyBoost = min(log(Double(record.openCount) + 1) * frequencyScale, frequencyCap)
        let hoursSinceOpen = max(now.timeIntervalSince(record.lastOpenedAt) / 3600, 0)
        let recencyBoost = max(recencyCap - hoursSinceOpen * recencyDecay, 0)
        return frequencyBoost + recencyBoost
    }

    private func trimQueryRecords() {
        guard usage.queryRecords.count > 256 else { return }
        let retainedKeys = usage.queryRecords
            .sorted { latestDate(for: $0.value) > latestDate(for: $1.value) }
            .prefix(256)
            .map(\.key)
        usage.queryRecords = usage.queryRecords.filter { retainedKeys.contains($0.key) }
    }

    private func latestDate(for records: [String: UsageRecord]) -> Date {
        records.values.map(\.lastOpenedAt).max() ?? .distantPast
    }

    private func save(_ snapshot: StoredUsage, revision: Int) {
        persistenceLock.lock()
        defer { persistenceLock.unlock() }
        guard revision > persistedRevision else { return }
        do {
            let url = storageURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
            persistedRevision = revision
        } catch {
            diagnostics.log("Failed to save usage ranking: \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) -> StoredUsage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StoredUsage.self, from: data)
    }

    private func queryKeys(for query: String?) -> [(key: String, weight: Double)] {
        guard let query else { return [] }
        let normalized = SearchScoring.normalize(query)
        guard normalized.isEmpty == false else { return [] }

        var values: [(key: String, weight: Double)] = [(hash(normalized), 1)]
        let maximumPrefixLength = min(normalized.count, 12)
        if maximumPrefixLength >= 2 {
            for length in stride(from: maximumPrefixLength - 1, through: 2, by: -1) {
                let prefix = String(normalized.prefix(length))
                let weight = max(0.25, Double(length) / Double(maximumPrefixLength) * 0.65)
                values.append((hash(prefix), weight))
            }
        }
        return values
    }

    private func hash(_ normalized: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}
