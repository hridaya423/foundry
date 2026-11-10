import Foundation

public enum SearchSensitivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case high
    case medium
    case low

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    public var subtitle: String {
        switch self {
        case .high: "Fewer, closer matches"
        case .medium: "Balanced results"
        case .low: "Broader fuzzy matching"
        }
    }
}

public enum SearchMatchKind: String, CaseIterable, Equatable, Sendable {
    case exact
    case phrasePrefix
    case tokenMatch
    case acronym
    case contains
    case fuzzy
}

public enum SearchMatchField: String, CaseIterable, Equatable, Sendable {
    case alias
    case title
    case subtitle
    case keyword
}

public enum SearchMatchTier: String, CaseIterable, Equatable, Sendable {
    case aliasExact
    case aliasPrefix
    case titleExact
    case titlePrefix
    case titleToken
    case titleAcronym
    case titleContains
    case titleFuzzy
    case subtitle
    case keyword
}

extension SearchMatchTier: Comparable {
    public static func < (lhs: SearchMatchTier, rhs: SearchMatchTier) -> Bool {
        guard let lhsIndex = allCases.firstIndex(of: lhs), let rhsIndex = allCases.firstIndex(of: rhs) else { return false }
        return lhsIndex < rhsIndex
    }

    /// Scalar rank weight: the single number that decides result order.
    /// Word-boundary and prefix matches dominate mid-word substrings, which
    /// dominate fuzzy/keyword hits. Adjacent tiers are at least 0.15 apart
    /// so bounded usage frecency (< 0.15) can reorder within a tier but can
    /// never vault a weaker match over a stronger one.
    public var score: Double {
        switch self {
        case .aliasExact: 1.90
        case .titleExact: 1.70
        case .aliasPrefix: 1.50
        case .titlePrefix: 1.30
        case .titleToken: 1.10
        case .titleAcronym: 0.95
        case .titleContains: 0.75
        case .subtitle: 0.60
        case .titleFuzzy: 0.42
        case .keyword: 0.25
        }
    }
}

extension SearchMatch {
    /// Scalar rank value: tier sets the band, fuzzy alignment quality
    /// (word-boundary bonuses) nudges within the band — always under the
    /// 0.15 minimum tier gap, so it can never cross a tier boundary.
    public var score: Double {
        tier.score + Double(min(fuzzyScore ?? 0, 200)) / 200 * 0.10
    }
}

public struct SearchMatch: Equatable, Sendable {
    public let kind: SearchMatchKind
    public let field: SearchMatchField
    public let tier: SearchMatchTier
    public let matchedTokenCount: Int
    public let exactTokenCount: Int
    public let candidateLength: Int
    public let editDistance: Int?
    public let fuzzyScore: Int?
}

public enum SearchScoring {
    private static let alphanumerics = CharacterSet.alphanumerics
    private static let searchLocale = Locale(identifier: "en_US_POSIX")

    public struct PreparedQuery: Sendable {
        public let normalized: String
        let tokens: [String]
        let tokenCharacters: [[Character]]
        /// Character multiset lower bound per token — lets the fuzzy matcher
        /// and ``probableMatch`` skip provably-impossible candidates.
        /// prove "impossible" pairs in one instruction instead of running the
        /// alignment/edit-distance dynamic programs.
        public let tokenMasks: [UInt64]

        public init(query: String) {
            self.init(normalized: SearchScoring.normalize(query))
        }

        public init(normalized: String) {
            self.normalized = normalized
            tokens = normalized.split(separator: " ").map(String.init)
            tokenCharacters = tokens.map(Array.init)
            tokenMasks = tokenCharacters.map(SearchScoring.characterMask)
        }
    }

    public static func match(query: String, title: String, aliases: [String] = [], allowFuzzy: Bool = true) -> SearchMatch? {
        let normalizedQuery = PreparedQuery(query: query)
        guard normalizedQuery.normalized.isEmpty == false else { return nil }
        return matchNormalized(
            query: normalizedQuery,
            title: title,
            subtitle: nil,
            keywords: [],
            aliases: aliases,
            sensitivity: allowFuzzy ? .medium : .high,
            allowFuzzy: allowFuzzy
        )
    }

    public static func match(
        query: String,
        title: String,
        subtitle: String?,
        keywords: [String],
        aliases: [String],
        sensitivity: SearchSensitivity = .medium
    ) -> SearchMatch? {
        match(query: PreparedQuery(query: query), title: title, subtitle: subtitle,
            keywords: keywords, aliases: aliases, sensitivity: sensitivity)
    }

    /// Prepared-query variant — providers scoring a catalog should build the
    /// `PreparedQuery` once per search instead of re-normalizing the query
    /// against every candidate.
    public static func match(
        query: PreparedQuery,
        title: String,
        subtitle: String?,
        keywords: [String],
        aliases: [String],
        sensitivity: SearchSensitivity = .medium
    ) -> SearchMatch? {
        guard query.normalized.isEmpty == false else { return nil }
        return matchNormalized(
            query: query,
            title: title,
            subtitle: subtitle,
            keywords: keywords,
            aliases: aliases,
            sensitivity: sensitivity
        )
    }

    public static func matchPrepared(
        query: PreparedQuery,
        normalizedTitle: String,
        normalizedSubtitle: String?,
        normalizedKeywords: [String],
        normalizedAliases: [String],
        sensitivity: SearchSensitivity = .medium
    ) -> SearchMatch? {
        guard query.normalized.isEmpty == false else { return nil }
        return matchNormalized(
            query: query,
            title: normalizedTitle,
            subtitle: normalizedSubtitle,
            keywords: normalizedKeywords,
            aliases: normalizedAliases,
            sensitivity: sensitivity,
            valuesAreNormalized: true
        )
    }

    public static func normalize(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: searchLocale
        )
        let lowercased = folded.lowercased(with: searchLocale)
        var normalized = String()
        normalized.reserveCapacity(lowercased.utf8.count)
        var needsSeparator = false
        for scalar in lowercased.unicodeScalars {
            guard alphanumerics.contains(scalar) else {
                if normalized.isEmpty == false { needsSeparator = true }
                continue
            }
            if needsSeparator { normalized.append(" ") }
            normalized.unicodeScalars.append(scalar)
            needsSeparator = false
        }
        return normalized
    }

    public static func payload(in query: String, prefixes: [String]) -> String? {
        let normalizedQuery = normalize(query)
        for prefix in prefixes {
            let normalizedPrefix = normalize(prefix)
            if normalizedQuery == normalizedPrefix { return "" }
            guard normalizedQuery.hasPrefix(normalizedPrefix + " ") else { continue }
            let foldedQuery = query.folding(options: [.diacriticInsensitive], locale: searchLocale)
            var emitted = 0
            var needsSeparator = false
            var payloadStart = foldedQuery.endIndex
            let scalars = foldedQuery.unicodeScalars
            for index in scalars.indices {
                guard alphanumerics.contains(scalars[index]) else {
                    if emitted > 0 { needsSeparator = true }
                    continue
                }
                if emitted == normalizedPrefix.count { payloadStart = index; break }
                if needsSeparator { emitted += 1; needsSeparator = false }
                emitted += 1
            }
            return String(foldedQuery[payloadStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func matchNormalized(
        query: PreparedQuery,
        title: String,
        subtitle: String?,
        keywords: [String],
        aliases: [String],
        sensitivity: SearchSensitivity,
        allowFuzzy: Bool = true,
        valuesAreNormalized: Bool = false
    ) -> SearchMatch? {
        let queryTokens = query.tokens
        guard queryTokens.isEmpty == false else { return nil }
        let aliasMatches = aliases.compactMap { aliasMatch(query: query.normalized, queryTokenCount: queryTokens.count,
            alias: valuesAreNormalized ? $0 : normalize($0)) }
        let titleMatches = [textMatch(query: query, candidate: title, field: .title, sensitivity: sensitivity, allowFuzzy: allowFuzzy,
            isNormalized: valuesAreNormalized)].compactMap { $0 }
        let subtitleMatches = [subtitle].compactMap { value in
            value.flatMap { textMatch(query: query, candidate: $0, field: .subtitle, sensitivity: sensitivity, allowFuzzy: allowFuzzy,
                isNormalized: valuesAreNormalized) }
        }
        let keywordMatches = keywords.compactMap { keyword in
            textMatch(query: query, candidate: keyword, field: .keyword, sensitivity: sensitivity, allowFuzzy: allowFuzzy, isNormalized: valuesAreNormalized)
        }

        return (aliasMatches + titleMatches + subtitleMatches + keywordMatches)
            .max { isBetter($1, than: $0) }
    }

    private static func aliasMatch(query: String, queryTokenCount: Int, alias: String) -> SearchMatch? {
        guard alias.isEmpty == false else { return nil }
        if alias == query {
            return SearchMatch(
                kind: .exact,
                field: .alias,
                tier: .aliasExact,
                matchedTokenCount: queryTokenCount,
                exactTokenCount: queryTokenCount,                candidateLength: alias.count,
                editDistance: 0,
                fuzzyScore: nil
            )
        }

        guard query.count >= 3, alias.hasPrefix(query) || query.hasPrefix(alias + " ") else { return nil }
        return SearchMatch(
            kind: .phrasePrefix,
            field: .alias,
            tier: .aliasPrefix,
            matchedTokenCount: queryTokenCount,
            exactTokenCount: queryTokenCount,            candidateLength: alias.count,
            editDistance: nil,
            fuzzyScore: nil
        )
    }

    private static func textMatch(query: PreparedQuery, candidate: String, field: SearchMatchField, sensitivity: SearchSensitivity, allowFuzzy: Bool,
        isNormalized: Bool = false) -> SearchMatch? {
        let normalizedCandidate = isNormalized ? candidate : normalize(candidate)
        guard normalizedCandidate.isEmpty == false else { return nil }
        // Field-level coverability: no query token may be further than
        // `editLimit` characters outside this field's character multiset.
        // Sound for every match kind — non-fuzzy kinds need zero misses.
        guard probableMatch(query: query, searchableMask: characterMask(normalizedCandidate), sensitivity: sensitivity) else { return nil }
        let queryString = query.normalized
        let queryTokens = query.tokens

        let candidateTokens = normalizedCandidate.split(separator: " ")
        guard queryTokens.isEmpty == false, candidateTokens.isEmpty == false else { return nil }

        let details: MatchDetails
        if normalizedCandidate == queryString {
            details = MatchDetails(kind: .exact, matchedTokenCount: queryTokens.count, exactTokenCount: queryTokens.count, editDistance: 0, fuzzyScore: nil)
        } else if normalizedCandidate.hasPrefix(queryString + " ") || normalizedCandidate.hasPrefix(queryString) {
            details = MatchDetails(kind: .phrasePrefix, matchedTokenCount: queryTokens.count, exactTokenCount: queryTokens.count, editDistance: nil,
                fuzzyScore: nil)
        } else if let tokenDetails = tokenMatchDetails(queryTokens: queryTokens, candidateTokens: candidateTokens) {
            details = tokenDetails
        } else if let compactTokenDetails = compactTokenMatchDetails(queryTokens: queryTokens, candidateTokens: candidateTokens) {
            details = compactTokenDetails
        } else {
            let acronym = String(candidateTokens.compactMap(\.first))
            if queryTokens.count == 1, acronym.hasPrefix(queryString), queryString.count >= 2 {
                details = MatchDetails(kind: .acronym, matchedTokenCount: queryTokens.count, exactTokenCount: 0, editDistance: nil, fuzzyScore: nil)
            } else if queryString.count >= 2, normalizedCandidate.contains(queryString) {
                details = MatchDetails(kind: .contains, matchedTokenCount: queryTokens.count, exactTokenCount: 0, editDistance: nil, fuzzyScore: nil)
            } else {
                guard allowFuzzy,
                      let fuzzy = fuzzyDetails(query: query,
                          candidateTokens: candidateTokens, sensitivity: sensitivity) else {
                    return nil
                }
                details = fuzzy
            }
        }

        return SearchMatch(
            kind: details.kind,
            field: field,
            tier: tier(for: field, kind: details.kind),
            matchedTokenCount: details.matchedTokenCount,
            exactTokenCount: details.exactTokenCount,            candidateLength: normalizedCandidate.count,
            editDistance: details.editDistance,
            fuzzyScore: details.fuzzyScore
        )
    }

    private static func tier(for field: SearchMatchField, kind: SearchMatchKind) -> SearchMatchTier {
        switch field {
        case .title:
            switch kind {
            case .exact: .titleExact
            case .phrasePrefix: .titlePrefix
            case .tokenMatch: .titleToken
            case .acronym: .titleAcronym
            case .contains: .titleContains
            case .fuzzy: .titleFuzzy
            }
        case .subtitle: .subtitle
        case .keyword: .keyword
        case .alias: kind == .exact ? .aliasExact : .aliasPrefix
        }
    }

    private static func fuzzyDetails(query: PreparedQuery, candidateTokens: [Substring],
        sensitivity: SearchSensitivity) -> MatchDetails? {
        let queryTokens = query.tokens
        let minimumQueryLength: Int
        let densityThreshold: Double
        switch sensitivity {
        case .high:
            minimumQueryLength = 4
            densityThreshold = 0.62
        case .medium:
            minimumQueryLength = 2
            densityThreshold = 0.25
        case .low:
            minimumQueryLength = 2
            densityThreshold = 0.15
        }
        guard queryTokens.allSatisfy({ $0.count >= minimumQueryLength || queryTokens.count > 1 }) else { return nil }

        let queryCharacters = query.tokenCharacters
        let candidateCharacters = candidateTokens.map(Array.init)
        let candidateMasks = candidateCharacters.map(characterMask)
        var score = 0
        var editDistance = 0
        var exactTokenCount = 0
        var candidateIndex = 0
        let editLimit = fuzzyEditLimit(queryTokens: queryTokens, sensitivity: sensitivity)
        for (tokenIndex, token) in queryTokens.enumerated() {
            var bestMatch: (index: Int, alignment: FuzzyAlignment, distance: Int?)?
            for index in candidateTokens.indices where index >= candidateIndex {
                // A pair can only match within `editLimit` edits if at most
                // `editLimit` query characters are absent from the candidate —
                // the mask difference is a lower bound on the true distance,
                // so this skips provably-impossible pairs without the DP.
                if (query.tokenMasks[tokenIndex] & ~candidateMasks[index]).nonzeroBitCount > editLimit { continue }
                let alignment: FuzzyAlignment?
                let distance: Int?
                if let fuzzyAlignment = fuzzyAlignment(pattern: queryCharacters[tokenIndex], candidate: candidateCharacters[index]) {
                    alignment = fuzzyAlignment
                    distance = nil
                } else {
                    let editDistance = editDistanceWithin(
                        queryCharacters[tokenIndex],
                        candidateCharacters[index],
                        limit: editLimit
                    )
                    alignment = editDistance <= editLimit
                        ? FuzzyAlignment(score: max(1, 64 - editDistance * 20 - abs(token.count - candidateTokens[index].count) * 2))
                        : nil
                    distance = editDistance <= editLimit ? editDistance : nil
                }
                guard let alignment else { continue }
                if bestMatch == nil || alignment.score > bestMatch!.alignment.score {
                    bestMatch = (index, alignment, distance)
                }
            }
            guard let bestMatch else { return nil }
            candidateIndex = bestMatch.index + 1
            let alignment = bestMatch.alignment
            score += alignment.score
            let tokenDistance = bestMatch.distance ?? editDistanceBetween(queryCharacters[tokenIndex], candidateCharacters[bestMatch.index])
            editDistance += tokenDistance
            if candidateTokens[bestMatch.index].elementsEqual(token) { exactTokenCount += 1 }

            let density = Double(token.count) / Double(max(candidateTokens[bestMatch.index].count, 1))
            guard density >= densityThreshold else { return nil }
        }

        return MatchDetails(
            kind: .fuzzy,
            matchedTokenCount: queryTokens.count,
            exactTokenCount: exactTokenCount,
            editDistance: editDistance,
            fuzzyScore: score / queryTokens.count
        )
    }

    private static func fuzzyAlignment(pattern patternCharacters: [Character], candidate candidateCharacters: [Character]) -> FuzzyAlignment? {
        guard patternCharacters.isEmpty == false, patternCharacters.count <= candidateCharacters.count else { return nil }

        let impossible = Int.min / 4
        var previous = Array(repeating: impossible, count: candidateCharacters.count)

        for (patternIndex, patternCharacter) in patternCharacters.enumerated() {
            var current = Array(repeating: impossible, count: candidateCharacters.count)
            var bestGapPrefix = impossible

            for candidateIndex in candidateCharacters.indices {
                guard patternCharacter == candidateCharacters[candidateIndex] else {
                    if patternIndex > 0, candidateIndex >= 2, previous[candidateIndex - 2] > impossible {
                        bestGapPrefix = max(bestGapPrefix, previous[candidateIndex - 2] + candidateIndex - 2)
                    }
                    continue
                }

                let boundary = boundaryBonus(at: candidateIndex, in: candidateCharacters)
                let matchScore = 16 + boundary
                if patternIndex == 0 {
                    current[candidateIndex] = matchScore + (candidateIndex == 0 || boundary > 0 ? boundary : 0)
                } else {
                    if candidateIndex >= 1, previous[candidateIndex - 1] > impossible {
                        current[candidateIndex] = max(current[candidateIndex], previous[candidateIndex - 1] + matchScore + 4)
                    }
                    if candidateIndex >= 2, previous[candidateIndex - 2] > impossible {
                        bestGapPrefix = max(bestGapPrefix, previous[candidateIndex - 2] + candidateIndex - 2)
                    }
                    if bestGapPrefix > impossible {
                        current[candidateIndex] = max(current[candidateIndex], bestGapPrefix - candidateIndex - 1 + matchScore)
                    }
                }
            }

            previous = current
        }

        guard let score = previous.max(), score > impossible else { return nil }
        return FuzzyAlignment(score: score)
    }

    /// Necessary condition for ANY match kind: every query token's characters
    /// must be coverable by the candidate blob within `editLimit` misses —
    /// the mask difference lower-bounds edit distance. Providers iterating a
    /// catalog can precompute one mask per item (title + subtitle + keywords)
    /// and skip `match`/`matchPrepared` entirely for impossible candidates.
    public static func probableMatch(query: PreparedQuery, searchableMask: UInt64, sensitivity: SearchSensitivity = .medium) -> Bool {
        let limit = fuzzyEditLimit(queryTokens: query.tokens, sensitivity: sensitivity)
        return query.tokenMasks.allSatisfy { ($0 & ~searchableMask).nonzeroBitCount <= limit }
    }

    /// 64-bit character multiset bound: a-z → bits 0-25, 0-9 → 26-35, any
    /// other scalar → bit 63. `a & ~b` popcount is a lower bound on how many
    /// `a` characters cannot be covered by `b`, which bounds edit distance.
    public static func characterMask(_ value: String) -> UInt64 {
        var mask: UInt64 = 0
        for scalar in value.unicodeScalars {
            switch scalar {
            case "a"..."z": mask |= 1 &<< (scalar.value - 97)
            case "0"..."9": mask |= 1 &<< (scalar.value - 48 + 26)
            default: mask |= 1 &<< 63
            }
        }
        return mask
    }

    private static func characterMask(_ characters: [Character]) -> UInt64 {
        characterMask(String(characters))
    }

    private static func fuzzyEditLimit(queryTokens: [String], sensitivity: SearchSensitivity) -> Int {
        sensitivity == .low || queryTokens.joined().count >= 6 ? 2 : 1
    }

    private static func boundaryBonus(at index: Int, in candidate: [Character]) -> Int {
        guard index == 0 else {
            let previous = candidate[index - 1]
            return previous.isLetter || previous.isNumber ? 0 : 8
        }
        return 8
    }

    private static func tokenMatchDetails(queryTokens: [String], candidateTokens: [Substring]) -> MatchDetails? {
        guard queryTokens.count <= candidateTokens.count else { return nil }

        var candidateIndex = 0
        var matchedExact = 0
        for queryToken in queryTokens {
            guard let index = candidateTokens[candidateIndex...].firstIndex(where: { $0 == queryToken || $0.hasPrefix(queryToken) }) else {
                return nil
            }
            if candidateTokens[index] == queryToken { matchedExact += 1 }
            candidateIndex = index + 1
        }

        return MatchDetails(kind: .tokenMatch, matchedTokenCount: queryTokens.count, exactTokenCount: matchedExact, editDistance: nil, fuzzyScore: nil)
    }

    private static func compactTokenMatchDetails(queryTokens: [String], candidateTokens: [Substring]) -> MatchDetails? {
        var candidateIndex = 0
        var matchedExact = 0

        for queryToken in queryTokens {
            if let index = candidateTokens[candidateIndex...].firstIndex(where: { $0 == queryToken || $0.hasPrefix(queryToken) }) {
                if candidateTokens[index] == queryToken { matchedExact += 1 }
                candidateIndex = index + 1
                continue
            }

            guard candidateIndex < candidateTokens.count else { return nil }
            var compacted = ""
            var endIndex = candidateIndex
            var matchEnd: Int?
            while endIndex < candidateTokens.count {
                compacted += candidateTokens[endIndex]
                if compacted == queryToken {
                    matchEnd = endIndex
                    break
                }
                if compacted.count >= queryToken.count { break }
                endIndex += 1
            }
            guard let matchEnd else { return nil }
            candidateIndex = matchEnd + 1
        }

        return MatchDetails(kind: .tokenMatch, matchedTokenCount: queryTokens.count, exactTokenCount: matchedExact, editDistance: nil, fuzzyScore: nil)
    }

    public static func isBetter(_ lhs: SearchMatch, than rhs: SearchMatch) -> Bool {
        if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
        if lhs.kind != rhs.kind {
            return SearchMatchKind.allCases.firstIndex(of: lhs.kind)! < SearchMatchKind.allCases.firstIndex(of: rhs.kind)!
        }
        if lhs.fuzzyScore != rhs.fuzzyScore {
            switch (lhs.fuzzyScore, rhs.fuzzyScore) {
            case let (lhsScore?, rhsScore?): return lhsScore > rhsScore
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
        }
        if lhs.exactTokenCount != rhs.exactTokenCount { return lhs.exactTokenCount > rhs.exactTokenCount }
        if lhs.matchedTokenCount != rhs.matchedTokenCount { return lhs.matchedTokenCount > rhs.matchedTokenCount }
        if let lhsDistance = lhs.editDistance, let rhsDistance = rhs.editDistance, lhsDistance != rhsDistance {
            return lhsDistance < rhsDistance
        }
        if lhs.editDistance != nil, rhs.editDistance == nil { return false }
        if lhs.candidateLength != rhs.candidateLength { return lhs.candidateLength < rhs.candidateLength }
        return SearchMatchKind.allCases.firstIndex(of: lhs.kind)! < SearchMatchKind.allCases.firstIndex(of: rhs.kind)!
    }

    private static func editDistanceBetween(_ lhsCharacters: [Character], _ rhsCharacters: [Character]) -> Int {
        guard lhsCharacters.isEmpty == false else { return rhsCharacters.count }
        guard rhsCharacters.isEmpty == false else { return lhsCharacters.count }

        var previous = Array(0...rhsCharacters.count)
        for (lhsIndex, lhsCharacter) in lhsCharacters.enumerated() {
            var current = [lhsIndex + 1]
            for (rhsIndex, rhsCharacter) in rhsCharacters.enumerated() {
                let insertion = current[rhsIndex] + 1
                let deletion = previous[rhsIndex + 1] + 1
                let substitution = previous[rhsIndex] + (lhsCharacter == rhsCharacter ? 0 : 1)
                current.append(min(insertion, deletion, substitution))
            }
            previous = current
        }
        return previous[rhsCharacters.count]
    }

    private static func editDistanceWithin(_ lhs: [Character], _ rhs: [Character], limit: Int) -> Int {
        guard abs(lhs.count - rhs.count) <= limit else { return limit + 1 }
        var previous = Array(0...rhs.count)
        for (lhsIndex, lhsCharacter) in lhs.enumerated() {
            var current = [lhsIndex + 1]
            current.reserveCapacity(rhs.count + 1)
            var rowMinimum = current[0]
            for (rhsIndex, rhsCharacter) in rhs.enumerated() {
                let insertion = current[rhsIndex] + 1
                let deletion = previous[rhsIndex + 1] + 1
                let substitution = previous[rhsIndex] + (lhsCharacter == rhsCharacter ? 0 : 1)
                let value = min(insertion, deletion, substitution)
                current.append(value)
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > limit { return limit + 1 }
            previous = current
        }
        return previous[rhs.count]
    }

    private struct MatchDetails {
        let kind: SearchMatchKind
        let matchedTokenCount: Int
        let exactTokenCount: Int
        let editDistance: Int?
        let fuzzyScore: Int?
    }

    private struct FuzzyAlignment {
        let score: Int
    }
}
