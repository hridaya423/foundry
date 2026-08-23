import Foundation
import FoundryDomain

final class CommandRanker {
    private let usageRanking: UsageRankingStore
    private let configService: ConfigService?

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
        let normalizedQuery = query.map(SearchScoring.normalize)
        let usageBoosts = usageRanking.usageBoosts(for: candidates.map { $0.result.id }, query: query)

        return candidates
            .map { candidate in
                let preference = preferences[candidate.result.id]
                let match = normalizedQuery.flatMap { normalizedQuery in
                    SearchScoring.matchPrepared(
                        normalizedQuery: normalizedQuery,
                        normalizedTitle: candidate.result.normalizedSearchTitle,
                        normalizedSubtitle: candidate.result.normalizedSearchSubtitle,
                        normalizedKeywords: candidate.result.normalizedSearchKeywords,
                        normalizedAliases: candidate.result.normalizedSearchAliases + (preference?.aliases ?? []).map(SearchScoring.normalize),
                        sensitivity: sensitivity
                    )
                }
                return RankedResult(
                    candidate: candidate,
                    preference: preference,
                    match: match,
                    usageBoost: usageBoosts[candidate.result.id] ?? 0
                )
            }
            .sorted { lhs, rhs in
                if query == nil, lhs.preference?.favoriteRank != rhs.preference?.favoriteRank {
                    switch (lhs.preference?.favoriteRank, rhs.preference?.favoriteRank) {
                    case let (lhsRank?, rhsRank?):
                        if lhsRank != rhsRank { return lhsRank < rhsRank }
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    default:
                        break
                    }
                }

                if let lhsMatch = lhs.match, let rhsMatch = rhs.match, lhsMatch != rhsMatch {
                    let lhsIsBetter = SearchScoring.isBetter(lhsMatch, than: rhsMatch)
                    let rhsIsBetter = SearchScoring.isBetter(rhsMatch, than: lhsMatch)
                    if SearchScoring.areComparable(lhsMatch, rhsMatch), lhs.usageBoost != rhs.usageBoost {
                        return lhs.usageBoost > rhs.usageBoost
                    }
                    if lhsIsBetter || rhsIsBetter {
                        return lhsIsBetter
                    }
                } else if lhs.match != nil, rhs.match == nil {
                    return true
                } else if lhs.match == nil, rhs.match != nil {
                    return false
                }

                if lhs.usageBoost != rhs.usageBoost {
                    return lhs.usageBoost > rhs.usageBoost
                }
                if lhs.candidate.providerID != rhs.candidate.providerID {
                    return lhs.candidate.providerID < rhs.candidate.providerID
                }
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
    let usageBoost: Double
}
