import Foundation
import FoundryDomain

final class CommandRanker: Sendable {
    private let usageRanking: UsageRankingStore
    private let configService: ConfigService?

    private static let homeLeads = ["foundry.clipboard-history", "foundry.ai", "foundry.snippets", "foundry.emoji-picker", "foundry.file-shelf"]

    init(usageRanking: UsageRankingStore, configService: ConfigService?) {
        self.usageRanking = usageRanking
        self.configService = configService
    }

    func deduplicated(_ candidates: [RankCandidate]) -> [RankCandidate] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.result.id).inserted }
    }

    func ordered(_ candidates: [RankCandidate], query: String?) -> [CommandResult] {
        let preferences = configService?.current.commandPreferences ?? [:]
        let sensitivity = configService?.current.searchSensitivity ?? .medium
        let normalizedQuery = query.map { SearchScoring.PreparedQuery(query: $0) }
        let usageBoosts = usageRanking.usageBoosts(for: candidates.map { $0.result.id }, query: query)

        return candidates
            .map { candidate in
                let preference = preferences[candidate.result.id]
                let match = normalizedQuery.flatMap { normalizedQuery in
                    SearchScoring.matchPrepared(
                        query: normalizedQuery,
                        normalizedTitle: candidate.result.normalizedSearchTitle,
                        normalizedSubtitle: candidate.result.normalizedSearchSubtitle,
                        normalizedKeywords: candidate.result.normalizedSearchKeywords,
                        normalizedAliases: candidate.result.normalizedSearchAliases + (preference?.aliases ?? []).map(SearchScoring.normalize),
                        sensitivity: sensitivity
                    )
                }
                let base: Double
                if query == nil {
                    base = 0
                } else if let computed = candidate.result.payload.computedScore {
                    base = computed
                } else {
                    // Results a provider matched through channels we don't
                    // re-score (file contents, process tables) sit below the
                    // weakest real text match.
                    base = match?.score ?? 0.10
                }
                // Frecency contribution is capped below the smallest tier
                // gap (0.15): it reorders within a tier, never across one.
                let usage = min(usageBoosts[candidate.result.id] ?? 0, 3.2) * 0.04
                return RankedResult(
                    candidate: candidate,
                    preference: preference,
                    match: match,
                    score: candidate.result.payload.computedScore ?? base + usage + (preference?.favoriteRank == nil ? 0 : 0.01),
                    usageBoost: usageBoosts[candidate.result.id] ?? 0
                )
            }
            .sorted { lhs, rhs in
                // Home has no query score — favorites first by rank.
                if query == nil {
                    switch (lhs.preference?.favoriteRank, rhs.preference?.favoriteRank) {
                    case let (lhsRank?, rhsRank?) where lhsRank != rhsRank:
                        return lhsRank < rhsRank
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    default:
                        break
                    }
                    if lhs.usageBoost != rhs.usageBoost { return lhs.usageBoost > rhs.usageBoost }
                    let lhsLead = Self.homeLeads.firstIndex(of: lhs.candidate.result.id) ?? .max
                    let rhsLead = Self.homeLeads.firstIndex(of: rhs.candidate.result.id) ?? .max
                    if lhsLead != rhsLead { return lhsLead < rhsLead }
                } else if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }

                if lhs.candidate.result.payload.computedScore != nil, rhs.candidate.result.payload.computedScore != nil,
                   lhs.candidate.sourceOrder != rhs.candidate.sourceOrder {
                    return lhs.candidate.sourceOrder < rhs.candidate.sourceOrder
                }

                // Deterministic tie-breaks — a strict weak ordering, so the
                // sort is stable and repeatable.
                let lhsExact = lhs.match?.exactTokenCount ?? 0
                let rhsExact = rhs.match?.exactTokenCount ?? 0
                if lhsExact != rhsExact { return lhsExact > rhsExact }
                let lhsLength = lhs.match?.candidateLength ?? .max
                let rhsLength = rhs.match?.candidateLength ?? .max
                if lhsLength != rhsLength { return lhsLength < rhsLength }
                let titleComparison = lhs.candidate.result.title.localizedCaseInsensitiveCompare(rhs.candidate.result.title)
                if titleComparison != .orderedSame {
                    return titleComparison == .orderedAscending
                }
                if lhs.candidate.result.id != rhs.candidate.result.id {
                    return lhs.candidate.result.id < rhs.candidate.result.id
                }
                return lhs.candidate.sourceOrder < rhs.candidate.sourceOrder
            }
            .map(\.candidate.result)
    }
}

private struct RankedResult {
    let candidate: RankCandidate
    let preference: CommandPreference?
    let match: SearchMatch?
    let score: Double
    let usageBoost: Double
}
