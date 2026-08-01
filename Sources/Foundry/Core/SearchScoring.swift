import Foundation

enum SearchSensitivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case high
    case medium
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    var subtitle: String {
        switch self {
        case .high: "Fewer, closer matches"
        case .medium: "Balanced results"
        case .low: "Broader fuzzy matching"
        }
    }
}

enum SearchMatchKind: String, CaseIterable, Equatable, Sendable {
    case exact
    case phrasePrefix
    case tokenMatch
    case acronym
    case contains
    case fuzzy
}

enum SearchMatchField: String, CaseIterable, Equatable, Sendable {
    case alias
    case title
    case subtitle
    case keyword
}

enum SearchMatchTier: String, CaseIterable, Equatable, Sendable {
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
    static func < (lhs: SearchMatchTier, rhs: SearchMatchTier) -> Bool {
        guard let lhsIndex = allCases.firstIndex(of: lhs), let rhsIndex = allCases.firstIndex(of: rhs) else { return false }
        return lhsIndex < rhsIndex
    }
}

struct SearchMatch: Equatable, Sendable {
    let kind: SearchMatchKind
    let field: SearchMatchField
    let tier: SearchMatchTier
    let matchedTokenCount: Int
    let exactTokenCount: Int
    let queryTokenCount: Int
    let queryLength: Int
    let candidateLength: Int
    let editDistance: Int?
    let fuzzyScore: Int?
}

enum SearchScoring {
    static func match(query: String, title: String, aliases: [String] = [], allowFuzzy: Bool = true) -> SearchMatch? {
        let normalizedQuery = normalize(query)
        guard normalizedQuery.isEmpty == false else { return nil }
        return match(
            normalizedQuery: normalizedQuery,
            title: title,
            subtitle: nil,
            keywords: [],
            aliases: aliases,
            sensitivity: allowFuzzy ? .medium : .high,
            allowFuzzy: allowFuzzy
        )
    }

    static func match(
        query: String,
        title: String,
        subtitle: String?,
        keywords: [String],
        aliases: [String],
        sensitivity: SearchSensitivity = .medium
    ) -> SearchMatch? {
        let normalizedQuery = normalize(query)
        guard normalizedQuery.isEmpty == false else { return nil }
        return match(
            normalizedQuery: normalizedQuery,
            title: title,
            subtitle: subtitle,
            keywords: keywords,
            aliases: aliases,
            sensitivity: sensitivity
        )
    }

    static func normalize(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let normalized = folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar).lowercased() : " "
        }.joined()
        return normalized
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func match(
        normalizedQuery query: String,
        title: String,
        subtitle: String?,
        keywords: [String],
        aliases: [String],
        sensitivity: SearchSensitivity,
        allowFuzzy: Bool = true
    ) -> SearchMatch? {
        let aliasMatches = aliases.compactMap { aliasMatch(query: query, alias: normalize($0)) }
        let titleMatches = [textMatch(query: query, candidate: title, field: .title, sensitivity: sensitivity, allowFuzzy: allowFuzzy)].compactMap { $0 }
        let subtitleMatches = [subtitle].compactMap { value in
            value.flatMap { textMatch(query: query, candidate: $0, field: .subtitle, sensitivity: sensitivity, allowFuzzy: allowFuzzy) }
        }
        let keywordMatches = keywords.compactMap { keyword in
            textMatch(query: query, candidate: keyword, field: .keyword, sensitivity: sensitivity, allowFuzzy: allowFuzzy)
        }

        return (aliasMatches + titleMatches + subtitleMatches + keywordMatches)
            .max { isBetter($1, than: $0) }
    }

    private static func aliasMatch(query: String, alias: String) -> SearchMatch? {
        guard alias.isEmpty == false else { return nil }
        let queryTokenCount = query.split(separator: " ").count
        if alias == query {
            return SearchMatch(
                kind: .exact,
                field: .alias,
                tier: .aliasExact,
                matchedTokenCount: queryTokenCount,
                exactTokenCount: queryTokenCount,
                queryTokenCount: queryTokenCount,
                queryLength: query.count,
                candidateLength: alias.count,
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
            exactTokenCount: queryTokenCount,
            queryTokenCount: queryTokenCount,
            queryLength: query.count,
            candidateLength: alias.count,
            editDistance: nil,
            fuzzyScore: nil
        )
    }

    private static func textMatch(query: String, candidate: String, field: SearchMatchField, sensitivity: SearchSensitivity, allowFuzzy: Bool) -> SearchMatch? {
        let normalizedCandidate = normalize(candidate)
        guard normalizedCandidate.isEmpty == false else { return nil }

        let queryTokens = query.split(separator: " ").map(String.init)
        let candidateTokens = normalizedCandidate.split(separator: " ").map(String.init)
        guard queryTokens.isEmpty == false, candidateTokens.isEmpty == false else { return nil }

        let details: MatchDetails
        if normalizedCandidate == query {
            details = MatchDetails(kind: .exact, matchedTokenCount: queryTokens.count, exactTokenCount: queryTokens.count, editDistance: 0, fuzzyScore: nil)
        } else if normalizedCandidate.hasPrefix(query + " ") || normalizedCandidate.hasPrefix(query) {
            details = MatchDetails(kind: .phrasePrefix, matchedTokenCount: queryTokens.count, exactTokenCount: queryTokens.count, editDistance: nil, fuzzyScore: nil)
        } else if let tokenDetails = tokenMatchDetails(queryTokens: queryTokens, candidateTokens: candidateTokens) {
            details = tokenDetails
        } else if let compactTokenDetails = compactTokenMatchDetails(queryTokens: queryTokens, candidateTokens: candidateTokens) {
            details = compactTokenDetails
        } else {
            let acronym = candidateTokens.compactMap(\.first).map(String.init).joined()
            if queryTokens.count == 1, acronym.hasPrefix(query), query.count >= 2 {
                details = MatchDetails(kind: .acronym, matchedTokenCount: queryTokens.count, exactTokenCount: 0, editDistance: nil, fuzzyScore: nil)
            } else if query.count >= 2, normalizedCandidate.contains(query) {
                details = MatchDetails(kind: .contains, matchedTokenCount: queryTokens.count, exactTokenCount: 0, editDistance: nil, fuzzyScore: nil)
            } else {
                guard allowFuzzy,
                      let fuzzy = fuzzyDetails(queryTokens: queryTokens, candidateTokens: candidateTokens, sensitivity: sensitivity) else {
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
            exactTokenCount: details.exactTokenCount,
            queryTokenCount: queryTokens.count,
            queryLength: query.count,
            candidateLength: normalizedCandidate.count,
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

    private static func fuzzyDetails(queryTokens: [String], candidateTokens: [String], sensitivity: SearchSensitivity) -> MatchDetails? {
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

        var score = 0
        var editDistance = 0
        var exactTokenCount = 0
        var candidateIndex = 0
        let editLimit = sensitivity == .low || queryTokens.joined().count >= 6 ? 2 : 1
        for token in queryTokens {
            var bestMatch: (index: Int, alignment: FuzzyAlignment)?
            for index in candidateTokens.indices where index >= candidateIndex {
                let alignment: FuzzyAlignment?
                if let fuzzyAlignment = fuzzyAlignment(pattern: token, candidate: candidateTokens[index]) {
                    alignment = fuzzyAlignment
                } else {
                    let distance = editDistanceBetween(token, candidateTokens[index])
                    alignment = distance <= editLimit
                        ? FuzzyAlignment(score: max(1, 64 - distance * 20 - abs(token.count - candidateTokens[index].count) * 2))
                        : nil
                }
                guard let alignment else { continue }
                if bestMatch == nil || alignment.score > bestMatch!.alignment.score {
                    bestMatch = (index, alignment)
                }
            }
            guard let bestMatch else { return nil }
            candidateIndex = bestMatch.index + 1
            let alignment = bestMatch.alignment
            score += alignment.score
            let tokenDistance = editDistanceBetween(token, candidateTokens[bestMatch.index])
            editDistance += tokenDistance
            if candidateTokens[bestMatch.index] == token { exactTokenCount += 1 }

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

    private static func fuzzyAlignment(pattern: String, candidate: String) -> FuzzyAlignment? {
        let patternCharacters = Array(pattern)
        let candidateCharacters = Array(candidate)
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

    private static func boundaryBonus(at index: Int, in candidate: [Character]) -> Int {
        guard index == 0 else {
            let previous = candidate[index - 1]
            return previous.isLetter || previous.isNumber ? 0 : 8
        }
        return 8
    }

    private static func tokenMatchDetails(queryTokens: [String], candidateTokens: [String]) -> MatchDetails? {
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

    private static func compactTokenMatchDetails(queryTokens: [String], candidateTokens: [String]) -> MatchDetails? {
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

    static func isBetter(_ lhs: SearchMatch, than rhs: SearchMatch) -> Bool {
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

    static func areComparable(_ lhs: SearchMatch, _ rhs: SearchMatch) -> Bool {
        guard lhs.tier == rhs.tier,
              lhs.exactTokenCount == rhs.exactTokenCount,
              lhs.matchedTokenCount == rhs.matchedTokenCount else { return false }
        switch (lhs.fuzzyScore, rhs.fuzzyScore) {
        case let (lhsScore?, rhsScore?): return abs(lhsScore - rhsScore) <= 24
        case (nil, nil): return true
        default: return false
        }
    }

    private static func editDistanceBetween(_ lhs: String, _ rhs: String) -> Int {
        let lhsCharacters = Array(lhs)
        let rhsCharacters = Array(rhs)
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

    private static func compact(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "")
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remaining = needle[...]
        for character in haystack where remaining.first == character {
            remaining.removeFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
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
