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
}

public struct SearchMatch: Equatable, Sendable {
    public let kind: SearchMatchKind
    public let field: SearchMatchField
    public let tier: SearchMatchTier
    public let matchedTokenCount: Int
    public let exactTokenCount: Int
    public let queryTokenCount: Int
    public let queryLength: Int
    public let candidateLength: Int
    public let editDistance: Int?
    public let fuzzyScore: Int?
}

public enum SearchScoring {
    private static let alphanumerics = CharacterSet.alphanumerics
    private static let searchLocale = Locale(identifier: "en_US_POSIX")

    public static func match(query: String, title: String, aliases: [String] = [], allowFuzzy: Bool = true) -> SearchMatch? {
        let normalizedQuery = normalize(query)
        guard normalizedQuery.isEmpty == false else { return nil }
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
        let normalizedQuery = normalize(query)
        guard normalizedQuery.isEmpty == false else { return nil }
        return matchNormalized(
            query: normalizedQuery,
            title: title,
            subtitle: subtitle,
            keywords: keywords,
            aliases: aliases,
            sensitivity: sensitivity
        )
    }

    public static func match(
        normalizedQuery: String,
        title: String,
        subtitle: String?,
        keywords: [String],
        aliases: [String],
        sensitivity: SearchSensitivity = .medium
    ) -> SearchMatch? {
        guard normalizedQuery.isEmpty == false else { return nil }
        return matchNormalized(
            query: normalizedQuery,
            title: title,
            subtitle: subtitle,
            keywords: keywords,
            aliases: aliases,
            sensitivity: sensitivity
        )
    }

    public static func matchPrepared(
        normalizedQuery: String,
        normalizedTitle: String,
        normalizedSubtitle: String?,
        normalizedKeywords: [String],
        normalizedAliases: [String],
        sensitivity: SearchSensitivity = .medium
    ) -> SearchMatch? {
        guard normalizedQuery.isEmpty == false else { return nil }
        return matchNormalized(
            query: normalizedQuery,
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

    private static func matchNormalized(
        query: String,
        title: String,
        subtitle: String?,
        keywords: [String],
        aliases: [String],
        sensitivity: SearchSensitivity,
        allowFuzzy: Bool = true,
        valuesAreNormalized: Bool = false
    ) -> SearchMatch? {
        let queryTokens = query.split(separator: " ").map(String.init)
        guard queryTokens.isEmpty == false else { return nil }
        let aliasMatches = aliases.compactMap { aliasMatch(query: query, queryTokenCount: queryTokens.count, alias: valuesAreNormalized ? $0 : normalize($0)) }
        let titleMatches = [textMatch(query: query, queryTokens: queryTokens, candidate: title, field: .title, sensitivity: sensitivity, allowFuzzy: allowFuzzy, isNormalized: valuesAreNormalized)].compactMap { $0 }
        let subtitleMatches = [subtitle].compactMap { value in
            value.flatMap { textMatch(query: query, queryTokens: queryTokens, candidate: $0, field: .subtitle, sensitivity: sensitivity, allowFuzzy: allowFuzzy, isNormalized: valuesAreNormalized) }
        }
        let keywordMatches = keywords.compactMap { keyword in
            textMatch(query: query, queryTokens: queryTokens, candidate: keyword, field: .keyword, sensitivity: sensitivity, allowFuzzy: allowFuzzy, isNormalized: valuesAreNormalized)
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

    private static func textMatch(query: String, queryTokens: [String], candidate: String, field: SearchMatchField, sensitivity: SearchSensitivity, allowFuzzy: Bool, isNormalized: Bool = false) -> SearchMatch? {
        let normalizedCandidate = isNormalized ? candidate : normalize(candidate)
        guard normalizedCandidate.isEmpty == false else { return nil }

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

        let queryCharacters = queryTokens.map(Array.init)
        let candidateCharacters = candidateTokens.map(Array.init)
        var score = 0
        var editDistance = 0
        var exactTokenCount = 0
        var candidateIndex = 0
        let editLimit = sensitivity == .low || queryTokens.joined().count >= 6 ? 2 : 1
        for (tokenIndex, token) in queryTokens.enumerated() {
            var bestMatch: (index: Int, alignment: FuzzyAlignment, distance: Int?)?
            for index in candidateTokens.indices where index >= candidateIndex {
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

    public static func areComparable(_ lhs: SearchMatch, _ rhs: SearchMatch) -> Bool {
        guard lhs.tier == rhs.tier,
              lhs.exactTokenCount == rhs.exactTokenCount,
              lhs.matchedTokenCount == rhs.matchedTokenCount else { return false }
        switch (lhs.fuzzyScore, rhs.fuzzyScore) {
        case let (lhsScore?, rhsScore?): return abs(lhsScore - rhsScore) <= 24
        case (nil, nil): return true
        default: return false
        }
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
